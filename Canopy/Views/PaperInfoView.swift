import CanopyCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct PaperInfoView: View {
    @Bindable var workflow: PaperInfoWorkflow
    let onReparse: () -> Void
    let onSave: () -> Void
    @State private var selectedAuthorCreditID: UUID?
    @State private var expandedAuthorCreditIDs: Set<UUID> = []
    @FocusState private var focusedAuthorCreditID: UUID?

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
                    metadataField("Title", text: $workflow.draft.title, provenance: workflow.provenance(for: .title))
                    metadataField(
                        "Publication Year",
                        text: $workflow.draft.publicationYearText,
                        provenance: workflow.provenance(for: .publicationYear)
                    )
                    metadataField("DOI", text: $workflow.draft.doi, provenance: workflow.provenance(for: .doi))
                    metadataField("arXiv ID", text: $workflow.draft.arxivID, provenance: workflow.provenance(for: .arxivID))
                }
                .disabled(workflow.hasActiveReparse)

                if let proposal = workflow.reparseProposal {
                    Section("Fresh Metadata") {
                        PaperInfoReparseReviewView(
                            proposal: proposal,
                            onUseFound: workflow.acceptReparsed,
                            onKeepCurrent: workflow.keepCurrent,
                            onKeepAllCurrent: workflow.discardReparseResults,
                            onFinish: workflow.finishReparseReview
                        )
                    }
                }

                Section("Author Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        List(selection: $selectedAuthorCreditID) {
                            if workflow.draft.authorCredits.isEmpty {
                                ContentUnavailableView(
                                    "No Author Credits",
                                    systemImage: "person.2",
                                    description: Text("Add an author to include a credit for this Paper.")
                                )
                            } else {
                                ForEach(Array(workflow.draft.authorCredits.enumerated()), id: \.element.id) { index, author in
                                    PaperInfoAuthorCreditRow(
                                        id: author.id,
                                        position: index,
                                        displayName: authorCreditDisplayNameBinding(for: author.id),
                                        familyName: authorCreditFamilyNameBinding(for: author.id),
                                        provenance: workflow.authorProvenance(id: author.id),
                                        isExpanded: authorCreditExpansionBinding(for: author.id),
                                        displayNameFocus: $focusedAuthorCreditID,
                                        canMoveUp: index > 0,
                                        canMoveDown: index + 1 < workflow.draft.authorCredits.count,
                                        onMoveUp: { moveAuthor(author.id, by: -1) },
                                        onMoveDown: { moveAuthor(author.id, by: 1) },
                                        onRemove: { removeAuthorCredit(author.id) }
                                    )
                                    .tag(author.id)
                                }
                                .dropDestination(for: PaperInfoAuthorCreditDragPayload.self) { payloads, insertionIndex in
                                    guard let draggedID = payloads.first?.id else { return }
                                    workflow.draft.moveAuthorCredit(
                                        id: draggedID,
                                        toInsertionIndex: insertionIndex
                                    )
                                    selectedAuthorCreditID = draggedID
                                }
                            }
                        }
                        .listStyle(.bordered)
                        .alternatingRowBackgrounds()
                        .frame(minHeight: 190, idealHeight: 220, maxHeight: 260)
                        .onDeleteCommand(perform: removeSelectedAuthorCredit)

                        HStack(spacing: 8) {
                            Button(action: addAuthorCredit) {
                                Label("Add Author Credit", systemImage: "plus")
                            }
                            Button(action: removeSelectedAuthorCredit) {
                                Label("Remove Author Credit", systemImage: "minus")
                            }
                            .disabled(!hasSelectedAuthorCredit)

                            Divider()
                                .frame(height: 18)

                            Button { moveSelectedAuthorCredit(by: -1) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                            .disabled(!canMoveSelectedAuthorCredit(by: -1))
                            Button { moveSelectedAuthorCredit(by: 1) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                            .disabled(!canMoveSelectedAuthorCredit(by: 1))

                            Spacer()
                            Text("Drag a row’s handle to reorder")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .controlSize(.small)
                    }
                }
                .disabled(workflow.hasActiveReparse)

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
                    HStack {
                        Button(action: onReparse) {
                            Label("Reparse Metadata…", systemImage: "arrow.clockwise")
                        }
                        .disabled(workflow.hasActiveReparse)

                        if workflow.isReparsing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Reading fresh metadata…")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    if let message = workflow.reparseMessage {
                        Label(message, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
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
                    .disabled(!workflow.hasChanges || workflow.hasActiveReparse)
            }
            .padding(16)
        }
        .frame(width: 680, height: 760)
        .onAppear(perform: resetAuthorCreditViewState)
        .onChange(of: workflow.paperID) {
            resetAuthorCreditViewState()
        }
        .onChange(of: workflow.draft.authorCredits.map(\.id)) {
            reconcileAuthorCreditViewState()
        }
        .interactiveDismissDisabled(workflow.hasChanges || workflow.hasActiveReparse)
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
        .alert(
            "Couldn’t Reparse Metadata",
            isPresented: Binding(
                get: { workflow.reparseErrorMessage != nil },
                set: { if !$0 { workflow.reparseErrorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(workflow.reparseErrorMessage ?? "Canopy could not read fresh metadata from this Source PDF.")
        }
    }

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
                    Text(provenance.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func authorCreditDisplayNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                workflow.draft.authorCredits.first(where: { $0.id == id })?.displayName ?? ""
            },
            set: { workflow.draft.updateAuthorDisplayName(id: id, displayName: $0) }
        )
    }

    private func authorCreditFamilyNameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                workflow.draft.authorCredits.first(where: { $0.id == id })?.familyName ?? ""
            },
            set: { workflow.draft.updateAuthorFamilyName(id: id, familyName: $0) }
        )
    }

    private func authorCreditExpansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedAuthorCreditIDs.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedAuthorCreditIDs.insert(id)
                } else {
                    expandedAuthorCreditIDs.remove(id)
                }
            }
        )
    }

    private func addAuthorCredit() {
        let id = UUID()
        workflow.draft.addAuthorCredit(id: id)
        selectedAuthorCreditID = id
        expandedAuthorCreditIDs.insert(id)
        focusedAuthorCreditID = id
    }

    private func removeSelectedAuthorCredit() {
        guard let selectedAuthorCreditID else { return }
        removeAuthorCredit(selectedAuthorCreditID)
    }

    private func removeAuthorCredit(_ id: UUID) {
        guard let removedIndex = workflow.draft.authorCredits.firstIndex(where: { $0.id == id }) else { return }
        workflow.draft.removeAuthorCredit(id: id)
        expandedAuthorCreditIDs.remove(id)
        if selectedAuthorCreditID == id {
            if workflow.draft.authorCredits.isEmpty {
                selectedAuthorCreditID = nil
            } else {
                let nextIndex = min(removedIndex, workflow.draft.authorCredits.count - 1)
                selectedAuthorCreditID = workflow.draft.authorCredits[nextIndex].id
            }
        }
    }

    private func moveSelectedAuthorCredit(by offset: Int) {
        guard let selectedAuthorCreditID else { return }
        moveAuthor(selectedAuthorCreditID, by: offset)
    }

    private func moveAuthor(_ id: UUID, by offset: Int) {
        workflow.draft.moveAuthorCredit(id: id, by: offset)
        selectedAuthorCreditID = id
    }

    private func canMoveSelectedAuthorCredit(by offset: Int) -> Bool {
        guard let selectedAuthorCreditID,
              let index = workflow.draft.authorCredits.firstIndex(where: { $0.id == selectedAuthorCreditID }) else {
            return false
        }
        return workflow.draft.authorCredits.indices.contains(index + offset)
    }

    private var hasSelectedAuthorCredit: Bool {
        guard let selectedAuthorCreditID else { return false }
        return workflow.draft.authorCredits.contains { $0.id == selectedAuthorCreditID }
    }

    private func resetAuthorCreditViewState() {
        selectedAuthorCreditID = nil
        expandedAuthorCreditIDs = []
        focusedAuthorCreditID = nil
    }

    private func reconcileAuthorCreditViewState() {
        let authorIDs = Set(workflow.draft.authorCredits.map(\.id))
        expandedAuthorCreditIDs.formIntersection(authorIDs)
        if let selectedAuthorCreditID, !authorIDs.contains(selectedAuthorCreditID) {
            self.selectedAuthorCreditID = nil
        }
        if let focusedAuthorCreditID, !authorIDs.contains(focusedAuthorCreditID) {
            self.focusedAuthorCreditID = nil
        }
    }
}

