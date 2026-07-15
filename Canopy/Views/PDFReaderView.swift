import CanopyCore
import PDFKit
import SwiftUI

struct PDFReaderView: View {
    let paper: Paper?
    let repository: LibraryRepository
    @Binding var inspectorPresented: Bool
    let annotationNavigation: AnnotationNavigation?
    @Binding var focusedAnnotationID: UUID?
    let annotationUndoTarget: AnnotationUndoTarget
    let annotationSession: AnnotationSession
    @Binding var reloadToken: UUID
    let onGetInfo: () -> Void
    let onSourceRecoveryAction: (SourceRecoveryAction) -> Void
    let onCancelSourceRecovery: () -> Void

    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides

    @State private var documentSession: PDFDocumentSession?
    @State private var restoredState: PaperReaderState?
    @State private var loadError: PDFReaderLoadError?
    @State private var snapshot = PDFReaderSnapshot(pageIndex: 0, viewport: nil, zoomScale: 1)
    @State private var pageEntry = "1"
    @State private var command: PDFReaderCommand?
    @State private var findQuery = ""
    @State private var matches: [PDFSelection] = []
    @State private var matchesVersion = UUID()
    @State private var selectedMatchIndex: Int?
    @State private var pendingSave: PendingReaderSave?
    @State private var failedSave: PendingReaderSave?
    @State private var persistenceErrorMessage: String?
    @FocusState private var findFieldFocused: Bool

