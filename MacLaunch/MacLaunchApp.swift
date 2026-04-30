import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()

    private var launchPanelController: LaunchPanelController?
    private var settingsWindowController: NSWindowController?
    private var hotKeyManager: HotKeyManager?
    private var settingsShortcutMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchPanelController = LaunchPanelController(settings: settings) { [weak self] in
            self?.hideLauncher()
        }

        hotKeyManager = HotKeyManager { [weak self] in
            self?.toggleLauncher()
        }
        applyHotKeyPreset()

        settings.$hotKeyPreset
            .sink { [weak self] _ in
                self?.applyHotKeyPreset()
            }
            .store(in: &cancellables)

        configureMainMenu()
        installSettingsShortcutMonitor()
        showLauncher()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let settingsShortcutMonitor {
            NSEvent.removeMonitor(settingsShortcutMonitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncher()
        return true
    }

    @objc
    func toggleLauncher() {
        launchPanelController?.toggle()
    }

    @objc
    func showLauncher() {
        launchPanelController?.showOnActiveSpace()
    }

    @objc
    func hideLauncher() {
        launchPanelController?.hide()
    }

    @objc
    func openSettings() {
        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.orderFrontRegardless()
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac Launch 设置"
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyHotKeyPreset() {
        hotKeyManager?.registerHotKey(
            keyCode: settings.hotKeyPreset.keyCode,
            modifiers: settings.hotKeyPreset.carbonModifiers
        )
    }

    private func installSettingsShortcutMonitor() {
        guard settingsShortcutMonitor == nil else { return }

        settingsShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command,
                  event.charactersIgnoringModifiers == "," else {
                return event
            }

            self?.openSettings()
            return nil
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Mac Launch")

        appMenu.addItem(
            NSMenuItem(
                title: "关于 Mac Launch",
                action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                keyEquivalent: ""
            )
        )
        appMenu.addItem(.separator())
        let settingsMenuItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsMenuItem.keyEquivalentModifierMask = [.command]
        settingsMenuItem.target = self
        appMenu.addItem(settingsMenuItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            NSMenuItem(
                title: "退出 Mac Launch",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        mainMenu.addItem(appMenuItem)
        mainMenu.setSubmenu(appMenu, for: appMenuItem)
        NSApp.mainMenu = mainMenu
    }
}

@main
struct MacLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Mac Launch", systemImage: "square.grid.3x3.fill") {
            MenuBarExtraContent(
                settings: appDelegate.settings,
                onShow: { appDelegate.showLauncher() },
                onHide: { appDelegate.hideLauncher() },
                onOpenSettings: { appDelegate.openSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
        }
    }
}

private struct MenuBarExtraContent: View {
    @ObservedObject var settings: AppSettings
    let onShow: () -> Void
    let onHide: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        Button("显示启动台") {
            onShow()
        }

        Button("隐藏启动台") {
            onHide()
        }

        Divider()

        Button("打开设置") {
            onOpenSettings()
        }

        Text("当前快捷键: \(settings.hotKeyPreset.title)")
            .font(.caption)

        Divider()

        Button("退出") {
            onQuit()
        }
    }
}
