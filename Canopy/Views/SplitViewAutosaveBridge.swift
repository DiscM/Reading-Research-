import AppKit
import SwiftUI

/// Gives SwiftUI's native macOS split views stable AppKit autosave identities.
/// SwiftUI continues to own visibility; AppKit persists only divider positions.
struct SplitViewAutosaveBridge: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> ResolverView {
        ResolverView(autosaveName: name)
    }

    func updateNSView(_ nsView: ResolverView, context: Context) {
        nsView.autosaveName = name
        nsView.resolveEnclosingSplitView()
    }

    final class ResolverView: NSView {
        var autosaveName: String

        init(autosaveName: String) {
            self.autosaveName = autosaveName
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolveEnclosingSplitView()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveEnclosingSplitView()
        }

        func resolveEnclosingSplitView() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var ancestor = self.superview
                while let view = ancestor, !(view is NSSplitView) {
                    ancestor = view.superview
                }
                guard let splitView = ancestor as? NSSplitView else { return }
                let name = NSSplitView.AutosaveName(self.autosaveName)
                if splitView.autosaveName != name {
                    splitView.autosaveName = name
                }
            }
        }
    }
}
