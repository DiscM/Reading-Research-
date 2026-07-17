import CanopyCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    let managedCopyReconciliationWarning: String?
    let isRetryingManagedCopyReconciliation: Bool
    let onRetryManagedCopyReconciliation: @MainActor () -> Void

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
    @State private var sourceRecoveryWorkflow = SourceRecoveryWorkflow()
    @State private var didCheckSourceAvailability = false
    @State private var paperRemovalRequest: PaperRemovalRequest?
    @State private var commandErrorMessage: String?

    private var repository: LibraryRepository { LibraryRepository(context: modelContext) }
    private var selectedPaper: Paper? {
        guard let selectedPaperID else { return nil }
        return try? repository.paper(id: selectedPaperID)
    }

    init(
        managedCopyReconciliationWarning: String? = nil,
        isRetryingManagedCopyReconciliation: Bool = false,
        onRetryManagedCopyReconciliation: @escaping @MainActor () -> Void = {}
    ) {
        self.managedCopyReconciliationWarning = managedCopyReconciliationWarning
        self.isRetryingManagedCopyReconciliation = isRetryingManagedCopyReconciliation
        self.onRetryManagedCopyReconciliation = onRetryManagedCopyReconciliation
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(
                selection: $selectedPaperID,
                onAddPapers: presentAddPapers,
                onDropURLs: workflow.prepare,
                onClearRecentHistory: repository.clearRecentHistory,
                onRequestRemoval: requestPaperRemoval,
                onGetInfo: presentPaperInfo,
                onSourceRecoveryAction: performSourceRecoveryAction
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
                },
                onSourceRecoveryAction: { action in
                    if let selectedPaperID {
                        performSourceRecoveryAction(action, selectedPaperID)
                    }
                },
                onCancelSourceRecovery: {
                    selectedPaperID = nil
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let managedCopyReconciliationWarning {
                ManagedCopyReconciliationWarningView(
                    errorMessage: managedCopyReconciliationWarning,
                    isRetrying: isRetryingManagedCopyReconciliation,
                    onRetry: onRetryManagedCopyReconciliation
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label(
                        inspectorPresented ? "Hide Annotations" : "Show Annotations",
                        systemImage: "sidebar.right"
                    )
                    .labelStyle(.iconOnly)
                }
                .help(inspectorPresented ? "Hide Annotations" : "Show Annotations")
                .accessibilityIdentifier("toggle-annotations-button")
                .accessibilityValue(inspectorPresented ? "Shown" : "Hidden")
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
        .fileImporter(
            isPresented: $sourceRecoveryWorkflow.isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                recoverSource(from: url)
            } else {
                sourceRecoveryWorkflow.cancel()
            }
        }
        .task {
            await checkSourceAvailabilityOnce()
        }
        .onChange(of: selectedPaperID) {
            annotationNavigation = nil
            focusedAnnotationID = nil
        }
        .focusedValue(
            \.addPapersCommandAction,
            AddPapersCommandAction {
                presentAddPapers()
            }
        )
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
            AddBatchSummarySheet(workflow: workflow) { paperID in
                selectedPaperID = paperID
            }
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
        .confirmationDialog(
            "Remove from Library?",
            isPresented: Binding(
                get: { paperRemovalRequest != nil },
                set: { if !$0 { paperRemovalRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: paperRemovalRequest
        ) { request in
            Button("Remove “\(request.title)”", role: .destructive) {
                removePaper(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(removalMessage(for: request.storageMode))
        }
    }

    private func presentAddPapers() {
        #if DEBUG
        if let testLibrary = CanopyUITestLibraryConfiguration.current,
           let fixtureURL = testLibrary.materializeAddPapersFixture() {
            workflow.prepare(urls: [fixtureURL])
            return
        }
        #endif
        fileImporterPresented = true
    }

    private func presentPaperInfo(_ paperID: UUID) {
        do {
            try paperInfoWorkflow.present(paperID: paperID, repository: repository)
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func checkSourceAvailabilityOnce() async {
        guard !didCheckSourceAvailability else { return }
        didCheckSourceAvailability = true
        do {
            let requests = try repository.sourceAvailabilityRequests()
            let managedStore = try? ManagedPaperStore.applicationSupport()
            let results = await Task.detached(priority: .utility) {
                PaperSourceAvailabilityChecker().check(requests, managedStore: managedStore)
            }.value
            try repository.applySourceAvailabilityResults(results)
        } catch {
            // A background check must not interrupt the library. Opening or Retry
            // still runs the full source-verification path and surfaces failures.
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

    private func performSourceRecoveryAction(_ action: SourceRecoveryAction, _ paperID: UUID) {
        guard let paper = try? repository.paper(id: paperID) else { return }
        switch action {
        case .retry:
            selectedPaperID = paperID
            readerReloadToken = UUID()
        case .locateSource, .locateOriginal, .restoreLibraryCopy:
            sourceRecoveryWorkflow.begin(for: paper)
        case .addChangedAsSeparate:
            if let url = sourceRecoveryWorkflow.resolveKnownChangedSourceURL(for: paper) {
                workflow.prepare(urls: [url])
            } else {
                fileImporterPresented = true
            }
        case .removeFromLibrary:
            requestPaperRemoval(paperID)
        }
    }

    private func recoverSource(from url: URL) {
        Task { @MainActor in
            do {
                let paperID = try await sourceRecoveryWorkflow.recover(from: url, repository: repository)
                selectedPaperID = paperID
                readerReloadToken = UUID()
            } catch {
                commandErrorMessage = error.localizedDescription
            }
        }
    }

    private func removePaper(_ request: PaperRemovalRequest) {
        do {
            let snapshot = try repository.removePaper(paperID: request.id)
            PaperRemovalUndo.register(
                snapshot: snapshot,
                repository: repository,
                target: paperRemovalUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            if selectedPaperID == request.id {
                selectedPaperID = nil
            }
            paperRemovalRequest = nil
        } catch {
            paperRemovalRequest = nil
            commandErrorMessage = error.localizedDescription
        }
    }

    private func requestPaperRemoval(_ paperID: UUID) {
        guard let paper = try? repository.paper(id: paperID) else { return }
        paperRemovalRequest = PaperRemovalRequest(
            id: paper.id,
            title: paper.title,
            storageMode: paper.storageMode
        )
    }

    private func removalMessage(for storageMode: PaperStorageMode) -> String {
        switch storageMode {
        case .referenced:
            "Canopy will delete this Paper’s highlights, notes, and reading progress. The original Source PDF will remain in its current location. You can undo this action."
        case .managedCopy:
            "Canopy will remove its Source PDF copy along with this Paper’s highlights, notes, and reading progress. You can undo this action."
        }
    }
}

private struct ManagedCopyReconciliationWarningView: View {
    let errorMessage: String
    let isRetrying: Bool
    let onRetry: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Some Library Files Need Recovery")
                    .font(.headline)
                Text("The library is available, but some Canopy-managed PDFs may be unavailable until recovery succeeds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 12)

            if isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Retrying library file recovery")
            }

            Button("Retry", action: onRetry)
                .disabled(isRetrying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.1))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct PaperRemovalRequest {
    let id: UUID
    let title: String
    let storageMode: PaperStorageMode
}
