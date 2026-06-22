import AppKit
import SwiftUI

enum SolarpunkTheme {
    static let spruce = adaptiveColor(
        light: NSColor(red: 0.10, green: 0.30, blue: 0.23, alpha: 1),
        dark: NSColor(red: 0.58, green: 0.78, blue: 0.63, alpha: 1)
    )
    static let moss = adaptiveColor(
        light: NSColor(red: 0.31, green: 0.46, blue: 0.23, alpha: 1),
        dark: NSColor(red: 0.65, green: 0.76, blue: 0.39, alpha: 1)
    )
    static let fern = Color(red: 0.20, green: 0.52, blue: 0.36)
    static let sunlight = Color(red: 0.88, green: 0.67, blue: 0.22)
    static let clay = adaptiveColor(
        light: NSColor(red: 0.67, green: 0.34, blue: 0.22, alpha: 1),
        dark: NSColor(red: 0.89, green: 0.53, blue: 0.38, alpha: 1)
    )
    static let lichen = Color(red: 0.63, green: 0.70, blue: 0.43)

    static let canvas = adaptiveColor(
        light: NSColor(red: 0.956, green: 0.949, blue: 0.892, alpha: 1),
        dark: NSColor(red: 0.075, green: 0.102, blue: 0.086, alpha: 1)
    )

    static let sidebar = adaptiveColor(
        light: NSColor(red: 0.902, green: 0.918, blue: 0.833, alpha: 0.82),
        dark: NSColor(red: 0.092, green: 0.142, blue: 0.112, alpha: 0.92)
    )

    static let surface = adaptiveColor(
        light: NSColor(red: 0.992, green: 0.984, blue: 0.934, alpha: 0.96),
        dark: NSColor(red: 0.118, green: 0.157, blue: 0.130, alpha: 0.96)
    )

    static let raisedSurface = adaptiveColor(
        light: NSColor(red: 0.975, green: 0.965, blue: 0.900, alpha: 1),
        dark: NSColor(red: 0.145, green: 0.184, blue: 0.151, alpha: 1)
    )

    static let hairline = spruce.opacity(0.16)

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

private struct SolarpunkCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(SolarpunkTheme.hairline, lineWidth: 1)
            }
            .shadow(color: SolarpunkTheme.spruce.opacity(0.07), radius: 7, y: 3)
    }
}

extension View {
    func solarpunkCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(SolarpunkCardModifier(cornerRadius: cornerRadius))
    }
}
