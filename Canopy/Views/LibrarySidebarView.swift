import CanopyCore
import SwiftData
import SwiftUI

struct LibrarySidebarView: View {
    @Binding var selection: UUID?
    let onAddPapers: () -> Void
    let onDropURLs: ([URL]) -> Void
    @Query(sort: \Paper.title) private var papers: [Paper]
    @State private var searchText = ""
    @State private var isDropTargeted = false

    private var filteredPapers: [Paper] {
        guard !searchText.isEmpty else { return papers }
        return papers.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.authorsDisplayText.localizedStandardContains(searchText)
                || $0.publicationYear.map(String.init)?.contains(searchText) == true
                || $0.annotations.contains { $0.note.localizedStandardContains(searchText) }
        }
    }

    var body: some View {
        List(selection: $selection) {
            if filteredPapers.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Papers" : "No Results",
                    systemImage: searchText.isEmpty ? "doc.text" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Add a PDF to begin your library." : "Try another title, author, year, or note.")
                )
            } else {
                Section("Library") {
                    ForEach(filteredPapers) { paper in
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
            ToolbarItem(placement: .navigation) {
                Button(action: onAddPapers) {
                    Label("Add Papers", systemImage: "plus")
                }
                .accessibilityIdentifier("add-papers-button")
                .help("Add Papers")
            }
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
