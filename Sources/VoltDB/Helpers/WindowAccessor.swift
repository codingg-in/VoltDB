import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView(callback: callback)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Intentionally empty to avoid re-triggering window mutations during SwiftUI render passes
    }
}

private final class WindowTrackingView: NSView {
    let callback: (NSWindow) -> Void
    private var hasConfigured = false

    init(callback: @escaping (NSWindow) -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window, !hasConfigured else { return }
        hasConfigured = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self = self, let window = window else { return }
            self.callback(window)
        }
    }
}

