import SwiftUI

enum CanopyAppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case light

    static let defaultMode = Self.dark

    var id: Self { self }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }

    static func resolve(storedRawValue: String?) -> Self {
        storedRawValue.flatMap(Self.init(rawValue:)) ?? defaultMode
    }
}

enum CanopyPreferenceKeys {
    static let appearanceMode = "accessibility.appearanceMode"
    static let increasedContrast = "accessibility.increasedContrast"
    static let differentiateWithoutColor = "accessibility.differentiateWithoutColor"
    static let annotationSortOrder = "annotations.sortOrder"
}

struct CanopyAccessibilityPreferences: DynamicProperty {
    @AppStorage(CanopyPreferenceKeys.appearanceMode)
    private var appearanceModeRawValue = CanopyAppearanceMode.defaultMode.rawValue
    @AppStorage(CanopyPreferenceKeys.increasedContrast) private var increasedContrast = false
    @AppStorage(CanopyPreferenceKeys.differentiateWithoutColor) private var differentiateWithoutColor = false

    var appearanceMode: CanopyAppearanceMode {
        CanopyAppearanceMode.resolve(storedRawValue: appearanceModeRawValue)
    }

    var lightModeSelection: Binding<Bool> {
        Binding(
            get: { appearanceMode == .light },
            set: { usesLightMode in
                appearanceModeRawValue = (
                    usesLightMode ? CanopyAppearanceMode.light : .dark
                ).rawValue
            }
        )
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

    var usesSystemAccessibilityDefaults: Bool {
        !increasedContrast && !differentiateWithoutColor
    }

    func resetAccessibility() {
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
