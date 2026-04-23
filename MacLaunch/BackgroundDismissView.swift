import AppKit
import SwiftUI

struct BackgroundDismissView: NSViewRepresentable {
    let onBackgroundClick: () -> Void

    func makeNSView(context: Context) -> BackgroundHitView {
        let view = BackgroundHitView()
        view.onBackgroundClick = onBackgroundClick
        return view
    }

    func updateNSView(_ nsView: BackgroundHitView, context: Context) {
        nsView.onBackgroundClick = onBackgroundClick
    }
}

@MainActor
final class BackgroundHitView: NSView {
    var onBackgroundClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        onBackgroundClick?()
    }
}
