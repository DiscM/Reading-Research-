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
            PDFReaderView(paper: selectedPaper)
                .inspector(isPresented: $inspectorPresented) {
                    AnnotationInspectorView(hasSelection: selectedPaperID != nil)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            inspectorPresented.toggle()
                        } label: {
                            Label("Annotations", systemImage: "sidebar.right")
                        }
                    }
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
