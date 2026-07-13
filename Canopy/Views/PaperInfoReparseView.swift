import CanopyCore
import SwiftUI

struct PaperInfoReparseReviewView: View {
    let proposal: PaperInfoReparseProposal
    let onUseFound: (PaperInfoMetadataField) -> Void
    let onKeepCurrent: (PaperInfoMetadataField) -> Void
    let onKeepAllCurrent: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose each value to use, review your choices, then select Done. Nothing is saved until you save Paper Info.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(proposal.fields) { field in
                PaperInfoReparseFieldView(
                    field: field,
                    currentValue: currentValue(for: field),
                    currentProvenance: currentProvenanceText(for: field),
                    foundValue: foundValue(for: field),
                    foundProvenance: foundProvenance(for: field),
                    decision: proposal.decision(for: field),
                    onUseFound: { onUseFound(field) },
                    onKeepCurrent: { onKeepCurrent(field) }
                )
                if field != proposal.fields.last {
                    Divider()
                }
            }

            HStack {
                Button("Keep All Current", action: onKeepAllCurrent)
                Spacer()
                Button("Done", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .disabled(!proposal.remainingFields.isEmpty)
            }
        }
        .padding(.vertical, 4)
    }

    private func currentValue(for field: PaperInfoMetadataField) -> String {
        switch field {
        case .title:
            proposal.current.title
        case .authorCredits:
            authorList(proposal.current.authorCredits.map { author in
                authorDescription(
                    displayName: author.displayName,
                    familyName: author.familyName,
                    provenance: proposal.currentAuthorProvenance[author.id] ?? .userEntry
                )
            })
        case .publicationYear:
            nonempty(proposal.current.publicationYearText)
        case .doi:
            nonempty(proposal.current.doi)
        case .arxivID:
            nonempty(proposal.current.arxivID)
        }
    }

    private func currentProvenanceText(for field: PaperInfoMetadataField) -> String {
        if field == .authorCredits { return "Provenance shown per Author Credit" }
        return proposal.currentProvenance[field]?.displayName ?? "Not set"
    }

    private func foundValue(for field: PaperInfoMetadataField) -> String {
        let metadata = proposal.metadata
        return switch field {
        case .title:
            metadata.title
        case .authorCredits:
            authorList(metadata.authorCredits.map { author in
                authorDescription(
                    displayName: author.displayName,
                    familyName: author.familyName,
                    provenance: author.provenance
                )
            })
        case .publicationYear:
            metadata.publicationYear.map(String.init) ?? "Not found"
        case .doi:
            metadata.doi ?? "Not found"
        case .arxivID:
            metadata.arxivID ?? "Not found"
        }
    }

    private func foundProvenance(for field: PaperInfoMetadataField) -> String {
        let metadata = proposal.metadata
        switch field {
        case .title:
            return metadata.titleProvenance.displayName
        case .authorCredits:
            return "Provenance shown per Author Credit"
        case .publicationYear:
            return metadata.publicationYearProvenance?.displayName ?? "Not found"
        case .doi:
            return metadata.doiProvenance?.displayName ?? "Not found"
        case .arxivID:
            return metadata.arxivIDProvenance?.displayName ?? "Not found"
        }
    }

    private func authorList(_ authors: [String]) -> String {
        authors.isEmpty ? "No Author Credits" : authors.joined(separator: "\n")
    }

    private func authorDescription(
        displayName: String,
        familyName: String,
        provenance: MetadataProvenance
    ) -> String {
        "\(displayName) — family name: \(familyName) · \(provenance.displayName)"
    }

    private func nonempty(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : trimmed
    }
}

private struct PaperInfoReparseFieldView: View {
    let field: PaperInfoMetadataField
    let currentValue: String
    let currentProvenance: String
    let foundValue: String
    let foundProvenance: String
    let decision: PaperInfoReparseDecision?
    let onUseFound: () -> Void
    let onKeepCurrent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.displayName)
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("Current")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentValue)
                            .textSelection(.enabled)
                        Text(currentProvenance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Found")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(foundValue)
                            .textSelection(.enabled)
                        Text(foundProvenance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                choiceButton(
                    "Keep Current",
                    decision: .keepCurrent,
                    action: onKeepCurrent
                )
                choiceButton(
                    "Use Found",
                    decision: .useFound,
                    action: onUseFound
                )
            }
            .controlSize(.small)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reparsed \(field.displayName)")
    }

    private func choiceButton(
        _ title: String,
        decision buttonDecision: PaperInfoReparseDecision,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(
                title,
                systemImage: decision == buttonDecision ? "checkmark.circle.fill" : "circle"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityValue(decision == buttonDecision ? "Selected" : "Not selected")
    }
}

extension PaperInfoMetadataField {
    var displayName: String {
        switch self {
        case .title: "Title"
        case .authorCredits: "Author Credits"
        case .publicationYear: "Publication Year"
        case .doi: "DOI"
        case .arxivID: "arXiv ID"
        }
    }
}
