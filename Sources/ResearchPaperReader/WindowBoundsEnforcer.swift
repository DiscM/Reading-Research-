import AppKit
import SwiftUI

struct WindowBoundsEnforcer: NSViewRepresentable {
    let minimumSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(minimumSize: minimumSize)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true

        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.minimumSize = minimumSize

        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var minimumSize: CGSize

        private weak var window: NSWindow?
        private var isClamping = false

        init(minimumSize: CGSize) {
            self.minimumSize = minimumSize
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else {
                if window != nil {
                    applyWindowLimits()
                }
                return
            }

            NotificationCenter.default.removeObserver(self)
            self.window = window

            applyWindowLimits()
            clampIntoVisibleScreen()

            let notifications: [NSNotification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didMoveNotification,
                NSWindow.didChangeScreenNotification
            ]

            for name in notifications {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowFrameChanged(_:)),
                    name: name,
                    object: window,
                )
            }
        }

        @objc private func windowFrameChanged(_ notification: Notification) {
            applyWindowLimits()
            clampIntoVisibleScreen()
        }

        private func applyWindowLimits() {
            guard let window, let visibleFrame = window.visibleScreenFrame else { return }

            let fittedMinimum = minimumSize.fitted(to: visibleFrame.size)
            window.minSize = fittedMinimum
            window.contentMinSize = fittedMinimum
        }

        private func clampIntoVisibleScreen() {
            guard !isClamping, let window, let visibleFrame = window.visibleScreenFrame else { return }

            isClamping = true
            defer { isClamping = false }

            var frame = window.frame
            let fittedMinimum = minimumSize.fitted(to: visibleFrame.size)

            frame.size.width = min(max(frame.width, fittedMinimum.width), visibleFrame.width)
            frame.size.height = min(max(frame.height, fittedMinimum.height), visibleFrame.height)

            if frame.maxX > visibleFrame.maxX {
                frame.origin.x = visibleFrame.maxX - frame.width
            }

            if frame.minX < visibleFrame.minX {
                frame.origin.x = visibleFrame.minX
            }

            if frame.maxY > visibleFrame.maxY {
                frame.origin.y = visibleFrame.maxY - frame.height
            }

            if frame.minY < visibleFrame.minY {
                frame.origin.y = visibleFrame.minY
            }

            guard !window.frame.equalTo(frame) else { return }
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

private extension NSWindow {
    var visibleScreenFrame: CGRect? {
        screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }
}

extension CGSize {
    func fitted(to bounds: CGSize) -> CGSize {
        CGSize(
            width: min(width, max(1, bounds.width)),
            height: min(height, max(1, bounds.height))
        )
    }
}
