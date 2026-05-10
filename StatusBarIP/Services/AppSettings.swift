import Foundation

struct AppSettings: Equatable, Sendable {
    static let minimumFetchInterval = 10.0
    static let defaultFetchInterval = 300.0

    var fetchInterval: TimeInterval
    var orderedIDs: [String]
    var hiddenIDs: Set<String>
    var showDockIcon: Bool
    var showStatusBarIcon: Bool
    var abbreviateStatusBarIP: Bool

    static let defaults = AppSettings(
        fetchInterval: defaultFetchInterval,
        orderedIDs: AdapterKind.defaultOrder.map(\.rawValue),
        hiddenIDs: [],
        showDockIcon: false,
        showStatusBarIcon: true,
        abbreviateStatusBarIP: false
    )
}

protocol SettingsStoring {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

struct UserDefaultsSettingsStore: SettingsStoring {
    private enum Key {
        static let fetchInterval = "fetchInterval"
        static let orderedIDs = "orderedIDs"
        static let hiddenIDs = "hiddenIDs"
        static let showDockIcon = "showDockIcon"
        static let showStatusBarIcon = "showStatusBarIcon"
        static let abbreviateStatusBarIP = "abbreviateStatusBarIP"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let rawInterval = defaults.object(forKey: Key.fetchInterval) as? Double ?? AppSettings.defaultFetchInterval
        let orderedIDs = defaults.stringArray(forKey: Key.orderedIDs) ?? AppSettings.defaults.orderedIDs
        let hiddenIDs = Set(defaults.stringArray(forKey: Key.hiddenIDs) ?? [])
        let showDockIcon = defaults.object(forKey: Key.showDockIcon) as? Bool ?? AppSettings.defaults.showDockIcon
        let showStatusBarIcon = defaults.object(forKey: Key.showStatusBarIcon) as? Bool ?? AppSettings.defaults.showStatusBarIcon
        let abbreviateStatusBarIP = defaults.object(forKey: Key.abbreviateStatusBarIP) as? Bool ?? AppSettings.defaults.abbreviateStatusBarIP

        return AppSettings(
            fetchInterval: max(rawInterval, AppSettings.minimumFetchInterval),
            orderedIDs: orderedIDs,
            hiddenIDs: hiddenIDs,
            showDockIcon: showDockIcon,
            showStatusBarIcon: showStatusBarIcon,
            abbreviateStatusBarIP: abbreviateStatusBarIP
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(max(settings.fetchInterval, AppSettings.minimumFetchInterval), forKey: Key.fetchInterval)
        defaults.set(settings.orderedIDs, forKey: Key.orderedIDs)
        defaults.set(Array(settings.hiddenIDs), forKey: Key.hiddenIDs)
        defaults.set(settings.showDockIcon, forKey: Key.showDockIcon)
        defaults.set(settings.showStatusBarIcon, forKey: Key.showStatusBarIcon)
        defaults.set(settings.abbreviateStatusBarIP, forKey: Key.abbreviateStatusBarIP)
    }
}
