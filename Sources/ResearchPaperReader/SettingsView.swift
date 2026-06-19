import SwiftUI

struct SettingsView: View {
    @AppStorage("aiMode") private var aiMode = "Private Local"
    @AppStorage("aiProvider") private var aiProvider = "Apple Foundation Models"
    @AppStorage("cloudProcessingEnabled") private var cloudProcessingEnabled = false
    @AppStorage("byokProvider") private var byokProvider = ""
    @AppStorage("resumeLastReadLocation") private var resumeLastReadLocation = true

    private let aiModes = [
        "Private Local",
        "Balanced",
        "Best AI",
        "Custom"
    ]

    var body: some View {
        Form {
            Section("Reading") {
                Toggle("Return to the last read location", isOn: $resumeLastReadLocation)

                Text("When opening a document you have started, the reader returns to its most recently viewed page. Reading position is always stored locally so Continue Reading stays available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("AI Mode") {
                Picker("Mode", selection: $aiMode) {
                    ForEach(aiModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Allow cloud processing", isOn: $cloudProcessingEnabled)

                Text("Private Local mode keeps document content on this Mac. Cloud and BYOK providers are represented here for the MVP and should be wired through a secure model router before production use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Provider") {
                Picker("Default Provider", selection: $aiProvider) {
                    Text("Apple Foundation Models").tag("Apple Foundation Models")
                    Text("Core ML").tag("Core ML")
                    Text("Local Heuristic").tag("Local Heuristic")
                    Text("MLX").tag("MLX")
                    Text("OpenAI-compatible BYOK").tag("OpenAI-compatible BYOK")
                }

                Text(LocalPaperAI.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("BYOK provider URL or name", text: $byokProvider)
                    .textFieldStyle(.roundedBorder)
            }

            Section("MVP Storage") {
                Text("Documents and library data are stored locally in Application Support. No account, sync, or backend is required for this MVP.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
