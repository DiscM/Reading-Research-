import AppKit
import CanopyCore
import SwiftUI

struct HighlightAppearancePreferences: Equatable {
    let increasedContrast: Bool

    var overlayOpacity: CGFloat { increasedContrast ? 0.55 : 0.42 }
    var inspectorFillOpacity: CGFloat { increasedContrast ? 0.28 : 0.18 }
    var selectedPaletteFillOpacity: CGFloat { increasedContrast ? 0.30 : 0.20 }
    var unselectedPaletteFillOpacity: CGFloat { increasedContrast ? 0.14 : 0.08 }
    var areaFillOpacity: CGFloat { increasedContrast ? 0.24 : 0.14 }
    var areaBorderOpacity: CGFloat { increasedContrast ? 1.0 : 0.88 }
    var areaBorderWidth: CGFloat { increasedContrast ? 3.5 : 2 }
    var swatchBorderWidth: CGFloat { increasedContrast ? 2 : 1 }
    var selectedBorderWidth: CGFloat { increasedContrast ? 3 : 2 }
}

struct HighlightColorLabelPresentation: Equatable {
    let name: String
    let checkmarkSystemImage: String?
    let borderWidth: CGFloat

    init(color: HighlightColor, selected: Bool, increasedContrast: Bool) {
        name = color.displayName
        checkmarkSystemImage = selected ? "checkmark" : nil
        borderWidth = selected
            ? HighlightAppearancePreferences(increasedContrast: increasedContrast).selectedBorderWidth
            : 0
    }
}

extension HighlightColor {
    var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .purple: "Purple"
        }
    }

    var differentiateWithoutColorSymbol: String {
        switch self {
        case .yellow: "circle.fill"
        case .green: "square.fill"
        case .blue: "triangle.fill"
        case .pink: "diamond.fill"
        case .purple: "hexagon.fill"
        }
    }

    var differentiateWithoutColorGlyph: String {
        switch self {
        case .yellow: "●"
        case .green: "■"
        case .blue: "▲"
        case .pink: "◆"
        case .purple: "⬢"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .pink: .pink
        case .purple: .purple
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .purple: .systemPurple
        }
    }
}
