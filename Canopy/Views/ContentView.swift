import CanopyCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let addPapersRequested = Notification.Name("Canopy.addPapersRequested")
    static let openPaperRequested = Notification.Name("Canopy.openPaperRequested")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @State private var selectedPaperID: UUID?
    @State private var inspectorPresented = true
    @State private var annotationNavigation: AnnotationNavigation?
    @State private var focusedAnnotationID: UUID?
    @State private var annotationUndoTarget = AnnotationUndoTarget()
    @State private var annotationSession = AnnotationSession()
    @State private var readerReloadToken = UUID()
    @State private var fileImporterPresented = false
    @State private var workflow = AddPapersWorkflow()
    @State private var paperInfoWorkflow = PaperInfoWorkflow()
    @State private var paperInfoUndoTarget = PaperInfoUndoTarget()
    @State private var paperRemovalUndoTarget = PaperRemovalUndoTarget()
    @State private var commandErrorMessage: String?

    private var repository: LibraryRepository { LibraryRepository(context: modelContext) }
    private var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return try? repository.paper(id: selectedPaperID)
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(
                selection: $selectedPaperID,
                onAddPapers: { fileImporterPresented = true },
                onDropURLs: workflow.prepare,
                onClearRecentHistory: repository.clearRecentHistory,
                onRemovePaper: { paperID in
                    let snapshot = try repository.removePaper(paperID: paperID)
                    PaperRemovalUndo.register(
                        snapshot: snapshot,
                        repository: repository,
                        target: paperRemovalUndoTarget,
                        undoManager: undoManager,
                        onError: { commandErrorMessage = $0.localizedDescription }
                    )
                },
                onGetInfo: presentPaperInfo
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            PDFReaderView(
                paper: selectedPaper,
                repository: repository,
                inspectorPresented: $inspectorPresented,
                annotationNavigation: annotationNavigation,
                focusedAnnotationID: $focusedAnnotationID,
                annotationUndoTarget: annotationUndoTarget,
                annotationSession: annotationSession,
                reloadToken: $readerReloadToken,
                onGetInfo: {
                    if let selectedPaperID {
                        presentPaperInfo(selectedPaperID)
                    }
                }
            )
                .inspector(isPresented: $inspectorPresented) {
                    AnnotationInspectorView(
                        paper: selectedPaper,
                        repository: repository,
                        focusedAnnotationID: $focusedAnnotationID,
                        annotationUndoTarget: annotationUndoTarget,
                        annotationSession: annotationSession,
                        onRetrySource: { readerReloadToken = UUID() },
                        onNavigate: { annotationID in
                            annotationNavigation = AnnotationNavigation(annotationID: annotationID)
                        }
                    )
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
        }
        .fileImporter(
            isPresented: $fileImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                workflow.prepare(urls: urls)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addPapersRequested)) { _ in
            fileImporterPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPaperRequested)) { notification in
            selectedPaperID = notification.object as? UUID
        }
        .onChange(of: selectedPaperID) {
            annotationNavigation = nil
            focusedAnnotationID = nil
            annotationSession.beginVerification(paperID: selectedPaperID)
        }
        .focusedValue(
            \.paperInfoCommandAction,
            selectedPaperID.map { paperID in
                PaperInfoCommandAction {
                    presentPaperInfo(paperID)
                }
            }
        )
        .sheet(isPresented: $workflow.isStorageChoicePresented) {
            AddBatchStorageSheet(workflow: workflow) {
                workflow.start(repository: repository)
            }
        }
        .sheet(isPresented: $workflow.isProgressPresented) {
            AddBatchProgressSheet(workflow: workflow)
        }
        .sheet(isPresented: $workflow.isPotentialReviewPresented) {
            PotentialDuplicateReviewSheet(workflow: workflow) {
                workflow.finishPotentialReview(repository: repository)
            }
        }
        .sheet(isPresented: $workflow.isSummaryPresented) {
            AddBatchSummarySheet(workflow: workflow)
        }
        .sheet(
            isPresented: Binding(
                get: { paperInfoWorkflow.isPresented },
                set: { if !$0 { paperInfoWorkflow.dismiss() } }
            )
        ) {
            PaperInfoView(
                workflow: paperInfoWorkflow,
                onReparse: {
                    Task { @MainActor in
                        await paperInfoWorkflow.reparse(repository: repository)
                    }
                },
                onSave: savePaperInfo
            )
        }
        .alert(
            "Couldn’t Complete Action",
            isPresented: Binding(
                get: { commandErrorMessage != nil },
                set: { if !$0 { commandErrorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(commandErrorMessage ?? "Canopy could not complete this action.")
        }
    }

    private func presentPaperInfo(_ paperID: UUID) {
        do {
            try paperInfoWorkflow.present(paperID: paperID, repository: repository)
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func savePaperInfo() {
        do {
            let target = try paperInfoWorkflow.makeTargetSnapshot()
            let change = try repository.applyPaperInfoSnapshot(target)
            PaperInfoUndo.register(
                change: change,
                repository: repository,
                target: paperInfoUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            paperInfoWorkflow.finishSaving(change)
        } catch {
            paperInfoWorkflow.errorMessage = error.localizedDescription
        }
    }
}
