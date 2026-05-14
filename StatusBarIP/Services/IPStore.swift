import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class IPStore: ObservableObject {
    @Published private(set) var entries: [IPEntry] = []
    @Published private(set) var publicResponse: PublicIPResponse?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isInternetAvailable = true
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginError: String?
    @Published var copiedID: String?
    @Published var settings: AppSettings {
        didSet {
            settingsStore.save(settings)
            applyDockPolicy()
            rebuildEntries()
            restartTimer()
        }
    }

    private let publicFetcher: PublicIPFetching
    private let localProvider: LocalIPProviding
    private let settingsStore: SettingsStoring
    private let networkMonitor: NetworkMonitoring
    private var timer: Timer?
    private var reconnectRetryTask: Task<Void, Never>?
    private var localEntries: [IPEntry] = []

    init(
        publicFetcher: PublicIPFetching = PublicIPService(),
        localProvider: LocalIPProviding = LocalIPService(),
        settingsStore: SettingsStoring = UserDefaultsSettingsStore(),
        networkMonitor: NetworkMonitoring = NetworkMonitorService()
    ) {
        self.publicFetcher = publicFetcher
        self.localProvider = localProvider
        self.settingsStore = settingsStore
        self.networkMonitor = networkMonitor
        self.settings = settingsStore.load()
        configureNetworkMonitor()
        applyDockPolicy()
        refreshLaunchAtLoginStatus()
        refreshLocalEntries()
        restartTimer()
    }

    var visibleEntries: [IPEntry] {
        orderedEntries.filter { !settings.hiddenIDs.contains($0.id) }
    }

    var statusEntry: IPEntry? {
        visibleEntries.first
    }

    var orderedEntries: [IPEntry] {
        sorted(entries: entries, orderedIDs: settings.orderedIDs)
    }

    func start() {
        networkMonitor.start()
        Task { await refreshPublicIP() }
    }

    func refreshAll() {
        refreshLocalEntries()
        Task { await refreshPublicIP() }
    }

    func refreshLocalEntries() {
        localEntries = localProvider.currentEntries()
        rebuildEntries()
    }

    func refreshPublicIP() async {
        guard isInternetAvailable else {
            publicResponse = nil
            lastError = "No internet"
            rebuildEntries()
            return
        }

        do {
            let response = try await publicFetcher.fetch()
            publicResponse = response
            lastUpdated = Date()
            lastError = nil
            rebuildEntries()
        } catch {
            lastError = error.localizedDescription
            rebuildEntries()
        }
    }

    func copy(_ entry: IPEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.address, forType: .string)
        copiedID = entry.id

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copiedID == entry.id {
                copiedID = nil
            }
        }
    }

    func setHidden(_ entry: IPEntry, hidden: Bool) {
        if hidden {
            settings.hiddenIDs.insert(entry.id)
        } else {
            settings.hiddenIDs.remove(entry.id)
        }
    }

    func moveEntry(from source: IndexSet, to destination: Int) {
        var ids = orderedEntries.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        settings.orderedIDs = ids
    }

    func moveEntry(_ entry: IPEntry, direction: MoveDirection) {
        var ids = orderedEntries.map(\.id)
        guard let index = ids.firstIndex(of: entry.id) else { return }
        let newIndex: Int

        switch direction {
        case .up:
            newIndex = max(index - 1, 0)
        case .down:
            newIndex = min(index + 1, ids.count - 1)
        }

        guard newIndex != index else { return }
        ids.swapAt(index, newIndex)
        settings.orderedIDs = ids
    }

    func setFetchInterval(_ value: Double) {
        settings.fetchInterval = max(value, AppSettings.minimumFetchInterval)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }

        refreshLaunchAtLoginStatus()
    }

    private func configureNetworkMonitor() {
        networkMonitor.onStatusChange = { [weak self] isConnected in
            guard let self else { return }
            isInternetAvailable = isConnected

            if isConnected {
                lastError = nil
                refreshAll()
                scheduleReconnectRetries()
            } else {
                reconnectRetryTask?.cancel()
                publicResponse = nil
                lastError = "No internet"
                refreshLocalEntries()
            }
        }
    }

    private func scheduleReconnectRetries() {
        reconnectRetryTask?.cancel()
        reconnectRetryTask = Task { [weak self] in
            for delay in [1.5, 4.0, 8.0, 15.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self?.refreshLocalEntries()
                }

                guard let self else { return }
                guard isInternetAvailable else { return }
                guard publicResponse == nil || lastError != nil else { return }

                await refreshPublicIP()
            }
        }
    }

    private func rebuildEntries() {
        var next: [IPEntry] = []

        if let publicResponse {
            let detail = [publicResponse.city, publicResponse.countryName, publicResponse.asOrganization]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            next.append(
                IPEntry(
                    id: AdapterKind.publicIP.rawValue,
                    kind: .publicIP,
                    title: "Public IP",
                    subtitle: detail.isEmpty ? "ip.faster.asia" : detail,
                    address: publicResponse.ip,
                    interfaceName: nil,
                    metadata: publicResponse.timezone
                )
            )
        } else {
            next.append(
                IPEntry(
                    id: AdapterKind.publicIP.rawValue,
                    kind: .publicIP,
                    title: "Public IP",
                    subtitle: lastError == nil ? "Fetching..." : "Fetch failed",
                    address: "Unavailable",
                    interfaceName: nil,
                    metadata: lastError
                )
            )
        }

        next.append(contentsOf: localEntries)
        entries = sorted(entries: next, orderedIDs: settings.orderedIDs)
        mergeKnownIDs(next.map(\.id))
    }

    private func mergeKnownIDs(_ currentIDs: [String]) {
        var ids = settings.orderedIDs
        var changed = false

        for defaultID in AdapterKind.defaultOrder.map(\.rawValue) where !ids.contains(defaultID) {
            ids.append(defaultID)
            changed = true
        }

        for id in currentIDs where !ids.contains(id) {
            ids.append(id)
            changed = true
        }

        if changed {
            settings.orderedIDs = ids
        }
    }

    private func sorted(entries: [IPEntry], orderedIDs: [String]) -> [IPEntry] {
        let explicitOrder = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) })

        return entries.sorted { lhs, rhs in
            let lhsOrder = explicitOrder[lhs.id] ?? kindOrder(lhs.kind)
            let rhsOrder = explicitOrder[rhs.id] ?? kindOrder(rhs.kind)

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            if lhs.kind != rhs.kind {
                return kindOrder(lhs.kind) < kindOrder(rhs.kind)
            }
            return lhs.address < rhs.address
        }
    }

    private func kindOrder(_ kind: AdapterKind) -> Int {
        (AdapterKind.defaultOrder.firstIndex(of: kind) ?? AdapterKind.defaultOrder.count) + 10_000
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(settings.fetchInterval, AppSettings.minimumFetchInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }
    }

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
    }
}

enum MoveDirection {
    case up
    case down
}
