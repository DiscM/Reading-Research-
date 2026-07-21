import AppKit
import SwiftUI

enum CanopySemanticColors {
    static func windowBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: resolved(.windowBackgroundColor, for: colorScheme))
    }

    static func controlBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: resolved(.controlBackgroundColor, for: colorScheme))
    }

    static func textBackground(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: resolved(.textBackgroundColor, for: colorScheme))
    }

    static func resolved(_ color: NSColor, for colorScheme: ColorScheme) -> NSColor {
        guard let appearance = NSAppearance(
            named: colorScheme == .dark ? .darkAqua : .aqua
        ) else {
            return color
        }

        var resolvedColor = color
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.sRGB) ?? color
        }
        return resolvedColor
    }
}

struct CanopyOpaqueSemanticBackground: NSViewRepresentable {
    let semanticColor: NSColor
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> OpaqueBackgroundView {
        let view = OpaqueBackgroundView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: OpaqueBackgroundView, context: Context) {
        update(nsView)
    }

    private func update(_ view: OpaqueBackgroundView) {
        view.backgroundColor = CanopySemanticColors.resolved(
            semanticColor,
            for: colorScheme
        )
    }

    final class OpaqueBackgroundView: NSView {
        override var allowsVibrancy: Bool { false }
        override var isOpaque: Bool { true }

        var backgroundColor = NSColor.clear {
            didSet {
                layer?.backgroundColor = backgroundColor.cgColor
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
