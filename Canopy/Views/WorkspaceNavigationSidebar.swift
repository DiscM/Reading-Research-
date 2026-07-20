import SwiftUI

struct WorkspaceNavigationSidebar<FooterContent: View>: View {
    @Binding private var selection: WorkspaceNavigationDestination?
    private let counts: WorkspaceNavigationCounts
    private let collections: [WorkspaceCollectionListItem]
    private let onNewCollection: () -> Void
    private let onRenameCollection: (UUID) -> Void
    private let onDeleteCollection: (UUID) -> Void
    private let onAddDocumentsToCollection: ([UUID], UUID) -> Void
    private let onAddSourcePDFsToCollection: ([URL], UUID) -> Void
    private let footer: FooterContent

    init(
        selection: Binding<WorkspaceNavigationDestination?>,
        counts: WorkspaceNavigationCounts,
        collections: [WorkspaceCollectionListItem],
        onNewCollection: @escaping () -> Void,
        onRenameCollection: @escaping (UUID) -> Void,
        onDeleteCollection: @escaping (UUID) -> Void,
        onAddDocumentsToCollection: @escaping ([UUID], UUID) -> Void,
        onAddSourcePDFsToCollection: @escaping ([URL], UUID) -> Void,
        @ViewBuilder footer: () -> FooterContent
    ) {
        _selection = selection
        self.counts = counts
        self.collections = collections
        self.onNewCollection = onNewCollection
        self.onRenameCollection = onRenameCollection
        self.onDeleteCollection = onDeleteCollection
        self.onAddDocumentsToCollection = onAddDocumentsToCollection
        self.onAddSourcePDFsToCollection = onAddSourcePDFsToCollection
        self.footer = footer()
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                navigationRow(
                    title: "All Documents",
                    systemImage: "square.stack",
                    count: counts.allDocuments,
                    destination: .allDocuments
                )
                navigationRow(
                    title: "Recent",
                    systemImage: "clock",
                    count: counts.recent,
                    destination: .recent
                )
                navigationRow(
                    title: "Unfiled",
                    systemImage: "tray",
                    count: counts.unfiled,
                    destination: .unfiled
                )
            }

            Section("Collections") {
                ForEach(collections) { collection in
                    collectionRow(collection)
                }

                Button(action: onNewCollection) {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Creates an organizational Collection without moving any Source PDFs")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Canopy")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
    }

    private func navigationRow(
        title: String,
        systemImage: String,
        count: Int,
        destination: WorkspaceNavigationDestination
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            Text(count, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(destination)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) Documents")
    }

    private func collectionRow(_ collection: WorkspaceCollectionListItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(collection.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(collection.documentCount, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .tag(WorkspaceNavigationDestination.collection(collection.id))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(collection.name)
        .accessibilityValue("\(collection.documentCount) Documents")
        .contextMenu {
            Button("Rename…", systemImage: "pencil") {
                onRenameCollection(collection.id)
            }
            Button("Delete Collection…", systemImage: "trash", role: .destructive) {
                onDeleteCollection(collection.id)
            }
        }
        .dropDestination(for: WorkspaceDocumentDragPayload.self) { payloads, _ in
            let documentIDs = Array(Set(payloads.flatMap(\.documentIDs)))
                .sorted { $0.uuidString < $1.uuidString }
            guard !documentIDs.isEmpty else { return false }
            onAddDocumentsToCollection(documentIDs, collection.id)
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            let sourcePDFs = urls.filter {
                $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame
            }
            guard !sourcePDFs.isEmpty else { return false }
            onAddSourcePDFsToCollection(sourcePDFs, collection.id)
            return true
        }
    }
}

extension WorkspaceNavigationSidebar where FooterContent == EmptyView {
    init(
        selection: Binding<WorkspaceNavigationDestination?>,
        counts: WorkspaceNavigationCounts,
        collections: [WorkspaceCollectionListItem],
        onNewCollection: @escaping () -> Void,
        onRenameCollection: @escaping (UUID) -> Void,
        onDeleteCollection: @escaping (UUID) -> Void,
        onAddDocumentsToCollection: @escaping ([UUID], UUID) -> Void,
        onAddSourcePDFsToCollection: @escaping ([URL], UUID) -> Void
    ) {
        self.init(
            selection: selection,
            counts: counts,
            collections: collections,
            onNewCollection: onNewCollection,
            onRenameCollection: onRenameCollection,
            onDeleteCollection: onDeleteCollection,
            onAddDocumentsToCollection: onAddDocumentsToCollection,
            onAddSourcePDFsToCollection: onAddSourcePDFsToCollection,
            footer: { EmptyView() }
        )
    }
}
