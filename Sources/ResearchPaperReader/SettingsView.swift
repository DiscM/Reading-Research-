import SwiftUI

struct SettingsView: View {
    @AppStorage("aiMode") private var aiMode = "Private Local"
    @AppStorage("aiProvider") private var aiProvider = "Local Heuristic"
    @AppStorage("cloudProcessingEnabled") private var cloudProcessingEnabled = false
    @AppStorage("byokProvider") private var byokProvider = ""

    private let aiModes = [
        "Private Local",
        "Balanced",
        "Best AI",
        "Custom"
    ]

    var body: some View {
        Form {
            Section("AI Mode") {
                Picker("Mode", selection: $aiMode) {
                    ForEach(aiModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Allow cloud processing", isOn: $cloudProcessingEnabled)

                Text("Private Local mode keeps paper content on this Mac. Cloud and BYOK providers are represented here for the MVP and should be wired through a secure model router before production use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Provider") {
                Picker("Default Provider", selection: $aiProvider) {
                    Text("Local Heuristic").tag("Local Heuristic")
                    Text("Apple Foundation Models").tag("Apple Foundation Models")
                    Text("Core ML").tag("Core ML")
                    Text("MLX").tag("MLX")
                    Text("OpenAI-compatible BYOK").tag("OpenAI-compatible BYOK")
                }

                TextField("BYOK provider URL or name", text: $byokProvider)
                    .textFieldStyle(.roundedBorder)
            }

            Section("MVP Storage") {
                Text("Papers and library data are stored locally in Application Support. No account, sync, or backend is required for this MVP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
