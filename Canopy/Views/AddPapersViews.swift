import AppKit
import CanopyCore
import SwiftData
import SwiftUI

struct AddBatchStorageSheet: View {
    @Bindable var workflow: AddPapersWorkflow
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Papers")
                .font(.title2.bold())
            Text("\(workflow.pendingURLs.count) PDF\(workflow.pendingURLs.count == 1 ? "" : "s") • \(ByteCountFormatter.string(fromByteCount: workflow.totalFileSize, countStyle: .file))")
                .foregroundStyle(.secondary)

            Picker("Storage", selection: $workflow.storageChoice) {
                ForEach(AddBatchStorageChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.radioGroup)

            Text(workflow.storageChoice.detail)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") {
                    workflow.isStorageChoicePresented = false
                    workflow.reset()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add Papers", action: onAdd)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

struct AddBatchProgressSheet: View {
    @Bindable var workflow: AddPapersWorkflow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(workflow.progressPhase)
                .font(.headline)
            ProgressView(value: workflow.progressFraction, total: 1)
                .accessibilityLabel(workflow.progressPhase)
                .accessibilityValue("\(workflow.progressCount), \(workflow.progressFraction.formatted(.percent.precision(.fractionLength(0))))")
            HStack {
                Text(workflow.progressCount)
                Spacer()
                Text(workflow.progressFraction, format: .percent.precision(.fractionLength(0)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(workflow.progressFilename)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel("Current Source PDF")
                .accessibilityValue(workflow.progressFilename)
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }
}

struct PotentialDuplicateReviewSheet: View {
    @Bindable var workflow: AddPapersWorkflow
    let onFinish: () -> Void
    @State private var selectedID: UUID?

    private var selected: PotentialDuplicate? {
        workflow.potentialDuplicates.first { $0.candidate.id == selectedID } ?? workflow.potentialDuplicates.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Potential Duplicates")
                        .font(.title2.bold())
                    Text("Compare each candidate before adding it.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Batch Choose") {
                    Button("Add All as Separate") { workflow.chooseAllPotentialDuplicates(addAsSeparate: true) }
                    Button("Keep All Existing") { workflow.chooseAllPotentialDuplicates(addAsSeparate: false) }
                }
            }
            .padding()

            Divider()
            NavigationSplitView {
                List(workflow.potentialDuplicates, selection: $selectedID) { duplicate in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(duplicate.candidate.metadata.title)
                            .lineLimit(2)
                        Text(decisionLabel(for: duplicate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(duplicate.candidate.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(duplicate.candidate.metadata.title)
                    .accessibilityValue(decisionLabel(for: duplicate))
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } detail: {
                if let selected {
                    PotentialDuplicateComparison(
                        duplicate: selected,
                        decision: Binding(
                            get: { workflow.potentialDecisions[selected.candidate.id] },
                            set: { workflow.potentialDecisions[selected.candidate.id] = $0 }
                        )
                    )
                }
            }
            .frame(height: 420)

            Divider()
            HStack {
                Button("Cancel Remaining Additions") { workflow.cancelPotentialReview() }
                Spacer()
                Text("\(workflow.potentialDecisions.count) of \(workflow.potentialDuplicates.count) decided")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Continue", action: onFinish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!workflow.allPotentialDecisionsMade)
            }
            .padding()
        }
        .frame(width: 860)
        .onAppear { selectedID = workflow.potentialDuplicates.first?.candidate.id }
        .interactiveDismissDisabled()
    }

    private func decisionLabel(for duplicate: PotentialDuplicate) -> String {
        switch workflow.potentialDecisions[duplicate.candidate.id] {
        case .addAsSeparate: "Add as separate Paper"
        case .keepExisting: "Keep existing"
        case nil: "Decision needed"
        }
    }
}

private struct PotentialDuplicateComparison: View {
    let duplicate: PotentialDuplicate
    @Binding var decision: PotentialDuplicateDecision?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(duplicate.triggerReasons.joined(separator: " • "))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)

                comparisonSection("Candidate", title: duplicate.candidate.metadata.title,
                                  authors: duplicate.candidate.metadata.authors.map(\.displayName).joined(separator: ", "),
                                  year: duplicate.candidate.metadata.publicationYear,
                                  doi: duplicate.candidate.metadata.doi,
                                  arxiv: duplicate.candidate.metadata.arxivID,
                                  location: duplicate.candidate.url.path)

                ForEach(duplicate.existingPapers) { paper in
                    comparisonSection("Existing Paper", title: paper.title,
                                      authors: paper.authorFamilyNames.joined(separator: ", "),
                                      year: paper.publicationYear,
                                      doi: paper.doi,
                                      arxiv: paper.arxivID,
                                      location: paper.rememberedLocation)
                }

                Picker("Decision", selection: $decision) {
                    Text("Choose…").tag(PotentialDuplicateDecision?.none)
                    Text("Add as Separate Paper").tag(PotentialDuplicateDecision?.some(.addAsSeparate))
                    Text("Keep Existing").tag(PotentialDuplicateDecision?.some(.keepExisting))
                }
                .pickerStyle(.segmented)
            }
            .padding()
        }
    }

    private func comparisonSection(
        _ heading: String,
        title: String,
        authors: String,
        year: Int?,
        doi: String?,
        arxiv: String?,
        location: String?
    ) -> some View {
        GroupBox(heading) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                row("Title", title)
                row("Authors", authors.isEmpty ? "—" : authors)
                row("Year", year.map(String.init) ?? "—")
                row("DOI", doi ?? "—")
                row("arXiv", arxiv ?? "—")
                row("Location", location ?? "Managed by Canopy")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct AddBatchSummarySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workflow: AddPapersWorkflow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Papers Summary")
                .font(.title2.bold())
            List(workflow.summaryItems) { item in
                HStack(alignment: .top) {
                    Image(systemName: symbol(for: item.kind))
                        .foregroundStyle(color(for: item.kind))
                        .accessibilityLabel(accessibilityLabel(for: item.kind))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.filename)
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let path = item.path {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if !item.actions.isEmpty {
                            HStack {
                                ForEach(Array(item.actions.enumerated()), id: \.offset) { _, action in
                                    Button(action.title) {
                                        workflow.performSummaryAction(
                                            action,
                                            itemID: item.id,
                                            repository: LibraryRepository(context: modelContext)
                                        )
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(workflow.copiedSummaryReport(), forType: .string)
                }
                Spacer()
                Button("Done") {
                    workflow.isSummaryPresented = false
                    workflow.reset()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600, height: 420)
    }

    private func symbol(for kind: AddBatchSummaryItem.Kind) -> String {
        switch kind { case .duplicate: "doc.on.doc"; case .skipped: "minus.circle"; case .failure: "exclamationmark.triangle" }
    }

    private func accessibilityLabel(for kind: AddBatchSummaryItem.Kind) -> String {
        switch kind { case .duplicate: "Duplicate"; case .skipped: "Skipped"; case .failure: "Failure" }
    }

    private func color(for kind: AddBatchSummaryItem.Kind) -> Color {
        switch kind { case .duplicate: .blue; case .skipped: .secondary; case .failure: .red }
    }
}
