import AppKit
import CanopyCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum WorkspaceLayoutMetrics {
    static let navigationWidth: CGFloat = 220
    static let documentListWidth: CGFloat = 320
    static let inspectorWidth: CGFloat = 320
    static let readerMinimumWidth: CGFloat = 540
    static let dividerWidth: CGFloat = 1

    static func minimumWindowWidth(
        navigationPresented: Bool,
        documentListPresented: Bool,
        inspectorPresented: Bool
    ) -> CGFloat {
        let visibleOptionalPaneCount = [
            navigationPresented,
            documentListPresented,
            inspectorPresented
        ].filter { $0 }.count
        let optionalPaneWidth = (navigationPresented ? navigationWidth : 0)
            + (documentListPresented ? documentListWidth : 0)
            + (inspectorPresented ? inspectorWidth : 0)
        let totalDividerWidth = CGFloat(visibleOptionalPaneCount) * Self.dividerWidth
        return max(900, readerMinimumWidth + optionalPaneWidth + totalDividerWidth)
    }
}

struct ContentView: View {
    let managedCopyReconciliationWarning: String?
    let isRetryingManagedCopyReconciliation: Bool
    let onRetryManagedCopyReconciliation: @MainActor () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Document.title) private var documents: [Document]
    @Query(sort: \Collection.name) private var collections: [Collection]
    @AppStorage("workspace.navigationPresented") private var navigationPresented = true
    @AppStorage("workspace.documentListPresented") private var documentListPresented = true
    @AppStorage("workspace.inspectorPresented") private var inspectorPresented = true
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var navigationDestination: WorkspaceNavigationDestination? = .allDocuments
    @State private var selectedKinds: Set<DocumentKind> = []
    @State private var documentSort = WorkspaceDocumentSort(
        field: .title,
        direction: .ascending
    )
    @State private var workspaceSearchText = ""
    @State private var workspaceSearchFocusRequest = false
    @State private var workspaceSearchGroups: [WorkspaceSearchDocumentGroup] = []
    @State private var selectionSearchDocumentIDs: Set<UUID>?
    @State private var inspectorTab = WorkspaceInspectorTab.launchDefault
    @State private var pageNavigation: PDFPageNavigation?
    @State private var indexCoordinator: WorkspaceIndexCoordinator
    @State private var annotationNavigation: AnnotationNavigation?
    @State private var focusedAnnotationID: UUID?
    @State private var annotationAdjustmentRequest: AnnotationAdjustmentRequest?
    @State private var annotationUndoTarget = AnnotationUndoTarget()
    @State private var annotationSession = AnnotationSession()
    @State private var readerReloadToken = UUID()
    @State private var fileImporterPresented = false
    @State private var workflow = AddDocumentsWorkflow()
    @State private var paperInfoWorkflow = PaperInfoWorkflow()
    @State private var paperStorageConversionWorkflow = PaperStorageConversionWorkflow()
    @State private var paperInfoUndoTarget = PaperInfoUndoTarget()
    @State private var paperRemovalUndoTarget = PaperRemovalUndoTarget()
    @State private var workspaceUndoTarget = WorkspaceUndoTarget()
    @State private var sourceRecoveryWorkflow = SourceRecoveryWorkflow()
    @State private var didCheckSourceAvailability = false
    @State private var paperRemovalRequest: PaperRemovalRequest?
    @State private var bulkRemovalRequest: WorkspaceRemovalRequest?
    @State private var collectionEditorMode: CollectionEditorMode?
    @State private var collectionNameDraft = ""
    @State private var collectionDeletionRequest: WorkspaceCollectionListItem?
    @State private var newCollectionDocumentIDs: [UUID] = []
    @State private var commandErrorMessage: String?

    private var repository: LibraryRepository { LibraryRepository(context: modelContext) }
    private var selectedPaper: Paper? {
        guard selectedDocumentIDs.count == 1,
              let selectedDocumentID = selectedDocumentIDs.first else { return nil }
        return try? repository.paper(id: selectedDocumentID)
    }

    init(
        managedCopyReconciliationWarning: String? = nil,
        isRetryingManagedCopyReconciliation: Bool = false,
        indexDatabaseURL: URL = CanopyModelContainer.defaultStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("PDFTextIndex.sqlite"),
        onRetryManagedCopyReconciliation: @escaping @MainActor () -> Void = {}
    ) {
        self.managedCopyReconciliationWarning = managedCopyReconciliationWarning
        self.isRetryingManagedCopyReconciliation = isRetryingManagedCopyReconciliation
        self.onRetryManagedCopyReconciliation = onRetryManagedCopyReconciliation
        _indexCoordinator = State(
            initialValue: WorkspaceIndexCoordinator(databaseURL: indexDatabaseURL)
        )
    }

    var body: some View {
        workspaceDialogs
            .fileImporter(
                isPresented: $fileImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                if case let .success(urls) = result {
                    workflow.prepare(urls: urls)
                }
            }
    }

    private var workspaceChrome: some View {
        AnyView(workspaceShell)
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
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigationPresented.toggle()
                } label: {
                    Label("Show or Hide Navigation", systemImage: "sidebar.left")
                        .labelStyle(.iconOnly)
                }
                .help("Show or Hide Navigation")

                Button {
                    documentListPresented.toggle()
                } label: {
                    Label("Show or Hide Document List", systemImage: "list.bullet.rectangle")
                        .labelStyle(.iconOnly)
                }
                .help("Show or Hide Document List")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label(
                        inspectorPresented ? "Hide Inspector" : "Show Inspector",
                        systemImage: "sidebar.right"
                    )
                    .labelStyle(.iconOnly)
                }
                .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
                .accessibilityIdentifier("toggle-annotations-button")
                .accessibilityValue(inspectorPresented ? "Shown" : "Hidden")
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
            indexCoordinator.schedule(repository: repository)
        }
        .task(id: indexScheduleID) {
            indexCoordinator.schedule(repository: repository)
        }
        .task(id: workspaceSearchTaskID) {
            await updateWorkspaceSearch()
        }
        .onChange(of: selectedDocumentIDs) {
            annotationNavigation = nil
            pageNavigation = nil
            focusedAnnotationID = nil
            annotationAdjustmentRequest = nil
        }
        .onChange(of: collections.map(\.id)) {
            guard case let .collection(collectionID) = navigationDestination,
                  !collections.contains(where: { $0.id == collectionID }) else { return }
            navigationDestination = .allDocuments
        }
        .focusedValue(
            \.addDocumentsCommandAction,
            AddDocumentsCommandAction {
                presentAddDocuments()
            }
        )
        .focusedValue(
            \.documentInfoCommandAction,
            selectedPaper.map { paper in
                DocumentInfoCommandAction {
                    presentPaperInfo(paper.id)
                }
            }
        )
        .focusedValue(
            \.workspaceCommandContext,
            WorkspaceCommandContext(perform: performWorkspaceCommand)
        )
    }

    private var workspaceSheets: some View {
        AnyView(workspaceChrome)
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
                selectedDocumentIDs = [paperID]
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
                storageConversionWorkflow: paperStorageConversionWorkflow,
                onReparse: {
                    Task { @MainActor in
                        await paperInfoWorkflow.reparse(repository: repository)
                    }
                },
                onChangeStorage: changePaperStorage,
                onSave: savePaperInfo
            )
        }
    }

    private var workspaceDialogs: some View {
        AnyView(workspaceSheets)
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
        .confirmationDialog(
            "Remove Selected Documents?",
            isPresented: Binding(
                get: { bulkRemovalRequest != nil },
                set: { if !$0 { bulkRemovalRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: bulkRemovalRequest
        ) { request in
            Button("Remove \(request.documentIDs.count) Documents", role: .destructive) {
                removeDocuments(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(request.confirmationMessage)
        }
        .alert(
            collectionEditorTitle,
            isPresented: Binding(
                get: { collectionEditorMode != nil },
                set: { if !$0 { resetCollectionEditor() } }
            )
        ) {
            TextField("Collection Name", text: $collectionNameDraft)
            Button(collectionEditorActionTitle) {
                saveCollectionEditor()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                resetCollectionEditor()
            }
        } message: {
            Text("Collections organize references to Documents without moving or copying their Source PDFs.")
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: Binding(
                get: { collectionDeletionRequest != nil },
                set: { if !$0 { collectionDeletionRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: collectionDeletionRequest
        ) { collection in
            Button("Delete “\(collection.name)”", role: .destructive) {
                deleteCollection(collection)
            }
            Button("Cancel", role: .cancel) {}
        } message: { collection in
            Text("The Collection will be removed. Its \(collection.documentCount) Documents and their Source PDFs will remain in the library.")
        }
    }

    private var workspaceShell: some View {
        HStack(spacing: 0) {
            if navigationPresented {
                navigationSidebar
                    .frame(width: WorkspaceLayoutMetrics.navigationWidth)
                    .clipped()
                workspaceDivider
            }

            if documentListPresented {
                documentList
                    .frame(width: WorkspaceLayoutMetrics.documentListWidth)
                    .clipped()
                workspaceDivider
            }

            readerCanvas
                .frame(
                    minWidth: WorkspaceLayoutMetrics.readerMinimumWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .layoutPriority(1)

            if inspectorPresented {
                workspaceDivider
                workspaceInspector
                    .frame(width: WorkspaceLayoutMetrics.inspectorWidth)
                    .background(.background)
                    .clipped()
                    .accessibilityIdentifier("workspace-inspector")
            }
        }
        .animation(nil, value: navigationPresented)
        .animation(nil, value: documentListPresented)
        .animation(nil, value: inspectorPresented)
        .frame(minWidth: workspaceMinimumWidth)
    }

    private var workspaceDivider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: WorkspaceLayoutMetrics.dividerWidth)
            .accessibilityHidden(true)
    }

    /// Keeps every explicitly presented pane usable while allowing a compact
    /// reader window as optional panes are collapsed.
    private var workspaceMinimumWidth: CGFloat {
        WorkspaceLayoutMetrics.minimumWindowWidth(
            navigationPresented: navigationPresented,
            documentListPresented: documentListPresented,
            inspectorPresented: inspectorPresented
        )
    }

    private var navigationSidebar: some View {
        WorkspaceNavigationSidebar(
            selection: $navigationDestination,
            counts: WorkspaceNavigationCounts(documents: workspaceDocumentItems),
            collections: workspaceCollections,
            onNewCollection: { presentCollectionEditor(for: nil) },
            onRenameCollection: { collectionID in
                presentCollectionEditor(for: collectionID)
            },
            onDeleteCollection: presentCollectionDeletion,
            onAddDocumentsToCollection: { documentIDs, collectionID in
                setDocuments(documentIDs, inCollection: collectionID, add: true)
            },
            onAddSourcePDFsToCollection: { urls, collectionID in
                workflow.prepare(urls: urls, destinationCollectionID: collectionID)
            }
        ) {
            WorkspaceIndexFooterView(
                coordinator: indexCoordinator,
                documents: documents,
                onRetry: { fingerprint in
                    indexCoordinator.retry(fingerprint: fingerprint, repository: repository)
                },
                onLocateSource: { documentID in
                    performSourceRecoveryAction(.locateSource, documentID)
                }
            )
        }
        .accessibilityIdentifier("workspace-navigation-sidebar")
    }

    private var documentList: some View {
        WorkspaceDocumentListView(
            title: documentListTitle,
            documents: workspaceDocumentItems,
            destination: activeNavigationDestination,
            selection: $selectedDocumentIDs,
            searchText: $workspaceSearchText,
            searchFocusRequest: $workspaceSearchFocusRequest,
            selectedKinds: $selectedKinds,
            sort: $documentSort,
            onAddDocuments: presentAddDocuments,
            onSearchSubmitted: { _, _ in },
            onSearchAllDocuments: { query in
                selectionSearchDocumentIDs = nil
                workspaceSearchText = query
                navigationDestination = .allDocuments
            },
            onGetInfo: presentPaperInfo,
            onAttentionAction: performAttentionAction,
            onRequestRemoval: requestDocumentRemoval,
            searchGroups: workspaceSearchGroups,
            searchScopeDescription: workspaceSearchScopeDescription,
            canExpandSearchToAllDocuments: selectionSearchDocumentIDs != nil
                || activeNavigationDestination != .allDocuments,
            onActivateSearchHit: activateSearchHit
        )
        .accessibilityIdentifier("workspace-document-list")
    }

    @ViewBuilder
    private var readerCanvas: some View {
        if selectedDocumentIDs.count > 1 {
            WorkspaceMultiSelectionSummaryView(
                documents: selectedWorkspaceDocumentItems,
                collections: workspaceCollections,
                onSetKind: setDocumentKind,
                onSetCollectionMembership: setDocuments(_:inCollection:add:),
                onCreateCollectionFromSelection: presentCollectionEditorForSelection,
                onRequestRemoval: requestDocumentRemoval
            )
        } else {
            PDFReaderView(
                paper: selectedPaper,
                repository: repository,
                inspectorPresented: $inspectorPresented,
                annotationNavigation: annotationNavigation,
                pageNavigation: pageNavigation,
                focusedAnnotationID: $focusedAnnotationID,
                annotationAdjustmentRequest: $annotationAdjustmentRequest,
                annotationUndoTarget: annotationUndoTarget,
                annotationSession: annotationSession,
                reloadToken: $readerReloadToken,
                onGetInfo: {
                    if let selectedPaper { presentPaperInfo(selectedPaper.id) }
                },
                onShowAnnotations: {
                    inspectorTab = .annotations
                },
                onSourceRecoveryAction: { action in
                    if let selectedPaper {
                        performSourceRecoveryAction(action, selectedPaper.id)
                    }
                },
                onCancelSourceRecovery: {
                    selectedDocumentIDs.removeAll()
                }
            )
        }
    }

    private var workspaceInspector: some View {
        WorkspaceInspectorContainer(selection: $inspectorTab) {
            overviewInspectorContent
        } annotations: {
            AnnotationInspectorView(
                paper: selectedPaper,
                repository: repository,
                focusedAnnotationID: $focusedAnnotationID,
                adjustingAnnotationID: annotationAdjustmentRequest?.annotationID,
                annotationUndoTarget: annotationUndoTarget,
                annotationSession: annotationSession,
                onRetrySource: { readerReloadToken = UUID() },
                onNavigate: { annotationID in
                    annotationNavigation = AnnotationNavigation(annotationID: annotationID)
                },
                onAdjust: { annotationID in
                    guard annotationAdjustmentRequest == nil else { return }
                    annotationNavigation = AnnotationNavigation(annotationID: annotationID)
                    annotationAdjustmentRequest = AnnotationAdjustmentRequest(
                        annotationID: annotationID
                    )
                }
            )
        }
    }

    @ViewBuilder
    private var overviewInspectorContent: some View {
        if selectedDocumentIDs.count > 1 {
            WorkspaceMultiSelectionInspectorView(
                documents: selectedWorkspaceDocumentItems,
                collections: workspaceCollections,
                onSetKind: setDocumentKind,
                onSetCollectionMembership: setDocuments(_:inCollection:add:),
                onNewCollection: presentCollectionEditorForSelection
            )
        } else if let selectedPaper {
            WorkspaceOverviewInspectorView(
                model: WorkspaceDocumentOverviewModel(
                    document: selectedPaper,
                    availableCollections: collections,
                    indexStatus: indexCoordinator.status(for: selectedPaper.fingerprint)
                ),
                onDocumentNoteChange: updateDocumentNote,
                onKindChange: { documentID, kind in
                    setDocumentKind([documentID], kind)
                },
                onDocumentDateChange: updateDocumentDate,
                onSetCollectionMembership: { documentID, collectionID, add in
                    setDocuments([documentID], inCollection: collectionID, add: add)
                },
                onNewCollection: {
                    presentCollectionEditorForSelection([selectedPaper.id])
                },
                onSourceStatusAction: performPrimarySourceAction,
                onIndexStatusAction: performIndexStatusAction
            )
        } else {
            ContentUnavailableView(
                "No Document Selected",
                systemImage: "sidebar.right",
                description: Text("Select a Document to edit its Overview or annotations.")
            )
        }
    }

    private var workspaceDocumentItems: [WorkspaceDocumentListItem] {
        documents.map { document in
            WorkspaceDocumentListItem(
                document: document,
                indexStatus: indexCoordinator.status(for: document.fingerprint)
            )
        }
    }

    private var navigationScopedDocumentItems: [WorkspaceDocumentListItem] {
        WorkspaceLibraryProjection(
            documents: workspaceDocumentItems,
            destination: activeNavigationDestination,
            selectedKinds: selectedKinds,
            sort: documentSort
        ).documents
    }

    private var workspaceSearchDocumentIDs: Set<UUID> {
        selectionSearchDocumentIDs ?? Set(navigationScopedDocumentItems.map(\.id))
    }

    private var workspaceSearchScopeDescription: String? {
        guard !workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if let selectionSearchDocumentIDs {
            return "\(selectionSearchDocumentIDs.count)-Document Selection"
        }
        return documentListTitle
    }

    private var selectedWorkspaceDocumentItems: [WorkspaceDocumentListItem] {
        workspaceDocumentItems.filter { selectedDocumentIDs.contains($0.id) }
    }

    private var workspaceCollections: [WorkspaceCollectionListItem] {
        collections.map(WorkspaceCollectionListItem.init(collection:))
    }

    private var activeNavigationDestination: WorkspaceNavigationDestination {
        navigationDestination ?? .allDocuments
    }

    private var documentListTitle: String {
        switch activeNavigationDestination {
        case .allDocuments: "All Documents"
        case .recent: "Recent"
        case .unfiled: "Unfiled"
        case let .collection(collectionID):
            collections.first(where: { $0.id == collectionID })?.name ?? "Collection"
        }
    }

    private var indexScheduleID: String {
        documents.map {
            "\($0.id.uuidString):\($0.sourceState.rawValue):\($0.pageCount)"
        }.sorted().joined(separator: "|")
    }

    private var workspaceSearchTaskID: String {
        let scope = workspaceSearchDocumentIDs.map(\.uuidString).sorted().joined(separator: ",")
        let indexState = indexCoordinator.statuses.map {
            "\($0.lifecycle.rawValue):\($0.indexedPageCount)"
        }.joined(separator: ",")
        return [
            workspaceSearchText,
            scope,
            indexState,
            String(workspaceSearchContentRevision)
        ].joined(separator: "|")
    }

    private var workspaceSearchContentRevision: Int {
        var hasher = Hasher()
        let snapshots = documents.map(WorkspaceSearchDocument.init(document:)).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        for document in snapshots {
            hasher.combine(document.id)
            hasher.combine(document.title)
            hasher.combine(document.kind.rawValue)
            hasher.combine(document.documentDate?.year)
            hasher.combine(document.documentDate?.month)
            hasher.combine(document.documentDate?.day)
            hasher.combine(document.documentNote)
            document.collectionNames.forEach { hasher.combine($0) }
            document.creatorNames.forEach { hasher.combine($0) }
            for annotation in document.annotations {
                hasher.combine(annotation.id)
                hasher.combine(annotation.pageIndex)
                hasher.combine(annotation.note)
                hasher.combine(annotation.selectedQuotation)
            }
        }
        return hasher.finalize()
    }

    private func performWorkspaceCommand(_ command: WorkspaceCommand) {
        switch command {
        case .toggleNavigationSidebar:
            navigationPresented.toggle()
        case .toggleDocumentList:
            documentListPresented.toggle()
        case .toggleInspector:
            inspectorPresented.toggle()
        case .showOverview:
            inspectorPresented = true
            inspectorTab = .overview
        case .showAnnotations:
            inspectorPresented = true
            inspectorTab = .annotations
        case .focusSearch:
            selectionSearchDocumentIDs = nil
            documentListPresented = true
            workspaceSearchFocusRequest = true
        case .focusContextualSearch:
            selectionSearchDocumentIDs = selectedDocumentIDs.count > 1
                ? selectedDocumentIDs
                : nil
            documentListPresented = true
            workspaceSearchFocusRequest = true
        }
    }

    private func updateWorkspaceSearch() async {
        let query = workspaceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            workspaceSearchGroups = []
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(180))
            try Task.checkCancellation()
        } catch {
            return
        }
        let scopeIDs = workspaceSearchDocumentIDs
        let scopedDocuments = documents.filter { scopeIDs.contains($0.id) }
        let fingerprints = scopedDocuments.map(\.fingerprint)
        let bodyHits = await indexCoordinator.search(query, fingerprints: fingerprints)
        guard !Task.isCancelled else { return }
        workspaceSearchGroups = WorkspaceSearchEngine.search(
            query: query,
            documents: documents.map(WorkspaceSearchDocument.init(document:)),
            pdfTextHits: bodyHits,
            scope: WorkspaceSearchScope(allowedDocumentIDs: scopeIDs)
        )
    }

    private func activateSearchHit(
        _ documentID: UUID,
        _ hit: WorkspaceSearchChildHit
    ) {
        selectedDocumentIDs = [documentID]
        Task { @MainActor in
            await Task.yield()
            if let annotationID = hit.annotationID {
                inspectorPresented = true
                inspectorTab = .annotations
                annotationNavigation = AnnotationNavigation(annotationID: annotationID)
            } else if let pageIndex = hit.pageIndex {
                pageNavigation = PDFPageNavigation(pageIndex: pageIndex)
            }
        }
    }

    private func setDocumentKind(_ documentIDs: [UUID], _ kind: DocumentKind) {
        do {
            let previousKinds = try documentKinds(for: documentIDs)
            try repository.setDocumentKind(kind, for: documentIDs)
            let currentKinds = try documentKinds(for: documentIDs)
            guard previousKinds != currentKinds else { return }
            WorkspaceUndo.register(
                previous: .documentKinds(previousKinds),
                current: .documentKinds(currentKinds),
                actionName: documentIDs.count == 1 ? "Change Document Kind" : "Change Document Kinds",
                repository: repository,
                target: workspaceUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func setDocuments(
        _ documentIDs: [UUID],
        inCollection collectionID: UUID,
        add: Bool
    ) {
        do {
            let uniqueDocumentIDs = Array(Set(documentIDs)).sorted {
                $0.uuidString < $1.uuidString
            }
            let previousMemberIDs = try collectionMemberDocumentIDs(
                collectionID: collectionID,
                among: uniqueDocumentIDs
            )
            if add {
                try repository.addDocuments(uniqueDocumentIDs, toCollection: collectionID)
            } else {
                try repository.removeDocuments(uniqueDocumentIDs, fromCollection: collectionID)
            }
            let currentMemberIDs = try collectionMemberDocumentIDs(
                collectionID: collectionID,
                among: uniqueDocumentIDs
            )
            guard previousMemberIDs != currentMemberIDs else { return }
            WorkspaceUndo.register(
                previous: .collectionMembership(
                    collectionID: collectionID,
                    documentIDs: uniqueDocumentIDs,
                    memberDocumentIDs: previousMemberIDs
                ),
                current: .collectionMembership(
                    collectionID: collectionID,
                    documentIDs: uniqueDocumentIDs,
                    memberDocumentIDs: currentMemberIDs
                ),
                actionName: add ? "Add to Collection" : "Remove from Collection",
                repository: repository,
                target: workspaceUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func updateDocumentNote(_ documentID: UUID, _ note: String) -> Bool {
        do {
            guard let document = try repository.document(id: documentID) else {
                throw LibraryRepositoryError.documentNotFound
            }
            let previousNote = document.documentNote
            guard previousNote != note else { return true }
            try repository.updateDocumentNote(documentID: documentID, note: note)
            WorkspaceUndo.register(
                previous: .documentNote(documentID: documentID, note: previousNote),
                current: .documentNote(documentID: documentID, note: note),
                actionName: "Edit Document Note",
                repository: repository,
                target: workspaceUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            return true
        } catch {
            commandErrorMessage = error.localizedDescription
            return false
        }
    }

    private func updateDocumentDate(_ documentID: UUID, _ date: DocumentDate?) {
        do {
            guard let document = try repository.document(id: documentID) else {
                throw LibraryRepositoryError.documentNotFound
            }
            let previousDate = document.documentDate
            let previousProvenance = document.documentDateProvenance
            guard previousDate != date else { return }
            try repository.updateDocumentDate(documentID: documentID, date: date)
            WorkspaceUndo.register(
                previous: .documentDate(
                    documentID: documentID,
                    date: previousDate,
                    provenance: previousProvenance
                ),
                current: .documentDate(
                    documentID: documentID,
                    date: date,
                    provenance: date == nil ? nil : .userEntry
                ),
                actionName: "Edit Document Date",
                repository: repository,
                target: workspaceUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func documentKinds(for documentIDs: [UUID]) throws -> [UUID: DocumentKind] {
        try Dictionary(uniqueKeysWithValues: Set(documentIDs).map { documentID in
            guard let document = try repository.document(id: documentID) else {
                throw LibraryRepositoryError.documentNotFound
            }
            return (documentID, document.kind)
        })
    }

    private func collectionMemberDocumentIDs(
        collectionID: UUID,
        among documentIDs: [UUID]
    ) throws -> Set<UUID> {
        var result: Set<UUID> = []
        for documentID in documentIDs {
            guard let document = try repository.document(id: documentID) else {
                throw LibraryRepositoryError.documentNotFound
            }
            if document.collections.contains(where: { $0.id == collectionID }) {
                result.insert(documentID)
            }
        }
        return result
    }

    private func performAttentionAction(
        _ documentID: UUID,
        _ attention: WorkspaceDocumentAttention
    ) {
        switch attention {
        case .sourceUnavailable, .indexNeedsSource:
            performSourceRecoveryAction(.locateSource, documentID)
        case .brokenReference:
            performSourceRecoveryAction(.locateSource, documentID)
        case .sourceChanged:
            performSourceRecoveryAction(.locateOriginal, documentID)
        case .libraryCopyMissing:
            performSourceRecoveryAction(.restoreLibraryCopy, documentID)
        case .indexFailed:
            guard let document = try? repository.document(id: documentID) else { return }
            indexCoordinator.retry(fingerprint: document.fingerprint, repository: repository)
        }
    }

    private func performPrimarySourceAction(_ documentID: UUID) {
        guard let document = try? repository.document(id: documentID) else { return }
        switch document.sourceState {
        case .available:
            readerReloadToken = UUID()
        case .sourceUnavailable:
            performSourceRecoveryAction(.locateSource, documentID)
        case .brokenReference:
            performSourceRecoveryAction(.locateSource, documentID)
        case .sourceChanged:
            performSourceRecoveryAction(.locateOriginal, documentID)
        case .libraryCopyMissing:
            performSourceRecoveryAction(.restoreLibraryCopy, documentID)
        }
    }

    private func performIndexStatusAction(_ documentID: UUID) {
        guard let document = try? repository.document(id: documentID),
              let status = indexCoordinator.status(for: document.fingerprint) else { return }
        switch status.lifecycle {
        case .failed:
            indexCoordinator.retry(fingerprint: document.fingerprint, repository: repository)
        case .needsSource:
            performPrimarySourceAction(documentID)
        case .pending, .indexing, .ready:
            break
        }
    }

    private func presentCollectionEditor(for collectionID: UUID?) {
        newCollectionDocumentIDs = []
        if let collectionID,
           let collection = collections.first(where: { $0.id == collectionID }) {
            collectionNameDraft = collection.name
            collectionEditorMode = .rename(collectionID)
        } else {
            collectionNameDraft = ""
            collectionEditorMode = .create
        }
    }

    private func presentCollectionEditorForSelection(_ documentIDs: [UUID]) {
        newCollectionDocumentIDs = documentIDs
        collectionNameDraft = ""
        collectionEditorMode = .create
    }

    private func presentCollectionDeletion(_ collectionID: UUID) {
        collectionDeletionRequest = workspaceCollections.first { $0.id == collectionID }
    }

    private var collectionEditorTitle: String {
        switch collectionEditorMode {
        case .rename: "Rename Collection"
        case .create, nil: "New Collection"
        }
    }

    private var collectionEditorActionTitle: String {
        if case .rename = collectionEditorMode { return "Rename" }
        return "Create"
    }

    private func saveCollectionEditor() {
        do {
            switch collectionEditorMode {
            case .create:
                let collection = try repository.createCollection(
                    name: collectionNameDraft,
                    documentIDs: newCollectionDocumentIDs
                )
                let snapshot = try repository.collectionSnapshot(id: collection.id)
                WorkspaceUndo.register(
                    previous: .collectionPresence(collectionID: collection.id, snapshot: nil),
                    current: .collectionPresence(collectionID: collection.id, snapshot: snapshot),
                    actionName: "Create Collection",
                    repository: repository,
                    target: workspaceUndoTarget,
                    undoManager: undoManager,
                    onError: { commandErrorMessage = $0.localizedDescription }
                )
                navigationDestination = .collection(collection.id)
            case let .rename(collectionID):
                guard let collection = try repository.collection(id: collectionID) else {
                    throw LibraryRepositoryError.collectionNotFound
                }
                let previousName = collection.name
                try repository.renameCollection(id: collectionID, name: collectionNameDraft)
                let currentName = try repository.collection(id: collectionID)?.name ?? collectionNameDraft
                if previousName != currentName {
                    WorkspaceUndo.register(
                        previous: .collectionName(collectionID: collectionID, name: previousName),
                        current: .collectionName(collectionID: collectionID, name: currentName),
                        actionName: "Rename Collection",
                        repository: repository,
                        target: workspaceUndoTarget,
                        undoManager: undoManager,
                        onError: { commandErrorMessage = $0.localizedDescription }
                    )
                }
            case nil:
                break
            }
            resetCollectionEditor()
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func resetCollectionEditor() {
        collectionEditorMode = nil
        collectionNameDraft = ""
        newCollectionDocumentIDs = []
    }

    private func deleteCollection(_ collection: WorkspaceCollectionListItem) {
        do {
            let snapshot = try repository.collectionSnapshot(id: collection.id)
            try repository.deleteCollection(id: collection.id)
            WorkspaceUndo.register(
                previous: .collectionPresence(collectionID: collection.id, snapshot: snapshot),
                current: .collectionPresence(collectionID: collection.id, snapshot: nil),
                actionName: "Delete Collection",
                repository: repository,
                target: workspaceUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            if navigationDestination == .collection(collection.id) {
                navigationDestination = .allDocuments
            }
            collectionDeletionRequest = nil
        } catch {
            collectionDeletionRequest = nil
            commandErrorMessage = error.localizedDescription
        }
    }

    private func requestDocumentRemoval(_ documentIDs: [UUID]) {
        let selectedDocuments = documents.filter { documentIDs.contains($0.id) }
        guard !selectedDocuments.isEmpty else { return }
        if selectedDocuments.count == 1, let document = selectedDocuments.first {
            requestPaperRemoval(document.id)
            return
        }
        bulkRemovalRequest = WorkspaceRemovalRequest(documents: selectedDocuments)
    }

    private func removeDocuments(_ request: WorkspaceRemovalRequest) {
        let fingerprints = fingerprintsLosingFinalDocument(removing: request.documentIDs)
        bulkRemovalRequest = nil
        do {
            let snapshots = try repository.removeDocuments(documentIDs: request.documentIDs)
            PaperRemovalUndo.register(
                snapshots: snapshots,
                repository: repository,
                target: paperRemovalUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            selectedDocumentIDs.subtract(request.documentIDs)
            Task { @MainActor in
                await indexCoordinator.enqueueDeletions(fingerprints)
                indexCoordinator.schedule(repository: repository)
            }
        } catch {
            commandErrorMessage = error.localizedDescription
        }
    }

    private func fingerprintsLosingFinalDocument(removing documentIDs: [UUID]) -> Set<Data> {
        let removedIDs = Set(documentIDs)
        let candidateFingerprints = Set(
            documents.filter { removedIDs.contains($0.id) }.map(\.fingerprint)
        )
        return Set(candidateFingerprints.filter { fingerprint in
            !documents.contains {
                $0.fingerprint == fingerprint && !removedIDs.contains($0.id)
            }
        })
    }

    private func presentAddDocuments() {
        #if DEBUG
        if let testLibrary = CanopyUITestLibraryConfiguration.current,
           let fixtureURL = testLibrary.materializeAddDocumentsFixture() {
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

    private func changePaperStorage(to mode: PaperStorageMode) {
        guard let paperID = paperInfoWorkflow.paperID,
              let paper = try? repository.paper(id: paperID) else { return }
        switch mode {
        case .managedCopy:
            Task { @MainActor in
                if await paperStorageConversionWorkflow.convertToManagedCopy(
                    paperID: paperID,
                    repository: repository
                ) {
                    paperInfoWorkflow.refreshReadOnlyDetails(repository: repository)
                    readerReloadToken = UUID()
                }
            }
        case .referenced:
            let panel = NSSavePanel()
            panel.title = "Choose Source PDF Location"
            panel.prompt = "Use Location"
            panel.allowedContentTypes = [.pdf]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = paper.sourceFilename
            guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
            Task { @MainActor in
                if await paperStorageConversionWorkflow.convertToReferenced(
                    paperID: paperID,
                    destinationURL: destinationURL,
                    repository: repository
                ) {
                    paperInfoWorkflow.refreshReadOnlyDetails(repository: repository)
                    readerReloadToken = UUID()
                }
            }
        }
    }

    private func performSourceRecoveryAction(_ action: SourceRecoveryAction, _ paperID: UUID) {
        guard let paper = try? repository.paper(id: paperID) else { return }
        switch action {
        case .retry:
            selectedDocumentIDs = [paperID]
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
                selectedDocumentIDs = [paperID]
                readerReloadToken = UUID()
            } catch {
                commandErrorMessage = error.localizedDescription
            }
        }
    }

    private func removePaper(_ request: PaperRemovalRequest) {
        let fingerprints = fingerprintsLosingFinalDocument(removing: [request.id])
        paperRemovalRequest = nil
        do {
            let snapshot = try repository.removePaper(paperID: request.id)
            PaperRemovalUndo.register(
                snapshot: snapshot,
                repository: repository,
                target: paperRemovalUndoTarget,
                undoManager: undoManager,
                onError: { commandErrorMessage = $0.localizedDescription }
            )
            selectedDocumentIDs.remove(request.id)
            Task { @MainActor in
                await indexCoordinator.enqueueDeletions(fingerprints)
                indexCoordinator.schedule(repository: repository)
            }
        } catch {
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
            "Canopy will delete this Document’s highlights, notes, and reading progress. The original Source PDF will remain in its current location. You can undo this action."
        case .managedCopy:
            "Canopy will remove its Source PDF copy along with this Document’s highlights, notes, and reading progress. You can undo this action."
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

private enum CollectionEditorMode {
    case create
    case rename(UUID)
}

private struct WorkspaceRemovalRequest {
    let documentIDs: [UUID]
    let referencedCount: Int
    let managedCopyCount: Int

    init(documents: [Document]) {
        documentIDs = documents.map(\.id).sorted { $0.uuidString < $1.uuidString }
        referencedCount = documents.count { $0.storageMode == .referenced }
        managedCopyCount = documents.count { $0.storageMode == .managedCopy }
    }

    var confirmationMessage: String {
        var consequences: [String] = []
        if referencedCount > 0 {
            consequences.append(
                "\(referencedCount) referenced Source PDF\(referencedCount == 1 ? "" : "s") will remain in place"
            )
        }
        if managedCopyCount > 0 {
            consequences.append(
                "\(managedCopyCount) Canopy-managed Source PDF \(managedCopyCount == 1 ? "copy" : "copies") will be removed"
            )
        }
        return consequences.joined(separator: "; ")
            + ". Highlights, notes, and reading progress will be removed. You can undo this action."
    }
}
