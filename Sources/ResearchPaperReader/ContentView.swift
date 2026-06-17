import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PaperStore
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

    private var sidebarPapers: [Paper] {
        store.papers
            .filtered(searchText: searchText, debouncedSearch: debouncedSearch, status: statusFilter)
            .sorted(by: sidebarSort)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 300)
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
                    }

                    Button {
                        store.importWithOpenPanel()
                    } label: {
                        Label("Import Papers", systemImage: "plus")
                    }
                    .background {
                        Button("") { store.importWithOpenPanel() }
                            .keyboardShortcut("i", modifiers: .command)
                            .hidden()
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs = [] }
                    }
                } label: {
                    Label(isSelecting ? "Done" : "Select", systemImage: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                }
            }

            if isSelecting && !selectedIDs.isEmpty {
                ToolbarItemGroup {
                    Button(role: .destructive) {
                        let papersToDelete = selectedIDs.compactMap { id in store.papers.first { $0.id == id } }
                        for p in papersToDelete { store.delete(p) }
                        selectedIDs = []
                    } label: {
                        Label("Delete (\(selectedIDs.count))", systemImage: "trash")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Paper Library")
                    .font(.title2.bold())

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search titles, full text", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

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
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                    Text("Enriching \(store.enrichmentCount)...")
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
                            let papersToDelete = selectedIDs.compactMap { id in store.papers.first { $0.id == id } }
                            for p in papersToDelete { store.delete(p) }
                            selectedIDs = []
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)

                        Button("Select All") {
                            selectedIDs = Set(sidebarPapers.map(\.id))
                        }
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
                Text("\(store.papers.count) paper\(store.papers.count == 1 ? "" : "s") in library")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
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
    }

    private func toggleSelection(_ id: Paper.ID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private var selectedIndex: Int? {
        guard let selectedPaperID else { return nil }
        return store.papers.firstIndex { $0.id == selectedPaperID }
    }

    @ViewBuilder
    private var detail: some View {
        if let index = selectedIndex {
            ReaderWorkspace(paper: $store.papers[index], navigateToPage: $navigateToPage)
                .environmentObject(store)
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
            .environmentObject(store)
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

    private var statusColor: Color {
        switch paper.status {
        case .unread:    .gray
        case .skimmed:   .blue
        case .reading:   .green
        case .read:      .indigo
        case .cited:     .purple
        case .rejected:  .red
        case .archived:  .secondary
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? .blue : .gray.opacity(0.3))
                        .font(.caption)
                        .frame(width: 16)
                }

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(paper.authors)
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
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
