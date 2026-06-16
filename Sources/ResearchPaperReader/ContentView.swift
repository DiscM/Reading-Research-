import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PaperStore
    @State private var selectedPaperID: Paper.ID?
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchTask: Task<Void, Never>?

    private var filteredPapers: [Paper] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.papers
        }

        return store.papers.filter { paper in
            paper.title.localizedCaseInsensitiveContains(searchText)
            || paper.authors.localizedCaseInsensitiveContains(searchText)
            || paper.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            || paper.notes.contains { $0.body.localizedCaseInsensitiveContains(searchText) || $0.quote.localizedCaseInsensitiveContains(searchText) }
            || paper.allText.localizedCaseInsensitiveContains(debouncedSearch)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                LibraryHeader(searchText: $searchText)

                List(selection: $selectedPaperID) {
                    ForEach(filteredPapers) { paper in
                        PaperRow(paper: paper)
                            .tag(paper.id)
                    }
                    .onDelete { offsets in
                        offsets.map { filteredPapers[$0] }.forEach(store.delete)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 290, ideal: 340)
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    debouncedSearch = newValue
                }
            }
        } detail: {
            if let index = selectedIndex {
                ReaderWorkspace(paper: $store.papers[index])
                    .environmentObject(store)
            } else {
                EmptyLibraryView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.importWithOpenPanel()
                } label: {
                    Label("Import Papers", systemImage: "plus")
                }

                if let index = selectedIndex {
                    Picker("Status", selection: $store.papers[index].status) {
                        ForEach(ReadingStatus.allCases) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                }
            }
        }
        .alert("Library Error", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private var selectedIndex: Int? {
        guard let selectedPaperID else { return nil }
        return store.papers.firstIndex { $0.id == selectedPaperID }
    }
}

private struct LibraryHeader: View {
    @Binding var searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paper Library")
                .font(.title2.bold())

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search titles, notes, full text", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }
}

private struct PaperRow: View {
    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(2)

            Text(paper.authors)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(paper.status.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                if !paper.notes.isEmpty {
                    Label("\(paper.notes.count)", systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Import a research paper to start reading.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