private struct PaperInfoAuthorCreditRow: View {
    let id: UUID
    let position: Int
    @Binding var displayName: String
    @Binding var familyName: String
    let provenance: MetadataProvenance
    @Binding var isExpanded: Bool
    let displayNameFocus: FocusState<UUID?>.Binding
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 5) {
                LabeledContent("Family Name") {
                    TextField("Family Name", text: $familyName)
                        .frame(minWidth: 260)
                }
                Text("Used for duplicate matching.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Family Name is required.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 5)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .draggable(PaperInfoAuthorCreditDragPayload(id: id))
                    .help("Drag to reorder this Author Credit")
                    .accessibilityHidden(true)
                Text("\(position + 1).")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Display Name", text: $displayName)
                        .focused(displayNameFocus, equals: id)
                    if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Display Name is required.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text(provenance.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button(role: .destructive, action: onRemove) {
                    Label("Remove Author Credit", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Remove this Author Credit")
            }
        }
        .accessibilityAction(named: "Move Up", onMoveUp)
        .accessibilityAction(named: "Move Down", onMoveDown)
        .accessibilityAction(named: "Remove Author Credit", onRemove)
        .accessibilityHint("Author Credit \(position + 1). Expand to edit the family name.")
        .contextMenu {
            Button("Move Up", action: onMoveUp)
                .disabled(!canMoveUp)
            Button("Move Down", action: onMoveDown)
                .disabled(!canMoveDown)
            Divider()
            Button("Remove Author Credit", role: .destructive, action: onRemove)
        }
    }
}

private struct PaperInfoAuthorCreditDragPayload: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .canopyAuthorCreditDrag)
    }
}

private extension UTType {
    static let canopyAuthorCreditDrag = UTType(
        exportedAs: "com.discm.Canopy.author-credit-drag"
    )
}

extension MetadataProvenance {
    var displayName: String {
        switch self {
        case .embeddedMetadata: "Embedded metadata"
        case .firstPage: "First page"
        case .filenameFallback: "Filename fallback"
        case .userEntry: "User entry"
        }
    }
}
