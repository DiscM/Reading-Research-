import CanopyCore
import SwiftUI

struct WorkspaceDocumentListView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let documents: [WorkspaceDocumentListItem]
    let destination: WorkspaceNavigationDestination
    @Binding var selection: Set<UUID>
    @Binding var searchText: String
    @Binding var searchFocusRequest: Bool
    @Binding var selectedKinds: Set<DocumentKind>
    @Binding var sort: WorkspaceDocumentSort
    let onAddDocuments: () -> Void
    let onSearchSubmitted: (String, WorkspaceNavigationDestination) -> Void
    let onSearchAllDocuments: (String) -> Void
    let onGetInfo: (UUID) -> Void
    let onAttentionAction: (UUID, WorkspaceDocumentAttention) -> Void
    let onRequestRemoval: ([UUID]) -> Void
    let searchGroups: [WorkspaceSearchDocumentGroup]
    let searchScopeDescription: String?
    let canExpandSearchToAllDocuments: Bool
    let onActivateSearchHit: (UUID, WorkspaceSearchChildHit) -> Void

    @State private var isSearchPresented = false
    @State private var expandedSearchGroupIDs: Set<UUID> = []

    init(
        title: String,
        documents: [WorkspaceDocumentListItem],
        destination: WorkspaceNavigationDestination,
        selection: Binding<Set<UUID>>,
        searchText: Binding<String>,
        searchFocusRequest: Binding<Bool>,
        selectedKinds: Binding<Set<DocumentKind>>,
        sort: Binding<WorkspaceDocumentSort>,
        onAddDocuments: @escaping () -> Void,
        onSearchSubmitted: @escaping (String, WorkspaceNavigationDestination) -> Void,
        onSearchAllDocuments: @escaping (String) -> Void,
        onGetInfo: @escaping (UUID) -> Void,
        onAttentionAction: @escaping (UUID, WorkspaceDocumentAttention) -> Void,
        onRequestRemoval: @escaping ([UUID]) -> Void,
        searchGroups: [WorkspaceSearchDocumentGroup] = [],
        searchScopeDescription: String? = nil,
        canExpandSearchToAllDocuments: Bool = false,
        onActivateSearchHit: @escaping (UUID, WorkspaceSearchChildHit) -> Void = { _, _ in }
    ) {
        self.title = title
        self.documents = documents
        self.destination = destination
        _selection = selection
        _searchText = searchText
        _searchFocusRequest = searchFocusRequest
        _selectedKinds = selectedKinds
        _sort = sort
        self.onAddDocuments = onAddDocuments
        self.onSearchSubmitted = onSearchSubmitted
        self.onSearchAllDocuments = onSearchAllDocuments
        self.onGetInfo = onGetInfo
        self.onAttentionAction = onAttentionAction
        self.onRequestRemoval = onRequestRemoval
        self.searchGroups = searchGroups
        self.searchScopeDescription = searchScopeDescription
        self.canExpandSearchToAllDocuments = canExpandSearchToAllDocuments
        self.onActivateSearchHit = onActivateSearchHit
    }

    private var visibleDocuments: [WorkspaceDocumentListItem] {
        WorkspaceLibraryProjection(
            documents: documents,
            destination: destination,
            selectedKinds: selectedKinds,
            sort: sort
        ).documents
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            CanopyOpaqueSemanticBackground(
                semanticColor: .textBackgroundColor,
                colorScheme: colorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                header
                Divider()
                documentList
            }
        }
        .frame(minWidth: 240, idealWidth: 320)
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .toolbar,
            prompt: "Search \(title)"
        )
        .onSubmit(of: .search) {
            onSearchSubmitted(normalizedSearchText, destination)
        }
        .onChange(of: searchFocusRequest) { _, requested in
            guard requested else { return }
            isSearchPresented = true
            searchFocusRequest = false
        }
        .onChange(of: visibleDocuments.map(\.id)) { _, _ in
            selection = WorkspaceDocumentSelection.reconciled(
                selection,
                visibleDocuments: visibleDocuments
            )
        }
        .onChange(of: normalizedSearchText) { _, _ in
            expandedSearchGroupIDs.removeAll()
        }
        .onChange(of: searchScopeDescription) { _, _ in
            expandedSearchGroupIDs.removeAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !normalizedSearchText.isEmpty, let searchScopeDescription {
                    Text(searchScopeDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if selection.count > 1 {
                    Text("\(selection.count) selected")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(visibleDocuments.count) Documents")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                kindFilterMenu
                sortMenu
                Spacer(minLength: 4)
                Button(action: onAddDocuments) {
                    Label("Add Documents", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .help("Add Documents")
                .accessibilityIdentifier("add-documents-button")
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var documentList: some View {
        List(selection: $selection) {
            if !normalizedSearchText.isEmpty {
                if searchGroups.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try another term or search All Documents.")
                    )
                } else {
                    ForEach(searchGroups) { group in
                        searchResultGroup(group)
                    }
                }
            } else if visibleDocuments.isEmpty {
                ContentUnavailableView(
                    normalizedSearchText.isEmpty ? "No Documents" : "No Results",
                    systemImage: normalizedSearchText.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(emptyDescription)
                )
            } else {
                ForEach(visibleDocuments) { document in
                    documentRow(document)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            guard !selection.isEmpty else { return }
            onRequestRemoval(selection.sorted { $0.uuidString < $1.uuidString })
        }
        .overlay(alignment: .top) {
            if !normalizedSearchText.isEmpty, canExpandSearchToAllDocuments {
                searchAllDocumentsButton
            }
        }
    }

    @ViewBuilder
    private func searchResultGroup(_ group: WorkspaceSearchDocumentGroup) -> some View {
        if let document = documents.first(where: { $0.id == group.documentID }) {
            Section {
                documentRow(document)
                ForEach(Array(visibleHits(for: group).enumerated()), id: \.offset) { _, hit in
                    Button {
                        selection = [group.documentID]
                        onActivateSearchHit(group.documentID, hit)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: hit.source.systemImage)
                                .frame(width: 16)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(hit.source.displayName)
                                        .font(.caption.weight(.medium))
                                    if let pageNumber = hit.pageNumber {
                                        Text("Page \(pageNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(hit.snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .padding(.leading, 28)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                if group.additionalMatchCount > 0,
                   !expandedSearchGroupIDs.contains(group.id) {
                    Button("Show \(group.additionalMatchCount) More") {
                        expandedSearchGroupIDs.insert(group.id)
                    }
                    .buttonStyle(.link)
                    .padding(.leading, 52)
                }
            }
        }
    }

    private func visibleHits(
        for group: WorkspaceSearchDocumentGroup
    ) -> [WorkspaceSearchChildHit] {
        expandedSearchGroupIDs.contains(group.id)
            ? group.childHits
            : group.initialChildHits
    }

    private var emptyDescription: String {
        if !normalizedSearchText.isEmpty {
            return "Try another term or search All Documents."
        }
        switch destination {
        case .allDocuments:
            return "Add a Source PDF to begin your workspace."
        case .recent:
            return "Documents you open will appear here."
        case .unfiled:
            return "Every Document currently belongs to a Collection."
        case .collection:
            return "Add existing Documents or drop Source PDFs onto this Collection."
        }
    }

    private var searchAllDocumentsButton: some View {
        Button {
            onSearchAllDocuments(normalizedSearchText)
        } label: {
            Label("Search All Documents", systemImage: "square.stack.3d.up")
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .background(.regularMaterial, in: Capsule())
        .padding(8)
        .help("Keep this query and expand its scope to All Documents")
    }

    private func documentRow(_ document: WorkspaceDocumentListItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: document.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .lineLimit(1)
                Text(document.secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if showsCollectionContext, !document.collectionNames.isEmpty {
                    Text(document.collectionNames.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let attention = document.attention {
                Image(systemName: attention.systemImage)
                    .foregroundStyle(attentionColor(attention))
                    .help(attention.label)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .tag(document.id)
        .draggable(dragPayload(for: document.id))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("document-row")
        .accessibilityLabel(document.title)
        .accessibilityValue(accessibilityValue(for: document))
        .accessibilityHint("Select to open this Document; Command-click to select more than one")
        .contextMenu {
            Button("Get Info…", systemImage: "info.circle") {
                onGetInfo(document.id)
            }
            if let attention = document.attention {
                Button(attention.actionTitle, systemImage: attention.systemImage) {
                    onAttentionAction(document.id, attention)
                }
            }
            Divider()
            Button("Remove from Library…", systemImage: "trash", role: .destructive) {
                let removalIDs = selection.contains(document.id) ? selection : [document.id]
                onRequestRemoval(removalIDs.sorted { $0.uuidString < $1.uuidString })
            }
        }
    }

    private var showsCollectionContext: Bool {
        destination == .allDocuments || !normalizedSearchText.isEmpty
    }

    private func dragPayload(for documentID: UUID) -> WorkspaceDocumentDragPayload {
        let documentIDs = selection.contains(documentID) ? Array(selection) : [documentID]
        return WorkspaceDocumentDragPayload(
            documentIDs: documentIDs.sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func accessibilityValue(for document: WorkspaceDocumentListItem) -> String {
        var values = [document.secondaryText]
        if !document.collectionNames.isEmpty {
            values.append("Collections: \(document.collectionNames.joined(separator: ", "))")
        }
        if let attention = document.attention {
            values.append(attention.label)
        }
        return values.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func attentionColor(_ attention: WorkspaceDocumentAttention) -> Color {
        switch attention.severity {
        case .neutral: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }

    private var kindFilterMenu: some View {
        Menu {
            Button {
                selectedKinds.removeAll()
            } label: {
                if selectedKinds.isEmpty {
                    Label("All Kinds", systemImage: "checkmark")
                } else {
                    Text("All Kinds")
                }
            }

            Divider()

            ForEach(DocumentKind.allCases) { kind in
                Toggle(kind.displayName, isOn: kindBinding(kind))
            }
        } label: {
            Label(kindFilterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter by Document Kind")
        .accessibilityLabel("Filter by Document Kind")
        .accessibilityValue(kindFilterLabel)
    }

    private var kindFilterLabel: String {
        switch selectedKinds.count {
        case 0: "Kind: All"
        case 1: "Kind: \(selectedKinds.first!.displayName)"
        default: "Kinds: \(selectedKinds.count)"
        }
    }

    private func kindBinding(_ kind: DocumentKind) -> Binding<Bool> {
        Binding(
            get: { selectedKinds.isEmpty || selectedKinds.contains(kind) },
            set: { isSelected in
                if isSelected {
                    selectedKinds.insert(kind)
                } else if selectedKinds.isEmpty {
                    selectedKinds = Set(DocumentKind.allCases.filter { $0 != kind })
                } else if selectedKinds.count > 1 {
                    selectedKinds.remove(kind)
                }
            }
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sort.field) {
                ForEach(WorkspaceDocumentSortField.allCases) { field in
                    Text(field.displayName).tag(field)
                }
            }

            Divider()

            Picker("Direction", selection: $sort.direction) {
                ForEach(WorkspaceSortDirection.allCases) { direction in
                    Text(direction.displayName(for: sort.field)).tag(direction)
                }
            }
        } label: {
            Label(sort.field.displayName, systemImage: "arrow.up.arrow.down")
        }
        .help("Sort Documents")
        .accessibilityValue(
            "\(sort.field.displayName), \(sort.direction.displayName(for: sort.field))"
        )
    }
}

private extension WorkspaceSearchHitSource {
    var displayName: String {
        switch self {
        case .title: "Title"
        case .collection: "Collection"
        case .creator: "Creator"
        case .documentKind: "Document Kind"
        case .documentDate: "Document Date"
        case .documentNote: "Document Note"
        case .annotationNote: "Annotation Note"
        case .annotationQuotation: "Highlighted Text"
        case .pdfBody: "PDF Text"
        }
    }

    var systemImage: String {
        switch self {
        case .title: "textformat"
        case .collection: "folder"
        case .creator: "person"
        case .documentKind: "square.grid.2x2"
        case .documentDate: "calendar"
        case .documentNote: "note.text"
        case .annotationNote: "highlighter"
        case .annotationQuotation: "quote.opening"
        case .pdfBody: "doc.text.magnifyingglass"
        }
    }
}
