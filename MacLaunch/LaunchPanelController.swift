import AppKit
import SwiftUI

@MainActor
final class LaunchPanelController: NSWindowController, NSWindowDelegate {
    private let panel: NSPanel

    init(settings: AppSettings, onDismiss: @escaping () -> Void) {
        let contentView = LaunchpadView(settings: settings, onDismiss: onDismiss)
            .frame(minWidth: 980, minHeight: 680)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: contentView)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.delegate = nil

        super.init(window: panel)

        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func showOnActiveSpace() {
        updateFrame()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .launcherFocusSearch, object: nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : showOnActiveSpace()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func updateFrame() {
        let activeScreen = NSApp.keyWindow?.screen ?? NSScreen.main ?? panel.screen
        let frame = activeScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
        panel.setFrame(frame, display: true)
    }
}
