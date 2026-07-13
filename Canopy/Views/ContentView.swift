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
    @State private var selectedPaperID: UUID?
    @State private var inspectorPresented = true
    @State private var annotationNavigation: AnnotationNavigation?
    @State private var focusedAnnotationID: UUID?
    @State private var annotationUndoTarget = AnnotationUndoTarget()
    @State private var annotationSession = AnnotationSession()
    @State private var readerReloadToken = UUID()
    @State private var fileImporterPresented = false
    @State private var workflow = AddPapersWorkflow()

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
                onDropURLs: workflow.prepare
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
                reloadToken: $readerReloadToken
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
    }
}
