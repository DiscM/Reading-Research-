import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PaperStore
    @State private var selectedPaperID: Paper.ID?
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                LibraryHeader(searchText: $searchText, searchFocused: $searchFocused)

                PaperList(store: store, selectedPaperID: $selectedPaperID, searchText: $searchText, debouncedSearch: $debouncedSearch)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 320)
            .onTapGesture { searchFocused = false }
            .onKeyPress(.escape) { searchFocused = false; return .handled }
            .background {
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .hidden()
            }
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
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paper Library")
                .font(.title2.bold())

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search titles, notes, full text", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused(searchFocused)
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

private struct PaperList: View {
    @ObservedObject var store: PaperStore
    @Binding var selectedPaperID: Paper.ID?
    @Binding var searchText: String
    @Binding var debouncedSearch: String

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
        List(selection: $selectedPaperID) {
            ForEach(filteredPapers) { paper in
                PaperRow(paper: paper)
                    .tag(paper.id)
            }
            .onDelete { offsets in
                offsets.map { filteredPapers[$0] }.forEach(store.delete)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            if !pdfs.isEmpty { store.importPDFs(pdfs) }
            return !pdfs.isEmpty
        }
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
