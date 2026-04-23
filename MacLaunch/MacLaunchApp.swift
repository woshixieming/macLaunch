import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()

    private var launchPanelController: LaunchPanelController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
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
                self?.configureStatusItem()
            }
            .store(in: &cancellables)

        configureStatusItem()
        showLauncher()
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
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = statusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Mac Launch")
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示启动台", action: #selector(showLauncher), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏启动台", action: #selector(hideLauncher), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "快捷键: \(settings.hotKeyPreset.title)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Mac Launch", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func applyHotKeyPreset() {
        hotKeyManager?.registerHotKey(
            keyCode: settings.hotKeyPreset.keyCode,
            modifiers: settings.hotKeyPreset.carbonModifiers
        )
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
                    onOpenSettings: {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    },
                    onQuit: { NSApp.terminate(nil) }
                )
            }

        Settings {
            SettingsView(settings: appDelegate.settings)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
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
