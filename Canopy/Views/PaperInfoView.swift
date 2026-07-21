import CanopyCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct PaperInfoView: View {
    @Bindable var workflow: PaperInfoWorkflow
    @Bindable var storageConversionWorkflow: PaperStorageConversionWorkflow
    let onReparse: () -> Void
    let onChangeStorage: (PaperStorageMode) -> Void
    let onSave: () -> Void
    @State private var selectedAuthorCreditID: UUID?
    @State private var expandedAuthorCreditIDs: Set<UUID> = []
    @State private var requestedStorageMode: PaperStorageMode?
    @FocusState private var focusedAuthorCreditID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Document Info")
                    .font(.title2.bold())
                Spacer()
            }
            .padding([.horizontal, .top], 24)

            Form {
                Section("Document Information") {
                    metadataField("Title", text: $workflow.draft.title, provenance: workflow.provenance(for: .title))
                    metadataField(
                        workflow.documentKind.dateLabel,
                        text: $workflow.draft.publicationYearText,
                        provenance: workflow.provenance(for: .publicationYear)
                    )
                    if workflow.showsResearchMetadata {
                        metadataField("DOI", text: $workflow.draft.doi, provenance: workflow.provenance(for: .doi))
                        metadataField("arXiv ID", text: $workflow.draft.arxivID, provenance: workflow.provenance(for: .arxivID))
                    }
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

                Section("\(workflow.documentKind.creatorLabel) Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        List(selection: $selectedAuthorCreditID) {
                            if workflow.draft.authorCredits.isEmpty {
                                ContentUnavailableView(
                                    "No Creator Credits",
                                    systemImage: "person.2",
                                    description: Text("Add a creator to include a credit for this Document.")
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
                                Label("Add Creator Credit", systemImage: "plus")
                            }
                            Button(action: removeSelectedAuthorCredit) {
                                Label("Remove Creator Credit", systemImage: "minus")
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
                    LabeledContent("Source PDF Storage") {
                        Picker("Source PDF Storage", selection: Binding(
                            get: { workflow.readOnlyDetails?.storageMode ?? .referenced },
                            set: { mode in
                                guard mode != workflow.readOnlyDetails?.storageMode else { return }
                                requestedStorageMode = mode
                            }
                        )) {
                            Text("Reference Original").tag(PaperStorageMode.referenced)
                            Text("Keep Copy in Canopy").tag(PaperStorageMode.managedCopy)
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                        .disabled(!canConvertStorage)
                        .accessibilityIdentifier("paper-source-storage-picker")
                    }
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
                    if storageConversionWorkflow.isConverting {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Changing Source PDF storage…")
                                .foregroundStyle(.secondary)
                        }
                    } else if workflow.hasChanges {
                        Text("Save or cancel Document Info changes before changing Source PDF storage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(storageConversionWorkflow.isConverting)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") {
                    workflow.dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(storageConversionWorkflow.isConverting)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        !workflow.hasChanges
                            || workflow.hasActiveReparse
                            || storageConversionWorkflow.isConverting
                    )
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
        .interactiveDismissDisabled(
            workflow.hasChanges || workflow.hasActiveReparse || storageConversionWorkflow.isConverting
        )
        .confirmationDialog(
            storageConversionTitle,
            isPresented: Binding(
                get: { requestedStorageMode != nil },
                set: { if !$0 { requestedStorageMode = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let requestedStorageMode {
                Button(storageConversionActionTitle(for: requestedStorageMode)) {
                    self.requestedStorageMode = nil
                    onChangeStorage(requestedStorageMode)
                }
            }
            Button("Cancel", role: .cancel) {
                requestedStorageMode = nil
            }
        } message: {
            Text(storageConversionMessage)
        }
        .alert(
            "Couldn’t Save Document Info",
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
        .alert(
            "Couldn’t Change Source PDF Storage",
            isPresented: Binding(
                get: { storageConversionWorkflow.errorMessage != nil },
                set: { if !$0 { storageConversionWorkflow.errorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(storageConversionWorkflow.errorMessage ?? "Canopy could not change Source PDF storage.")
        }
    }

    private var canConvertStorage: Bool {
        workflow.readOnlyDetails?.sourceState == .available
            && !workflow.hasChanges
            && !workflow.hasActiveReparse
            && !storageConversionWorkflow.isConverting
    }

    private var storageConversionTitle: String {
        requestedStorageMode == .managedCopy ? "Keep Copy in Canopy?" : "Reference Source PDF Outside Canopy?"
    }

    private var storageConversionMessage: String {
        switch requestedStorageMode {
        case .managedCopy:
            "Canopy will verify and keep its own copy. The original Source PDF will remain untouched."
        case .referenced:
            "Choose where to place the Source PDF. Canopy will verify the new file before removing its managed copy."
        case nil:
            ""
        }
    }

    private func storageConversionActionTitle(for mode: PaperStorageMode) -> String {
        mode == .managedCopy ? "Keep Copy in Canopy" : "Choose Location…"
    }

    private func metadataField(
        _ label: String,
        text: Binding<String>,
        provenance: MetadataProvenance?
    ) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing, spacing: 3) {
                TextField(label, text: text)
                    .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity)
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
                        .frame(maxWidth: .infinity)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
