import AppKit
import CanopyCore
import SwiftData
import SwiftUI

struct AddBatchStorageSheet: View {
    @Bindable var workflow: AddDocumentsWorkflow
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Documents")
                .font(.title2.bold())
            Text("\(workflow.pendingURLs.count) PDF\(workflow.pendingURLs.count == 1 ? "" : "s") • \(ByteCountFormatter.string(fromByteCount: workflow.totalFileSize, countStyle: .file))")
                .foregroundStyle(.secondary)

            Picker("Document Kind", selection: $workflow.documentKind) {
                ForEach(DocumentKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }

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
                Button("Add Documents", action: onAdd)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("confirm-add-documents-button")
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityIdentifier("add-documents-storage-sheet")
    }
}

struct AddBatchProgressSheet: View {
    @Bindable var workflow: AddDocumentsWorkflow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(workflow.progressPhase.title)
                .font(.headline)
            ProgressView(value: workflow.progressFraction, total: 1)
                .accessibilityLabel(workflow.progressPhase.title)
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
            if workflow.canCancelCheckingDocuments {
                HStack {
                    Spacer()
                    Button("Cancel") {
                        workflow.cancelCheckingDocuments()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }
}

struct PotentialDuplicateReviewSheet: View {
    @Bindable var workflow: AddDocumentsWorkflow
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
                Button("Cancel Add Batch", role: .cancel) { workflow.cancelPotentialReview() }
                    .keyboardShortcut(.cancelAction)
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
        .frame(width: 980)
        .onAppear { selectedID = workflow.potentialDuplicates.first?.candidate.id }
        .interactiveDismissDisabled()
    }

    private func decisionLabel(for duplicate: PotentialDuplicate) -> String {
        switch workflow.potentialDecisions[duplicate.candidate.id] {
        case .addAsSeparate: "Add as separate Document"
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
                ForEach(duplicate.matches) { match in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Trigger: \(match.triggerReasons.joined(separator: " • "))")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Potential duplicate trigger for \(match.existingPaper.title)")
                            .accessibilityValue(match.triggerReasons.joined(separator: ", "))

                        HStack(alignment: .top, spacing: 16) {
                            comparisonSection(
                                "Candidate",
                                fields: PotentialDuplicateComparisonFields(candidate: duplicate.candidate)
                            )
                            comparisonSection(
                                "Existing Research Paper",
                                fields: PotentialDuplicateComparisonFields(existingPaper: match.existingPaper)
                            )
                        }
                    }
                }

                Picker("Decision", selection: $decision) {
                    Text("Choose…").tag(PotentialDuplicateDecision?.none)
                    Text("Add as Separate Document").tag(PotentialDuplicateDecision?.some(.addAsSeparate))
                    Text("Keep Existing").tag(PotentialDuplicateDecision?.some(.keepExisting))
                }
                .pickerStyle(.segmented)
            }
            .padding()
        }
    }

    private func comparisonSection(
        _ heading: String,
        fields: PotentialDuplicateComparisonFields
    ) -> some View {
        GroupBox(heading) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                row("Title", fields.title)
                row("Authors", fields.authors)
                row("Year", fields.year)
                row("DOI", fields.doi)
                row("arXiv", fields.arxivID)
                row(fields.sourceLabel, fields.source)
                row("File Size", fields.fileSize)
                row("Page Count", fields.pageCount)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct PotentialDuplicateComparisonFields: Equatable {
    let title: String
    let authors: String
    let year: String
    let doi: String
    let arxivID: String
    let sourceLabel: String
    let source: String
    let fileSize: String
    let pageCount: String

    init(candidate: PreflightCandidate) {
        title = candidate.metadata.title
        authors = Self.display(candidate.metadata.authors.map(\.displayName).joined(separator: ", "))
        year = candidate.metadata.publicationYear.map(String.init) ?? "—"
        doi = Self.display(candidate.metadata.doi)
        arxivID = Self.display(candidate.metadata.arxivID)
        sourceLabel = "Filename"
        source = candidate.url.lastPathComponent
        fileSize = ByteCountFormatter.string(fromByteCount: candidate.fileSize, countStyle: .file)
        pageCount = String(candidate.metadata.pageCount)
    }

    init(existingPaper paper: PaperIdentitySnapshot) {
        title = paper.title
        authors = Self.display(paper.authorDisplayNames.joined(separator: ", "))
        year = paper.publicationYear.map(String.init) ?? "—"
        doi = Self.display(paper.doi)
        arxivID = Self.display(paper.arxivID)
        if let rememberedLocation = paper.rememberedLocation, !rememberedLocation.isEmpty {
            sourceLabel = "Remembered Location"
            source = rememberedLocation
        } else {
            sourceLabel = "Filename"
            source = Self.display(paper.sourceFilename)
        }
        fileSize = ByteCountFormatter.string(fromByteCount: paper.sourceFileSize, countStyle: .file)
        pageCount = String(paper.pageCount)
    }

    private static func display(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }
}

struct AddBatchSummarySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var workflow: AddDocumentsWorkflow
    let onOpenPaper: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Documents Summary")
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
                                            repository: LibraryRepository(context: modelContext),
                                            onOpenPaper: onOpenPaper
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