    private var pageCount: Int { documentSession?.document.pageCount ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            if documentSession != nil {
                readerControls
                Divider()
            }

            Group {
                if paper == nil {
                    ContentUnavailableView(
                        "Choose a Paper",
                        systemImage: "book.pages",
                        description: Text("Select a recent or library paper to begin reading.")
                    )
                } else if let documentSession {
                    PDFKitReaderView(
                        document: documentSession.document,
                        restoredState: restoredState,
                        command: command,
                        matches: matches,
                        matchesVersion: matchesVersion,
                        selectedMatchIndex: selectedMatchIndex,
                        annotations: annotationSession.paperID == paper?.id && annotationSession.isSourceVerified
                            ? annotationSession.annotations
                            : [],
                        annotationNavigation: annotationNavigation,
                        onCreateAnnotations: createAnnotations,
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
                    ProgressView("Opening Paper…")
                }
            }
        }
        .task(id: loadTaskID) {
            loadPaper()
        }
        .task(id: pendingSave) {
            guard let pendingSave else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, pendingSave == self.pendingSave else { return }
            persist(pendingSave)
        }
        .task(id: findTaskID) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            updateFindMatches()
        }
        .onChange(of: inspectorPresented) { _, isPresented in
            scheduleSave(isInspectorPresented: isPresented)
        }
        .focusedValue(\.paperCommandContext, paperCommandContext)
        .onDisappear {
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
            Text(persistenceErrorMessage ?? "Canopy could not save changes to this Paper.")
        }
    }

    private var loadTaskID: String {
        "\(paper?.id.uuidString ?? "none"):\(reloadToken.uuidString)"
    }

    private var findTaskID: String {
        "\(documentSession?.paperID.uuidString ?? "none"):\(findQuery)"
    }

    private var sourceDocumentContrastCompensation: Double {
        accessibilityOverrides.sourceDocumentContrastCompensation(
            systemIncreasedContrast: colorSchemeContrast == .increased
        )
    }

    private var paperCommandContext: PaperCommandContext? {
        guard documentSession != nil else { return nil }
        return PaperCommandContext(
            availableCommands: PaperCommand.availableReaderCommands(hasFindMatches: !matches.isEmpty),
            perform: performPaperCommand
        )
    }

    private func performPaperCommand(_ paperCommand: PaperCommand) {
        switch paperCommand {
        case .focusFind:
            findFieldFocused = true
        case .nextFindMatch:
            nextMatch()
        case .previousFindMatch:
            previousMatch()
        case .zoomIn:
            command = PDFReaderCommand(action: .zoomIn)
        case .zoomOut:
            command = PDFReaderCommand(action: .zoomOut)
        case .fitWidth:
            command = PDFReaderCommand(action: .fitWidth)
        case .actualSize:
            command = PDFReaderCommand(action: .actualSize)
        case .toggleAnnotations:
            inspectorPresented.toggle()
        }
    }

    private var readerControls: some View {
        HStack(spacing: 8) {
            TextField("Page", text: $pageEntry)
                .frame(width: 42)
                .multilineTextAlignment(.trailing)
                .disabled(documentSession == nil)
                .onSubmit(goToEnteredPage)
                .accessibilityLabel("Page number")

            Text("of \(pageCount)")
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                command = PDFReaderCommand(action: .zoomOut)
            } label: {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .disabled(documentSession == nil)
            .help("Zoom Out")

            Button {
                command = PDFReaderCommand(action: .zoomIn)
            } label: {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .disabled(documentSession == nil)
            .help("Zoom In")

            Menu {
                Button("Fit Width") {
                    command = PDFReaderCommand(action: .fitWidth)
                }
                Button("Actual Size") {
                    command = PDFReaderCommand(action: .actualSize)
                }
            } label: {
                Label("Zoom Options", systemImage: "rectangle.expand.vertical")
            }
            .disabled(documentSession == nil)

            TextField("Find", text: $findQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($findFieldFocused)
                .disabled(documentSession == nil)
                .accessibilityLabel("Find in Paper")

            Button(action: previousMatch) {
                Label("Previous Match", systemImage: "chevron.up")
            }
            .disabled(matches.isEmpty)
            .help("Previous Match")

            Button(action: nextMatch) {
                Label("Next Match", systemImage: "chevron.down")
            }
            .disabled(matches.isEmpty)
            .help("Next Match")

            Text(findResultText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 58, alignment: .leading)
                .accessibilityLabel("Find results")
                .accessibilityValue(findResultText.isEmpty ? "No search" : findResultText)

            Button(action: onGetInfo) {
                Label("Paper Info", systemImage: "info.circle")
            }
            .help("Show Paper Info")

            Button {
                inspectorPresented.toggle()
            } label: {
                Label("Annotations", systemImage: "sidebar.right")
            }
            .help("Show or Hide Annotations")
            .accessibilityValue(inspectorPresented ? "Shown" : "Hidden")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial)
    }

    private var findResultText: String {
        guard !findQuery.isEmpty else { return "" }
        guard let selectedMatchIndex, !matches.isEmpty else { return "0 results" }
        return "\(selectedMatchIndex + 1) of \(matches.count)"
    }

    @MainActor
    private func loadPaper() {
        flushPendingSave()
        annotationSession.beginVerification(paperID: paper?.id)
        documentSession = nil
        restoredState = nil
        loadError = nil
        findQuery = ""
        clearFindMatches()
        pageEntry = "1"
        guard let paper else { return }

        inspectorPresented = paper.isInspectorPresented
        do {
            let sourceAccess = try repository.sourceAccess(paperID: paper.id)
            let session = try PDFDocumentSession(paperID: paper.id, sourceAccess: sourceAccess)
            let savedState = try repository.readerState(paperID: paper.id)
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

    private func updateSnapshot(_ newSnapshot: PDFReaderSnapshot) {
        snapshot = newSnapshot
        pageEntry = String(newSnapshot.pageIndex + 1)
        scheduleSave(isInspectorPresented: inspectorPresented)
    }

    private func scheduleSave(isInspectorPresented: Bool) {
        guard let documentSession else { return }
        pendingSave = PendingReaderSave(
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

    private func persist(_ save: PendingReaderSave) {
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
        command = PDFReaderCommand(action: .goToPage(pageIndex))
    }

    private func updateFindMatches() {
        guard let document = documentSession?.document else {
            clearFindMatches()
            return
        }
        let query = findQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearFindMatches()
            return
        }
        matches = document.findString(query, withOptions: .caseInsensitive)
        matchesVersion = UUID()
        selectedMatchIndex = matches.isEmpty ? nil : 0
    }

    private func clearFindMatches() {
        matches = []
        matchesVersion = UUID()
        selectedMatchIndex = nil
    }

    private func previousMatch() {
        guard !matches.isEmpty else { return }
        let current = selectedMatchIndex ?? 0
        selectedMatchIndex = (current - 1 + matches.count) % matches.count
    }

    private func nextMatch() {
        guard !matches.isEmpty else { return }
        let current = selectedMatchIndex ?? -1
        selectedMatchIndex = (current + 1) % matches.count
    }

    private func createAnnotations(
        anchors: [AnnotationAnchor],
        color: HighlightColor,
        addNote: Bool
    ) {
        guard let paper else { return }
        do {
            let annotations = try repository.createAnnotations(
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
                focusedAnnotationID = annotationID
            }
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }
}

struct AnnotationNavigation: Equatable {
    let id = UUID()
    let annotationID: UUID
}

private struct PendingReaderSave: Equatable {
    let paperID: UUID
    let state: PaperReaderState
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
            "Canopy can’t currently access this Paper’s Source PDF."
        case .sourceMissing:
            "Canopy can’t find this Paper’s Source PDF."
        case .sourceChanged:
            "The Source PDF has changed since this Paper was added."
        case .libraryCopyMissing:
            "Canopy’s managed copy of this Paper is missing."
        case .cannotOpen:
            "The Source PDF could not be read."
        }
    }
}
