import AppKit
import CanopyCore
import Foundation
import PDFKit
import SwiftUI

struct PDFPageNavigation: Equatable {
    let id = UUID()
    let pageIndex: Int
}

struct PDFReaderView: View {
    let paper: Paper?
    let repository: LibraryRepository
    @Binding var inspectorPresented: Bool
    let annotationNavigation: AnnotationNavigation?
    let pageNavigation: PDFPageNavigation?
    @Binding var focusedAnnotationID: UUID?
    @Binding var annotationAdjustmentRequest: AnnotationAdjustmentRequest?
    let annotationUndoTarget: AnnotationUndoTarget
    let annotationSession: AnnotationSession
    @Binding var reloadToken: UUID
    let onGetInfo: () -> Void
    let onShowAnnotations: () -> Void
    let onSourceRecoveryAction: (SourceRecoveryAction) -> Void
    let onCancelSourceRecovery: () -> Void

    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides

    @State private var documentSession: PDFDocumentSession?
    @State private var restoredState: PaperReaderState?
    @State private var loadError: PDFReaderLoadError?
    @State private var snapshot = PDFReaderSnapshot(pageIndex: 0, viewport: nil, zoomScale: 1)
    @State private var pageEntry = "1"
    @State private var transientState = PDFReaderTransientState()
    @State private var findSession = PDFDocumentFindSession()
    @State private var pendingSave: PDFReaderPendingSave?
    @State private var failedSave: PDFReaderPendingSave?
    @State private var persistenceErrorMessage: String?
    @State private var adjustmentCommand: AnnotationAdjustmentCommand?
    @FocusState private var findFieldFocused: Bool

    private var pageCount: Int { documentSession?.document.pageCount ?? 0 }

