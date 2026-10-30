import SwiftUI

/// Captures the hosting NSWindow into the observable model (used for
/// menu-open routing and future per-window behaviors).
struct WindowAccessor: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackedView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TrackedView)?.onChange = onChange
    }

    private final class TrackedView: NSView {
        var onChange: (NSWindow?) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange(window)
        }
    }
}
