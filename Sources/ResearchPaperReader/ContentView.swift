import SwiftUI

struct ContentView: View {
    @Environment(PaperStore.self) private var store
    @State private var selectedPaperID: Paper.ID?
    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @State private var statusFilter: ReadingStatus?
    @State private var sidebarSort: SortOrder = .recent
    @State private var navigateToPage: Int?
    @State private var isSelecting = false
    @State private var selectedIDs = Set<Paper.ID>()
    @State private var showResearchHub = false

    private var sidebarPapers: [Paper] {
        store.papers
            .filtered(searchText: searchText, debouncedSearch: debouncedSearch, status: statusFilter)
            .sorted(by: sidebarSort)
    }

    var body: some View {
        Group {
            if showResearchHub {
                researchHub
            } else {
                library
            }
        }
        .alert(
            "Research Paper Reader",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )
        ) {
            Button("OK") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "An unknown error occurred.")
        }
    }

    private var library: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 292, max: 340)
        } detail: {
            detail
                .transition(.opacity)
        }
        .toolbar {
            ToolbarItemGroup {
                if !isSelecting {
                    if selectedPaperID != nil {
                        Button {
                            selectedPaperID = nil
                        } label: {
                            Label("Back to Library", systemImage: "chevron.left")
                        }
                        .help("Return to document library")
                    }

                    Button {
                        store.importWithOpenPanel()
                    } label: {
                        Label("Import PDFs", systemImage: "plus")
                    }
                    .help("Import PDF documents into library")
                    .background {
                        Button("") { store.importWithOpenPanel() }
                            .keyboardShortcut("i", modifiers: .command)
                            .hidden()
                    }
                }

                Spacer()

                if !isSelecting {
                    Button {
                        showResearchHub = true
                    } label: {
                        Label("Research Hub", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .help("Open research workspace with collections, citations, and discovery")
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs = [] }
                    }
                } label: {
                    Label(isSelecting ? "Done" : "Select", systemImage: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .help(isSelecting ? "Finish selecting documents" : "Select multiple documents to batch delete")
            }

            if isSelecting && !selectedIDs.isEmpty {
                ToolbarItemGroup {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label("Delete (\(selectedIDs.count))", systemImage: "trash")
                    }
                    .help("Delete selected documents from library")
                }
            }
        }
    }

    private var researchHub: some View {
        ResearchHubView { paperID, page in
            selectedPaperID = paperID
            navigateToPage = page
            showResearchHub = false
        }
        .environment(store)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showResearchHub = false
                } label: {
                    Label("Back to Library", systemImage: "chevron.left")
                }
                .help("Return to document library")
                .keyboardShortcut("[", modifiers: .command)
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.title3)
                        .foregroundStyle(SolarpunkTheme.fern)
                        .frame(width: 32, height: 32)
                        .background(SolarpunkTheme.fern.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Canopy")
                            .font(.headline.weight(.bold))
                        Text("Research library")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search titles, full text", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                }
                .padding(8)
                .background(SolarpunkTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SolarpunkTheme.hairline))

                HStack(spacing: 8) {
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(nil as ReadingStatus?)
                        ForEach(ReadingStatus.allCases) { status in
                            Text(status.rawValue).tag(Optional(status))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Sort", selection: $sidebarSort) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
            .padding()

            Divider()

            if store.isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Processing \(store.enrichmentCount)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .transition(.opacity)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sidebarPapers) { paper in
                        SidebarPaperRow(
                            paper: paper,
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(paper.id),
                            onTap: {
                                if isSelecting {
                                    toggleSelection(paper.id)
                                } else {
                                    selectedPaperID = paper.id
                                }
                            }
                        )
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }

            if isSelecting && !selectedIDs.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        Text("\(selectedIDs.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .help("Delete selected documents")
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)

                        Button("Select All") {
                            selectedIDs = Set(sidebarPapers.map(\.id))
                        }
                        .help("Select all visible documents")
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !isSelecting {
                HStack {
                    Label("\(store.papers.count) document\(store.papers.count == 1 ? "" : "s")", systemImage: "books.vertical")
                    Spacer()
                    Button {
                        showResearchHub = true
                    } label: {
                        Label("Research Hub", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SolarpunkTheme.fern)
                    .help("Open Research Hub")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(SolarpunkTheme.raisedSurface.opacity(0.7))
            }
        }
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
        .background(SolarpunkTheme.sidebar)
    }

    private func deleteSelected() {
        for id in selectedIDs {
            guard let paper = store.papers.first(where: { $0.id == id }) else { continue }
            store.delete(paper)
        }
        selectedIDs = []
    }

    private func toggleSelection(_ id: Paper.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private var selectedPaperBinding: Binding<Paper>? {
        guard let selectedPaperID else { return nil }
        return Binding(
            get: {
                store.papers.first(where: { $0.id == selectedPaperID }) ?? Paper(title: "", authors: "", year: "", abstract: "", filePath: "")
            },
            set: { updatedPaper in
                guard let index = store.papers.firstIndex(where: { $0.id == selectedPaperID }) else { return }
                store.papers[index] = updatedPaper
            }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedPaperBinding {
            ReaderWorkspace(paper: selectedPaperBinding, navigateToPage: $navigateToPage)
                .environment(store)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
            SelectionScreen(
                selectedPaperID: $selectedPaperID,
                searchText: $searchText,
                debouncedSearch: $debouncedSearch,
                statusFilter: $statusFilter
            )
            .environment(store)
            .transition(.asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            ))
        }
    }
}

private struct SidebarPaperRow: View {
    let paper: Paper
    let isSelecting: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? SolarpunkTheme.fern : .gray.opacity(0.3))
                        .font(.caption)
                        .frame(width: 16)
                }

                Image(systemName: paper.documentKind.systemImage)
                    .font(.caption)
                    .foregroundStyle(paper.status.color)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(paper.authors.isEmpty ? paper.documentKind.rawValue : paper.authors)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if !paper.notes.isEmpty {
                        Label("\(paper.notes.count)", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? SolarpunkTheme.fern.opacity(0.12) : Color.clear)
    }
}
