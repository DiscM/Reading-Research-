import CanopyCore
import SwiftData
import SwiftUI

struct LibrarySidebarView: View {
    @Binding var selection: UUID?
    let onAddPapers: () -> Void
    let onDropURLs: ([URL]) -> Void
    let onClearRecentHistory: () throws -> Void
    let onRemovePaper: (UUID) throws -> Void
    let onGetInfo: (UUID) -> Void
    @Query(sort: \Paper.title) private var papers: [Paper]
    @State private var searchText = ""
    @State private var sortOrder = LibrarySortOrder.title
    @State private var isDropTargeted = false
    @State private var removalRequest: PaperRemovalRequest?
    @State private var persistenceErrorTitle: String?
    @State private var persistenceErrorMessage: String?

    private var contents: LibraryContents {
        LibraryContents(papers: papers, searchText: searchText, sortOrder: sortOrder)
    }

    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasRecentHistory: Bool {
        papers.contains { $0.lastOpenedAt != nil }
    }

    var body: some View {
        List(selection: $selection) {
            if contents.recent.isEmpty && contents.library.isEmpty {
                ContentUnavailableView(
                    hasSearchQuery ? "No Results" : "No Papers",
                    systemImage: hasSearchQuery ? "magnifyingglass" : "doc.text",
                    description: Text(hasSearchQuery ? "Try another title, author, year, or note." : "Add a PDF to begin your library.")
                )
            } else {
                if !contents.recent.isEmpty {
                    Section("Recent") {
                        ForEach(contents.recent) { paper in
                            paperRow(paper)
                        }
                    }
                }
                if !contents.library.isEmpty {
                    Section("Library") {
                        ForEach(contents.library) { paper in
                            paperRow(paper)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar)
        .navigationTitle("Canopy")
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [7]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame }
            guard !pdfs.isEmpty else { return false }
            onDropURLs(pdfs)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: onAddPapers) {
                    Label("Add Papers", systemImage: "plus")
                }
                .accessibilityIdentifier("add-papers-button")
                .help("Add Papers")

                Menu {
                    Picker("Sort Library By", selection: $sortOrder) {
                        ForEach(LibrarySortOrder.allCases) { order in
                            Text(order.displayName).tag(order)
                        }
                    }
                    Divider()
                    Button("Clear Recent History", action: clearRecentHistory)
                        .disabled(!hasRecentHistory)
                } label: {
                    Label("Library Options", systemImage: "ellipsis.circle")
                }
                .help("Library Options")
            }
        }
        .alert(
            persistenceErrorTitle ?? "Couldn’t Save Library Changes",
            isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: {
                    if !$0 {
                        persistenceErrorTitle = nil
                        persistenceErrorMessage = nil
                    }
                }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage ?? "Canopy could not save the change.")
        }
        .confirmationDialog(
            "Remove from Library?",
            isPresented: Binding(
                get: { removalRequest != nil },
                set: { if !$0 { removalRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: removalRequest
        ) { request in
            Button("Remove “\(request.title)”", role: .destructive) {
                removePaper(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(removalMessage(for: request.storageMode))
        }
    }

    private func paperRow(_ paper: Paper) -> some View {
        HStack(spacing: 8) {
            sourceStateSymbol(for: paper)
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title)
                    .lineLimit(1)
                if !paper.authorsDisplayText.isEmpty {
                    Text(paper.authorsDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tag(paper.id)
        .contextMenu {
            Button("Get Info", systemImage: "info.circle") {
                onGetInfo(paper.id)
            }

            Divider()

            Button("Remove from Library…", systemImage: "trash", role: .destructive) {
                removalRequest = PaperRemovalRequest(
                    id: paper.id,
                    title: paper.title,
                    storageMode: paper.storageMode
                )
            }
        }
    }

    private func clearRecentHistory() {
        do {
            try onClearRecentHistory()
        } catch {
            persistenceErrorTitle = "Couldn’t Clear Recent History"
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func removePaper(_ request: PaperRemovalRequest) {
        do {
            try onRemovePaper(request.id)
            if selection == request.id {
                selection = nil
            }
            removalRequest = nil
        } catch {
            removalRequest = nil
            persistenceErrorTitle = "Couldn’t Remove Paper"
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func removalMessage(for storageMode: PaperStorageMode) -> String {
        switch storageMode {
        case .referenced:
            "Canopy will delete this Paper’s highlights, notes, and reading progress. The original Source PDF will remain in its current location. You can undo this action."
        case .managedCopy:
            "Canopy will remove its Source PDF copy along with this Paper’s highlights, notes, and reading progress. You can undo this action."
        }
    }

    @ViewBuilder
    private func sourceStateSymbol(for paper: Paper) -> some View {
        switch paper.sourceState {
        case .available:
            EmptyView()
        case .sourceUnavailable:
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .help("Source Unavailable")
        case .brokenReference:
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.orange)
                .help("Source Missing")
        case .sourceChanged:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help("Source Changed")
        case .libraryCopyMissing:
            Image(systemName: "doc.badge.ellipsis")
                .foregroundStyle(.red)
                .help("Library Copy Missing")
        }
    }
}

private struct PaperRemovalRequest {
    let id: UUID
    let title: String
    let storageMode: PaperStorageMode
}
