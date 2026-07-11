import CanopyCore
import SwiftData
import SwiftUI

struct LibrarySidebarView: View {
    @Binding var selection: UUID?
    @Query(sort: \Paper.title) private var papers: [Paper]
    @State private var searchText = ""

    private var filteredPapers: [Paper] {
        guard !searchText.isEmpty else { return papers }
        return papers.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.authors.localizedStandardContains(searchText)
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
                    description: Text(searchText.isEmpty ? "Import a PDF to begin your library." : "Try another title, author, year, or note.")
                )
            } else {
                Section("Library") {
                    ForEach(filteredPapers) { paper in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paper.title)
                                .lineLimit(1)
                            if !paper.authors.isEmpty {
                                Text(paper.authors)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
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
    }
}

