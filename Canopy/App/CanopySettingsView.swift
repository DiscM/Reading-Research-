import SwiftUI

struct CanopySettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

    var body: some View {
        ZStack {
            CanopyOpaqueSemanticBackground(
                semanticColor: .windowBackgroundColor,
                colorScheme: colorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Form {
                Section("Appearance") {
                    Toggle(
                        "Use Light Mode",
                        isOn: accessibilityPreferences.lightModeSelection
                    )
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("appearance-light-mode-toggle")

                    Text("Canopy uses Dark Mode by default. Both appearances use macOS semantic colors.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Accessibility") {
                    Toggle(
                        "Increase Contrast",
                        isOn: accessibilityPreferences.increasedContrastSelection
                    )
                    Toggle(
                        "Differentiate Without Color",
                        isOn: accessibilityPreferences.differentiateWithoutColorSelection
                    )

                    Button("Reset Accessibility Settings") {
                        accessibilityPreferences.resetAccessibility()
                    }
                    .disabled(accessibilityPreferences.usesSystemAccessibilityDefaults)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 460, height: 270)
        .containerBackground(
            CanopySemanticColors.windowBackground(for: colorScheme),
            for: .window
        )
        .preferredColorScheme(accessibilityPreferences.appearanceMode.preferredColorScheme)
    }
}