    var body: some View {
        ZStack {
            CanopyOpaqueSemanticBackground(
                semanticColor: .windowBackgroundColor,
                colorScheme: colorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                if documentSession != nil {
                    readerControls
                    if paper?.hasSelectableText == false {
                        Label(
                            "This PDF has no selectable text. Find and text highlighting are unavailable; Area Annotation still works.",
                            systemImage: "text.magnifyingglass"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 7)
                        .accessibilityLabel(
                            "This PDF has no selectable text. Find and text highlighting are unavailable. Area Annotation remains available."
                        )
                    }
                    if annotationAdjustmentRequest != nil {
                        HStack(spacing: 10) {
                            Label("Adjusting Annotation", systemImage: "move.3d")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Cancel") {
                                adjustmentCommand = AnnotationAdjustmentCommand(action: .cancel)
                            }
                            .keyboardShortcut(.cancelAction)
                            Button("Done") {
                                adjustmentCommand = AnnotationAdjustmentCommand(action: .commit)
                            }
                            .keyboardShortcut(.defaultAction)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 7)
                    }
                    Divider()
                }

                Group {
                    if paper == nil {
                        ContentUnavailableView(
                            "Choose a Document",
                            systemImage: "book.pages",
                            description: Text("Select a recent or library Document to begin reading.")
                        )
                    } else if let documentSession {
                        PDFKitReaderView(
                            document: documentSession.document,
                            restoredState: restoredState,
                            command: transientState.command,
                            matches: findSession.matches,
                            matchesVersion: findSession.resultsVersion,
                            selectedMatchIndex: transientState.selectedMatchIndex,
                            allowsTextAnnotations: paper?.hasSelectableText != false,
                            isAreaAnnotationMode: transientState.isAreaAnnotationMode,
                            pdfInteractionResetID: transientState.pdfInteractionResetID,
                            annotations: annotationSession.paperID == paper?.id && annotationSession.isSourceVerified
                                ? annotationSession.annotations
                                : [],
                            annotationNavigation: annotationNavigation,
                            adjustmentRequest: annotationAdjustmentRequest,
                            adjustmentCommand: adjustmentCommand,
                            onCreateAnnotations: createAnnotations,
                            onCreateAreaAnnotation: createAreaAnnotation,
                            onRequestAnnotationAdjustment: requestAnnotationAdjustment,
                            onDeleteAnnotation: deleteAnnotation,
                            onCommitAnnotationAdjustment: commitAnnotationAdjustment,
                            onCancelAnnotationAdjustment: cancelAnnotationAdjustment,
                            onAreaAnnotationModeEnded: {
                                transientState.isAreaAnnotationMode = false
                            },
                            onTextSelectionRejected: { message in
                                transientState.annotationGuidanceMessage = message
                            },
                            onSnapshotChange: updateSnapshot
                        )
                        .id(documentSession.paperID)
                        .contrast(sourceDocumentContrastCompensation)
                    } else if let loadError {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                loadError.title,
                                systemImage: loadError.systemImage,
                                description: Text(loadError.message)
                            )
                            if let paper {
                                VStack(spacing: 8) {
                                    ForEach(SourceRecoveryAction.actions(for: paper.sourceState)) { action in
                                        Button(
                                            action.title,
                                            role: action == .removeFromLibrary ? .destructive : nil
                                        ) {
                                            onSourceRecoveryAction(action)
                                        }
                                    }
                                    if paper.sourceState == .brokenReference || paper.sourceState == .sourceChanged {
                                        Button("Cancel", role: .cancel, action: onCancelSourceRecovery)
                                    }
                                }
                            }
                        }
                    } else {
                        ProgressView("Opening Document…")
                    }
                }
            }
        }
        .task(id: loadTaskID) {
            loadPaper()
        }
        .onChange(of: pageNavigation) {
            applyPageNavigation()
        }
        .task(id: pendingSave) {
            guard let pendingSave else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, pendingSave == self.pendingSave else { return }
            persist(pendingSave)
        }
        .task(id: findTaskID) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled,
                  paper?.hasSelectableText != false,
                  documentSession?.document != nil else { return }
            updateFindMatches()
        }
        .onChange(of: transientState.findQuery) {
            findSession.cancel(clearResults: true)
            transientState.selectedMatchIndex = nil
        }
        .onChange(of: findSession.resultsVersion) {
            if findSession.matches.isEmpty {
                transientState.selectedMatchIndex = nil
            } else if transientState.selectedMatchIndex == nil {
                transientState.selectedMatchIndex = 0
            }
        }
        .onChange(of: inspectorPresented) { _, isPresented in
            scheduleSave(isInspectorPresented: isPresented)
        }
        .onChange(of: annotationAdjustmentRequest?.requestID) {
            adjustmentCommand = nil
        }
        .focusedValue(\.documentCommandContext, documentCommandContext)
        .onDisappear {
            findSession.cancel(clearResults: true)
            flushPendingSave()
        }
        .alert(
            "Couldn’t Save Changes",
            isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: { if !$0 { persistenceErrorMessage = nil } }
            )
        ) {
            if failedSave != nil {
                Button("Retry", action: retryFailedSave)
            }
            Button("Dismiss", role: .cancel) {
                failedSave = nil
            }
        } message: {
            Text(persistenceErrorMessage ?? "Canopy could not save changes to this Document.")
        }
        .alert(
            "Select Text on One Page",
            isPresented: Binding(
                get: { transientState.annotationGuidanceMessage != nil },
                set: { if !$0 { transientState.annotationGuidanceMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                transientState.annotationGuidanceMessage
                    ?? "Select text on one page at a time, then add the highlight again."
            )
        }
    }

    private var loadTaskID: String {
        "\(paper?.id.uuidString ?? "none"):\(reloadToken.uuidString)"
    }

    private var findTaskID: String {
        "\(documentSession?.paperID.uuidString ?? "none"):\(transientState.findQuery)"
    }

    private var sourceDocumentContrastCompensation: Double {
        accessibilityOverrides.sourceDocumentContrastCompensation(
            systemIncreasedContrast: colorSchemeContrast == .increased
        )
    }

    private var documentCommandContext: DocumentCommandContext? {
        guard documentSession != nil else { return nil }
        return DocumentCommandContext(
            availableCommands: DocumentCommand.availableReaderCommands(
                hasFindMatches: !findSession.matches.isEmpty,
                hasSelectableText: paper?.hasSelectableText != false
            ),
            perform: performDocumentCommand
        )
    }

    private func performDocumentCommand(_ documentCommand: DocumentCommand) {
        switch documentCommand {
        case .focusFind:
            findFieldFocused = true
        case .nextFindMatch:
            nextMatch()
        case .previousFindMatch:
            previousMatch()
        case .zoomIn:
            transientState.command = PDFReaderCommand(action: .zoomIn)
        case .zoomOut:
            transientState.command = PDFReaderCommand(action: .zoomOut)
        case .fitWidth:
            transientState.command = PDFReaderCommand(action: .fitWidth)
        case .actualSize:
            transientState.command = PDFReaderCommand(action: .actualSize)
        case .toggleInspector:
            inspectorPresented.toggle()
        case .startAreaAnnotation:
            transientState.isAreaAnnotationMode = true
        }
    }

    private var readerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper?.title ?? "Document")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("reader-document-title")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    pageControls
                    zoomControls
                    findControls
                    annotationControls
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        pageControls
                        zoomControls
                        annotationControls
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    findControls
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        pageControls
                        zoomControls
                    }
                    .fixedSize(horizontal: true, vertical: false)

                    findControls
                    annotationControls
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if transientState.isAreaAnnotationMode {
                Text("Drag one rectangle on a page. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Area Annotation mode. Drag one rectangle on a page. Press Escape to cancel."
                    )
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CanopySemanticColors.controlBackground(for: colorScheme))
    }

    private var pageControls: some View {
        HStack(spacing: 8) {
            TextField("Page", text: $pageEntry)
                .frame(width: 42)
                .multilineTextAlignment(.trailing)
                .disabled(documentSession == nil)
                .onSubmit(goToEnteredPage)
                .accessibilityIdentifier("reader-page-field")
                .accessibilityLabel("Page number")

            Text("of \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button {
                transientState.command = PDFReaderCommand(action: .zoomOut)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(documentSession == nil)
            .accessibilityLabel("Zoom Out")
            .help("Zoom Out")

            Button {
                transientState.command = PDFReaderCommand(action: .zoomIn)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(documentSession == nil)
            .accessibilityIdentifier("reader-zoom-in")
            .accessibilityLabel("Zoom In")
            .help("Zoom In")

            Menu {
                Button("Fit Width") {
                    transientState.command = PDFReaderCommand(action: .fitWidth)
                }
                Button("Actual Size") {
                    transientState.command = PDFReaderCommand(action: .actualSize)
                }
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .disabled(documentSession == nil)
            .accessibilityLabel("Zoom Options")
            .help("Zoom Options")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var findControls: some View {
        HStack(spacing: 8) {
            TextField("Find", text: $transientState.findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($findFieldFocused)
                .disabled(documentSession == nil || paper?.hasSelectableText == false)
                .accessibilityLabel("Find in Document")

            Button(action: previousMatch) {
                Image(systemName: "chevron.up")
            }
            .disabled(findSession.matches.isEmpty)
            .accessibilityLabel("Previous Match")
            .help("Previous Match")

            Button(action: nextMatch) {
                Image(systemName: "chevron.down")
            }
            .disabled(findSession.matches.isEmpty)
            .accessibilityLabel("Next Match")
            .help("Next Match")

            if findSession.isFinding {
                Button {
                    findSession.cancel()
                } label: {
                    Label("Cancel Find", systemImage: "xmark.circle")
                }
                .help("Cancel Find")
            }

            Text(findResultText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 58, alignment: .leading)
                .accessibilityLabel("Find results")
                .accessibilityValue(findResultText.isEmpty ? "No search" : findResultText)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var annotationControls: some View {
        HStack(spacing: 8) {
            Button {
                transientState.isAreaAnnotationMode.toggle()
            } label: {
                Image(systemName: transientState.isAreaAnnotationMode ? "xmark" : "rectangle.dashed")
            }
            .disabled(documentSession == nil)
            .accessibilityLabel(
                transientState.isAreaAnnotationMode ? "Cancel Area Annotation" : "Area Annotation"
            )
            .help(transientState.isAreaAnnotationMode ? "Cancel Area Annotation" : "Draw an Area Annotation")
            .accessibilityHint(
                transientState.isAreaAnnotationMode
                    ? "Stops drawing an Area Annotation. You can also press Escape."
                    : "Choose this, then drag one rectangle on a PDF page. Press Escape to cancel."
            )

            Button(action: onGetInfo) {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("Document Info")
            .help("Show Document Info")

            #if DEBUG
            if CanopyUITestLibraryConfiguration.isRequested {
                Text("Zoom \(zoomScaleTestValue)")
                    .font(.caption2)
                    .accessibilityIdentifier("reader-zoom-scale")
                    .accessibilityValue(zoomScaleTestValue)

                Text("Viewport Y \(viewportYTestValue)")
                    .font(.caption2)
                    .accessibilityIdentifier("reader-viewport-y")
                    .accessibilityValue(viewportYTestValue)
            }
            #endif
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var zoomScaleTestValue: String {
        snapshot.zoomScale.formatted(.number.precision(.fractionLength(4)))
    }

    private var viewportYTestValue: String {
        guard let viewport = snapshot.viewport else { return "none" }
        return String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            viewport.y
        )
    }

    private var findResultText: String {
        guard !transientState.findQuery.isEmpty else { return "" }
        if findSession.isFinding {
            return findSession.matches.isEmpty
                ? "Searching…"
                : "\(findSession.matches.count) found…"
        }
        guard let selectedMatchIndex = transientState.selectedMatchIndex,
              !findSession.matches.isEmpty else { return "0 results" }
        return "\(selectedMatchIndex + 1) of \(findSession.matches.count)"
    }

    @MainActor
    private func loadPaper() {
        let transitionOutcome = PDFReaderPaperTransition.perform(
            outgoingSave: pendingSave,
            incomingPaperID: paper?.id,
            repository: repository,
            findSession: findSession,
            transientState: &transientState,
            focusedAnnotationID: &focusedAnnotationID
        )
        applyOutgoingSave(from: transitionOutcome)
        annotationSession.beginVerification(paperID: paper?.id)
        documentSession = nil
        restoredState = nil
        snapshot = PDFReaderSnapshot(pageIndex: 0, viewport: nil, zoomScale: 1)
        loadError = nil
        pageEntry = "1"
        guard let paper else { return }

        do {
            let sourceAccess = try repository.sourceAccess(paperID: paper.id)
            let session = try PDFDocumentSession(paperID: paper.id, sourceAccess: sourceAccess)
            if let restoreError = transitionOutcome.restoreError {
                throw restoreError
            }
            let savedState = transitionOutcome.restoredState
            restoredState = savedState
            if let savedState {
                snapshot = PDFReaderSnapshot(
                    pageIndex: savedState.pageIndex,
                    viewport: savedState.viewport,
                    zoomScale: savedState.zoomScale
                )
                pageEntry = String(savedState.pageIndex + 1)
            }
            do {
                try repository.recordPaperOpened(paperID: paper.id)
            } catch {
                persistenceErrorMessage = error.localizedDescription
            }
            documentSession = session
            applyPageNavigation()
            annotationSession.sourceVerified(paperID: paper.id, repository: repository)
        } catch let error as PaperSourceAccessError {
            let readerError = PDFReaderLoadError(error)
            annotationSession.verificationFailed(paperID: paper.id, message: readerError.message)
            loadError = readerError
        } catch let error as PDFReaderLoadError {
            annotationSession.verificationFailed(paperID: paper.id, message: error.message)
            loadError = error
        } catch {
            annotationSession.verificationFailed(
                paperID: paper.id,
                message: PDFReaderLoadError.cannotOpen.message
            )
            loadError = .cannotOpen
        }
    }

    private func applyPageNavigation() {
        guard let pageNavigation, pageCount > 0 else { return }
        let pageIndex = min(max(pageNavigation.pageIndex, 0), pageCount - 1)
        pageEntry = String(pageIndex + 1)
        transientState.command = PDFReaderCommand(action: .goToPage(pageIndex))
    }

    private func applyOutgoingSave(from outcome: PDFReaderPaperTransitionOutcome) {
        guard let outgoingSave = outcome.outgoingSave else { return }
        if let outgoingSaveError = outcome.outgoingSaveError {
            failedSave = outgoingSave
            persistenceErrorMessage = outgoingSaveError.localizedDescription
            return
        }
        if pendingSave == outgoingSave {
            pendingSave = nil
        }
        if failedSave?.paperID == outgoingSave.paperID {
            failedSave = nil
            persistenceErrorMessage = nil
        }
    }

    private func updateSnapshot(_ newSnapshot: PDFReaderSnapshot) {
        snapshot = newSnapshot
        pageEntry = String(newSnapshot.pageIndex + 1)
        scheduleSave(isInspectorPresented: inspectorPresented)
    }

    private func scheduleSave(isInspectorPresented: Bool) {
        guard let documentSession else { return }
        pendingSave = PDFReaderPendingSave(
            paperID: documentSession.paperID,
            state: PaperReaderState(
                pageIndex: snapshot.pageIndex,
                viewport: snapshot.viewport,
                zoomScale: snapshot.zoomScale,
                isInspectorPresented: isInspectorPresented
            )
        )
    }

    private func flushPendingSave() {
        guard let pendingSave else { return }
        persist(pendingSave)
    }

    private func persist(_ save: PDFReaderPendingSave) {
        do {
            try repository.saveReaderState(paperID: save.paperID, state: save.state)
            if pendingSave == save {
                pendingSave = nil
            }
            if failedSave?.paperID == save.paperID {
                failedSave = nil
                persistenceErrorMessage = nil
            }
        } catch {
            failedSave = save
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func retryFailedSave() {
        guard let failedSave else { return }
        persist(failedSave)
    }

    private func goToEnteredPage() {
        guard pageCount > 0 else { return }
        let enteredPage = Int(pageEntry) ?? (snapshot.pageIndex + 1)
        let pageIndex = min(max(enteredPage - 1, 0), pageCount - 1)
        pageEntry = String(pageIndex + 1)
        transientState.command = PDFReaderCommand(action: .goToPage(pageIndex))
    }

    private func updateFindMatches() {
        guard let document = documentSession?.document else {
            clearFindMatches()
            return
        }
        let query = transientState.findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearFindMatches()
            return
        }
        findSession.start(query: query, in: document)
    }

    private func clearFindMatches() {
        findSession.cancel(clearResults: true)
        transientState.selectedMatchIndex = nil
    }

    private func previousMatch() {
        guard !findSession.matches.isEmpty else { return }
        let current = transientState.selectedMatchIndex ?? 0
        transientState.selectedMatchIndex = (current - 1 + findSession.matches.count) % findSession.matches.count
    }

    private func nextMatch() {
        guard !findSession.matches.isEmpty else { return }
        let current = transientState.selectedMatchIndex ?? -1
        transientState.selectedMatchIndex = (current + 1) % findSession.matches.count
    }

    private func createAnnotations(
        anchors: [TextAnnotationAnchor],
        color: HighlightColor,
        addNote: Bool
    ) {
        guard let paper else { return }
        do {
            let annotations = try repository.createTextAnnotations(
                paperID: paper.id,
                anchors: anchors,
                color: color
            )
            let annotationIDs = annotations.map(\.id)
            AnnotationUndo.registerUndoForCreation(
                annotationIDs: annotationIDs,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: { annotationSession.reload(repository: repository) },
                onError: { persistenceErrorMessage = $0.localizedDescription }
            )
            annotationSession.reload(repository: repository)

            if addNote, let annotationID = annotationIDs.first {
                inspectorPresented = true
                onShowAnnotations()
                focusedAnnotationID = annotationID
            }
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func createAreaAnnotation(
        _ selection: PDFPageAreaSelection,
        color: HighlightColor,
        addNote: Bool
    ) {
        guard let paper else { return }
        let rectangle = selection.rectangle.standardized
        let anchor = AreaAnnotationAnchor(
            pageIndex: selection.pageIndex,
            rect: AnnotationRect(
                x: rectangle.minX,
                y: rectangle.minY,
                width: rectangle.width,
                height: rectangle.height
            )
        )
        do {
            let annotation = try repository.createAreaAnnotation(
                paperID: paper.id,
                anchor: anchor,
                color: color
            )
            AnnotationUndo.registerUndoForCreation(
                annotationIDs: [annotation.id],
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: { annotationSession.reload(repository: repository) },
                onError: { persistenceErrorMessage = $0.localizedDescription }
            )
            annotationSession.reload(repository: repository)

            if addNote {
                inspectorPresented = true
                onShowAnnotations()
                focusedAnnotationID = annotation.id
            }
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func commitAnnotationAdjustment(
        annotationID: UUID,
        anchor: AnnotationAnchorValue
    ) -> Bool {
        guard annotationAdjustmentRequest?.annotationID == annotationID,
              let annotation = annotationSession.annotations.first(where: { $0.id == annotationID }),
              let previousAnchor = AnnotationAnchorValue(annotation: annotation) else {
            annotationAdjustmentRequest = nil
            return false
        }
        if previousAnchor == anchor {
            annotationAdjustmentRequest = nil
            return true
        }
        do {
            try repository.updateAnnotationAnchor(annotationID: annotationID, anchor: anchor)
            AnnotationUndo.registerUndoForAnchorChange(
                annotationID: annotationID,
                previousAnchor: previousAnchor,
                currentAnchor: anchor,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: { annotationSession.reload(repository: repository) },
                onError: { persistenceErrorMessage = $0.localizedDescription }
            )
            annotationSession.reload(repository: repository)
            annotationAdjustmentRequest = nil
            return true
        } catch {
            persistenceErrorMessage = error.localizedDescription
            return false
        }
    }

    private func requestAnnotationAdjustment(_ annotationID: UUID) {
        guard annotationAdjustmentRequest == nil else { return }
        annotationAdjustmentRequest = AnnotationAdjustmentRequest(annotationID: annotationID)
    }

    private func deleteAnnotation(_ annotationID: UUID) {
        do {
            let snapshot = try repository.deleteAnnotation(annotationID: annotationID)
            if annotationAdjustmentRequest?.annotationID == annotationID {
                annotationAdjustmentRequest = nil
            }
            AnnotationUndo.registerUndoForDeletion(
                snapshot: snapshot,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: { annotationSession.reload(repository: repository) },
                onError: { persistenceErrorMessage = $0.localizedDescription }
            )
            annotationSession.reload(repository: repository)
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func cancelAnnotationAdjustment() {
        annotationAdjustmentRequest = nil
    }
}

struct AnnotationNavigation: Equatable {
    let id = UUID()
    let annotationID: UUID
}

struct PDFReaderTransientState: Equatable {
    var command: PDFReaderCommand?
    var findQuery: String
    var selectedMatchIndex: Int?
    var isAreaAnnotationMode: Bool
    var annotationGuidanceMessage: String?

    /// Changing this value tells the PDFKit coordinator to discard any selection or
    /// pending annotation popover that belonged to the previously selected Paper.
    private(set) var pdfInteractionResetID: UUID

    init(
        command: PDFReaderCommand? = nil,
        findQuery: String = "",
        selectedMatchIndex: Int? = nil,
        isAreaAnnotationMode: Bool = false,
        annotationGuidanceMessage: String? = nil,
        pdfInteractionResetID: UUID = UUID()
    ) {
        self.command = command
        self.findQuery = findQuery
        self.selectedMatchIndex = selectedMatchIndex
        self.isAreaAnnotationMode = isAreaAnnotationMode
        self.annotationGuidanceMessage = annotationGuidanceMessage
        self.pdfInteractionResetID = pdfInteractionResetID
    }

    mutating func resetForPaperTransition() {
        command = nil
        findQuery = ""
        selectedMatchIndex = nil
        isAreaAnnotationMode = false
        annotationGuidanceMessage = nil
        pdfInteractionResetID = UUID()
    }
}

struct PDFReaderPendingSave: Equatable {
    let paperID: UUID
    let state: PaperReaderState
}

struct PDFReaderPaperTransitionOutcome {
    let outgoingSave: PDFReaderPendingSave?
    let outgoingSaveError: (any Error)?
    let restoredState: PaperReaderState?
    let restoreError: (any Error)?

    var outgoingSaveSucceeded: Bool {
        outgoingSave != nil && outgoingSaveError == nil
    }

    var restoreSucceeded: Bool {
        restoreError == nil
    }
}

@MainActor
enum PDFReaderPaperTransition {
    static func perform(
        outgoingSave: PDFReaderPendingSave?,
        incomingPaperID: UUID?,
        repository: LibraryRepository,
        findSession: PDFDocumentFindSession,
        transientState: inout PDFReaderTransientState,
        focusedAnnotationID: inout UUID?
    ) -> PDFReaderPaperTransitionOutcome {
        var outgoingSaveError: (any Error)?
        if let outgoingSave {
            do {
                try repository.saveReaderState(
                    paperID: outgoingSave.paperID,
                    state: outgoingSave.state
                )
            } catch {
                outgoingSaveError = error
            }
        }

        findSession.cancel(clearResults: true)
        transientState.resetForPaperTransition()
        focusedAnnotationID = nil

        var restoredState: PaperReaderState?
        var restoreError: (any Error)?
        if let incomingPaperID {
            do {
                restoredState = try repository.readerState(paperID: incomingPaperID)
            } catch {
                restoreError = error
            }
        }

        return PDFReaderPaperTransitionOutcome(
            outgoingSave: outgoingSave,
            outgoingSaveError: outgoingSaveError,
            restoredState: restoredState,
            restoreError: restoreError
        )
    }
}

@MainActor
private final class PDFDocumentSession {
    let paperID: UUID
    let document: PDFDocument
    private let sourceAccess: PaperSourceAccess

    init(paperID: UUID, sourceAccess: PaperSourceAccess) throws {
        self.paperID = paperID
        self.sourceAccess = sourceAccess
        guard let document = PDFDocument(url: sourceAccess.url) else {
            throw PDFReaderLoadError.cannotOpen
        }
        self.document = document
    }
}

private enum PDFReaderLoadError: Error, Equatable {
    case sourceUnavailable
    case sourceMissing
    case sourceChanged
    case libraryCopyMissing
    case cannotOpen

    init(_ sourceError: PaperSourceAccessError) {
        switch sourceError {
        case .sourceUnavailable: self = .sourceUnavailable
        case .sourceMissing: self = .sourceMissing
        case .sourceChanged: self = .sourceChanged
        case .libraryCopyMissing: self = .libraryCopyMissing
        }
    }

    var title: String {
        switch self {
        case .sourceUnavailable: "Source Unavailable"
        case .sourceMissing: "Source Missing"
        case .sourceChanged: "Source Changed"
        case .libraryCopyMissing: "Library Copy Missing"
        case .cannotOpen: "Couldn’t Open PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .sourceUnavailable: "externaldrive.badge.exclamationmark"
        case .sourceMissing: "link.badge.plus"
        case .sourceChanged: "exclamationmark.triangle"
        case .libraryCopyMissing: "doc.badge.ellipsis"
        case .cannotOpen: "doc.badge.exclamationmark"
        }
    }

    var message: String {
        switch self {
        case .sourceUnavailable:
            "Canopy can’t currently access this Document’s Source PDF."
        case .sourceMissing:
            "Canopy can’t find this Document’s Source PDF."
        case .sourceChanged:
            "The Source PDF has changed since this Document was added."
        case .libraryCopyMissing:
            "Canopy’s managed copy of this Document is missing."
        case .cannotOpen:
            "The Source PDF could not be read."
        }
    }
}
