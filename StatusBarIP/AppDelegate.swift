import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = IPStore()
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsController = SettingsWindowController(store: store)
        statusController = StatusItemController(store: store) { [weak self] in
            self?.showSettings()
        }
        store.start()
    }

    func showSettings() {
        settingsController?.show()
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let store: IPStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let rightClickMenu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private let openSettings: () -> Void

    init(store: IPStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        configurePopover()
        configureMenu()
        observeStore()
        updateStatusButton()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store) { [weak self] in
                self?.popover.performClose(nil)
                self?.openSettings()
            } quitApp: {
                NSApp.terminate(nil)
            }
        )
    }

    private func configureMenu() {
        rightClickMenu.addItem(
            menuItem(
                title: "Settings",
                systemImage: "gearshape",
                action: #selector(openSettingsFromMenu),
                keyEquivalent: ""
            )
        )
        rightClickMenu.addItem(.separator())
        rightClickMenu.addItem(
            menuItem(
                title: "Quit",
                systemImage: "power",
                action: #selector(closeApp),
                keyEquivalent: "q"
            )
        )
        rightClickMenu.items.forEach { $0.target = self }
    }

    private func menuItem(title: String, systemImage: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        image?.isTemplate = true
        item.image = image
        return item
    }

    private func observeStore() {
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        if !store.isInternetAvailable {
            let image = store.settings.showStatusBarIcon
                ? NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: nil)
                : nil
            image?.isTemplate = true

            button.image = image
            button.title = store.settings.showStatusBarIcon ? " No internet" : "No internet"
            button.toolTip = "No internet"
            return
        }

        let entry = store.statusEntry
        let image = store.settings.showStatusBarIcon
            ? NSImage(systemSymbolName: entry?.kind.symbolName ?? "network", accessibilityDescription: nil)
            : nil
        image?.isTemplate = true

        button.image = image
        button.title = entry.map { entry in
            let address = IPAddressDisplayFormatter.statusBarAddress(
                entry.address,
                abbreviated: store.settings.abbreviateStatusBarIP
            )
            return store.settings.showStatusBarIcon ? " \(address)" : address
        } ?? "No IP"
        button.toolTip = entry.map { "\($0.displayTitle): \($0.address)" } ?? "Status Bar IP"
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            statusItem.menu = rightClickMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func closeApp() {
        NSApp.terminate(nil)
    }
}

@MainActor
final class SettingsWindowController {
    private let store: IPStore
    private var window: NSWindow?

    init(store: IPStore) {
        self.store = store
    }

    func show() {
        if window == nil {
            let hostingController = NSHostingController(rootView: SettingsView(store: store))
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Status Bar IP Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.setContentSize(NSSize(width: 820, height: 500))
            newWindow.contentMinSize = NSSize(width: 760, height: 440)
            newWindow.standardWindowButton(.zoomButton)?.isEnabled = false
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
