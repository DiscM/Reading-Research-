import SwiftUI

enum CanopyAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "Follow System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum CanopyPreferenceKeys {
    static let appearanceMode = "accessibility.appearanceMode"
    static let increasedContrast = "accessibility.increasedContrast"
    static let differentiateWithoutColor = "accessibility.differentiateWithoutColor"
    static let annotationSortOrder = "annotations.sortOrder"
}

struct CanopyAccessibilityPreferences: DynamicProperty {
    @AppStorage(CanopyPreferenceKeys.appearanceMode) private var appearanceModeRawValue = CanopyAppearanceMode.system.rawValue
    @AppStorage(CanopyPreferenceKeys.increasedContrast) private var increasedContrast = false
    @AppStorage(CanopyPreferenceKeys.differentiateWithoutColor) private var differentiateWithoutColor = false

    var appearanceMode: CanopyAppearanceMode {
        CanopyAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    var appearanceModeSelection: Binding<String> {
        $appearanceModeRawValue
    }

    var increasedContrastSelection: Binding<Bool> {
        $increasedContrast
    }

    var differentiateWithoutColorSelection: Binding<Bool> {
        $differentiateWithoutColor
    }

    var overrides: CanopyAccessibilityOverrides {
        CanopyAccessibilityOverrides(
            increasedContrast: increasedContrast,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    var usesSystemDefaults: Bool {
        appearanceModeRawValue == CanopyAppearanceMode.system.rawValue
            && !increasedContrast
            && !differentiateWithoutColor
    }

    func reset() {
        appearanceModeRawValue = CanopyAppearanceMode.system.rawValue
        increasedContrast = false
        differentiateWithoutColor = false
    }
}

struct CanopyAccessibilityOverrides: Equatable {
    private static let increasedInterfaceContrast = 1.2

    var increasedContrast = false
    var differentiateWithoutColor = false

    func usesIncreasedContrast(system: Bool) -> Bool {
        system || increasedContrast
    }

    func differentiatesWithoutColor(system: Bool) -> Bool {
        system || differentiateWithoutColor
    }

    func interfaceContrastAmount(systemIncreasedContrast: Bool) -> Double {
        increasedContrast && !systemIncreasedContrast ? Self.increasedInterfaceContrast : 1
    }

    func sourceDocumentContrastCompensation(systemIncreasedContrast: Bool) -> Double {
        1 / interfaceContrastAmount(systemIncreasedContrast: systemIncreasedContrast)
    }
}

private struct CanopyAccessibilityOverridesKey: EnvironmentKey {
    static let defaultValue = CanopyAccessibilityOverrides()
}

extension EnvironmentValues {
    var canopyAccessibilityOverrides: CanopyAccessibilityOverrides {
        get { self[CanopyAccessibilityOverridesKey.self] }
        set { self[CanopyAccessibilityOverridesKey.self] = newValue }
    }
}
