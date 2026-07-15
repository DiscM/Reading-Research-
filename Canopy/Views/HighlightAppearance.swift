import AppKit
import CanopyCore
import SwiftUI

struct HighlightAppearancePreferences: Equatable {
    let increasedContrast: Bool

    var overlayOpacity: CGFloat { increasedContrast ? 0.55 : 0.42 }
    var inspectorFillOpacity: CGFloat { increasedContrast ? 0.28 : 0.18 }
    var selectedPaletteFillOpacity: CGFloat { increasedContrast ? 0.30 : 0.20 }
    var unselectedPaletteFillOpacity: CGFloat { increasedContrast ? 0.14 : 0.08 }
    var swatchBorderWidth: CGFloat { increasedContrast ? 2 : 1 }
    var selectedBorderWidth: CGFloat { increasedContrast ? 3 : 2 }
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
