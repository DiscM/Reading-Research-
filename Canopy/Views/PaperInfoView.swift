import CanopyCore
import SwiftUI

struct PaperInfoView: View {
    @Bindable var workflow: PaperInfoWorkflow
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Paper Info")
                    .font(.title2.bold())
                Spacer()
            }
            .padding([.horizontal, .top], 24)

            Form {
                Section("Bibliographic Information") {
                    metadataField("Title", text: $workflow.draft.title, provenance: snapshot?.titleProvenance)
                    metadataField(
                        "Publication Year",
                        text: $workflow.draft.publicationYearText,
                        provenance: snapshot?.publicationYearProvenance
                    )
                    metadataField("DOI", text: $workflow.draft.doi, provenance: snapshot?.doiProvenance)
                    metadataField("arXiv ID", text: $workflow.draft.arxivID, provenance: snapshot?.arxivIDProvenance)
                }

                Section("Author Credits") {
                    if let details = workflow.readOnlyDetails, !details.authors.isEmpty {
                        ForEach(details.authors) { author in
                            LabeledContent("Author \(author.position + 1)") {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(author.displayName)
                                    Text(provenanceName(author.provenance))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("No Author Credits")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Source PDF") {
                    LabeledContent("Status", value: workflow.readOnlyDetails?.sourceStatus ?? "Unavailable")
                    LabeledContent("Storage", value: workflow.readOnlyDetails?.storage ?? "—")
                    LabeledContent("Filename", value: workflow.readOnlyDetails?.sourceFilename ?? "—")
                    LabeledContent("Location") {
                        Text(workflow.readOnlyDetails?.sourceLocation ?? "—")
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    workflow.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!workflow.hasChanges)
            }
            .padding(16)
        }
        .frame(width: 600, height: 620)
        .interactiveDismissDisabled(workflow.hasChanges)
        .alert(
            "Couldn’t Save Paper Info",
            isPresented: Binding(
                get: { workflow.errorMessage != nil },
                set: { if !$0 { workflow.errorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(workflow.errorMessage ?? "Canopy could not save these changes.")
        }
    }

    private var snapshot: PaperInfoSnapshot? { workflow.originalSnapshot }

    private func metadataField(
        _ label: String,
        text: Binding<String>,
        provenance: MetadataProvenance?
    ) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 3) {
                TextField(label, text: text)
                    .frame(minWidth: 300)
                    .multilineTextAlignment(.leading)
                if let provenance {
                    Text(provenanceName(provenance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func provenanceName(_ provenance: MetadataProvenance) -> String {
        switch provenance {
        case .embeddedMetadata: "Embedded metadata"
        case .firstPage: "First page"
        case .filenameFallback: "Filename fallback"
        case .userEntry: "User entry"
        }
    }

}
