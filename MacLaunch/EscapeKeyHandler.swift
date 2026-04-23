import AppKit
import SwiftUI

struct EscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void
    var onKeyDown: ((NSEvent) -> Bool)? = nil
    var onScrollWheel: ((NSEvent) -> Bool)? = nil

    func makeNSView(context: Context) -> EscapeAwareView {
        let view = EscapeAwareView()
        view.onEscape = onEscape
        view.onKeyDown = onKeyDown
        view.onScrollWheel = onScrollWheel
        return view
    }

    func updateNSView(_ nsView: EscapeAwareView, context: Context) {
        nsView.onEscape = onEscape
        nsView.onKeyDown = onKeyDown
        nsView.onScrollWheel = onScrollWheel
    }
}

@MainActor
final class EscapeAwareView: NSView {
    var onEscape: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onScrollWheel: ((NSEvent) -> Bool)?
    private var monitor: Any?
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.onKeyDown?(event) == true {
                return nil
            }

            guard event.keyCode == 53 else {
                return event
            }

            self?.onEscape?()
            return nil
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.onScrollWheel?(event) == true ? nil : event
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        if newWindow == nil, let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}
