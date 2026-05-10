import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: IPStore
    @State private var selection: SettingsMenuItem = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detail
        }
        .frame(width: 820, height: 500)
        .background(SettingsPalette.windowBackground)
        .onAppear {
            store.refreshLaunchAtLoginStatus()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(SettingsMenuItem.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbolName)
                            .font(.system(size: 14, weight: .regular))
                            .frame(width: 19)

                        Text(item.title)
                            .font(.system(size: 14, weight: .regular))

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .foregroundStyle(selection == item ? .white : .primary)
                    .background {
                        if selection == item {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsPalette.selectedMenuBackground)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(10)
        .frame(width: 200)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSettingsPane(store: store)
        case .adapterDisplay:
            AdapterDisplayPane(store: store)
        case .about:
            AboutSettingsPane()
        }
    }
}

private enum SettingsMenuItem: String, CaseIterable, Identifiable {
    case general
    case adapterDisplay
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .adapterDisplay: "Adapter display"
        case .about: "About"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .adapterDisplay: "arrow.up.arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

private enum SettingsPalette {
    static let windowBackground = Color(red: 0.095, green: 0.082, blue: 0.115)
    static let selectedMenuBackground = Color(red: 0.015, green: 0.315, blue: 0.78)
}

private struct GeneralSettingsPane: View {
    @ObservedObject var store: IPStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Public IP")

                    HStack {
                        Label("Fetch public IP every", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Stepper(value: fetchIntervalBinding, in: AppSettings.minimumFetchInterval...86_400, step: 10) {
                            Text("\(Int(store.settings.fetchInterval))s")
                                .font(.system(.subheadline, design: .monospaced))
                                .frame(width: 70, alignment: .trailing)
                        }
                        .controlSize(.small)
                    }
                    .settingsRow()
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Appearance")

                    SettingsToggleRow(
                        title: "Show status bar icon",
                        subtitle: "Show the globe-style adapter icon before the IP address.",
                        systemImage: "globe.asia.australia.fill",
                        isOn: statusIconBinding
                    )

                    SettingsToggleRow(
                        title: "Shorten status bar IP",
                        subtitle: "Show only the beginning and end of the main menu bar address.",
                        systemImage: "textformat.abc.dottedunderline",
                        isOn: abbreviatedStatusBarIPBinding
                    )

                    SettingsToggleRow(
                        title: "Show Dock icon",
                        subtitle: "Show Status Bar IP in the Dock while it is running.",
                        systemImage: "macwindow.on.rectangle",
                        isOn: dockIconBinding
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    sectionTitle("Startup")

                    SettingsToggleRow(
                        title: "Launch at Login",
                        subtitle: "Start automatically when you sign in to macOS.",
                        systemImage: "power.circle",
                        isOn: launchAtLoginBinding
                    )

                    if let launchAtLoginError = store.launchAtLoginError {
                        Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .settingsRow()
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fetchIntervalBinding: Binding<Double> {
        Binding(
            get: { store.settings.fetchInterval },
            set: { store.setFetchInterval($0) }
        )
    }

    private var dockIconBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showDockIcon },
            set: { store.settings.showDockIcon = $0 }
        )
    }

    private var statusIconBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showStatusBarIcon },
            set: { store.settings.showStatusBarIcon = $0 }
        )
    }

    private var abbreviatedStatusBarIPBinding: Binding<Bool> {
        Binding(
            get: { store.settings.abbreviateStatusBarIP },
            set: { store.settings.abbreviateStatusBarIP = $0 }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchAtLoginEnabled },
            set: { store.setLaunchAtLogin($0) }
        )
    }
}

private struct AdapterDisplayPane: View {
    @ObservedObject var store: IPStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if store.orderedEntries.count > 6 {
                    ScrollView {
                        adapterListContent
                            .padding(.trailing, 12)
                    }
                } else {
                    adapterListContent
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var adapterListContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(store.orderedEntries) { entry in
                SettingsAdapterRow(
                    entry: entry,
                    hidden: store.settings.hiddenIDs.contains(entry.id),
                    canMoveUp: store.orderedEntries.first?.id != entry.id,
                    canMoveDown: store.orderedEntries.last?.id != entry.id,
                    toggleHidden: { hidden in
                        store.setHidden(entry, hidden: hidden)
                    },
                    moveUp: {
                        store.moveEntry(entry, direction: .up)
                    },
                    moveDown: {
                        store.moveEntry(entry, direction: .down)
                    }
                )

                if store.orderedEntries.last?.id != entry.id {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

            VStack(spacing: 4) {
                Text("Status Bar IP")
                    .font(.system(size: 26, weight: .bold))
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/hadesker/StatusBarIP")!) {
                    Label("github.com/hadesker/StatusBarIP", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.medium))
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                    Text("Hadesker")
                        .font(.subheadline.weight(.semibold))
                }

                Link(destination: URL(string: "https://hadesker.net")!) {
                    Label("hadesker.net", systemImage: "globe")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(12)
            .frame(width: 340)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version, build) {
        case let (version?, build?) where !version.isEmpty && !build.isEmpty:
            return "\(version) (\(build))"
        case let (version?, _) where !version.isEmpty:
            return version
        default:
            return "1.0"
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 12)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .settingsRow()
    }
}

private struct SettingsAdapterRow: View {
    let entry: IPEntry
    let hidden: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let toggleHidden: (Bool) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(entry.kind.tint.opacity(0.14))
                Image(systemName: entry.kind.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.kind.tint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.address) · \(entry.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(get: { !hidden }, set: { toggleHidden(!$0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(hidden ? "Show adapter" : "Hide adapter")

            HStack(spacing: 4) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move up")

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move down")
            }
            .padding(.trailing, 10)
        }
        .padding(.leading, 10)
        .padding(.vertical, 6)
    }
}

private func sectionTitle(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 14, weight: .bold))
}

private extension View {
    func settingsRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
    }
}
