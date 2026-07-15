import CanopyCore
import SwiftData
import SwiftUI

struct LibrarySidebarView: View {
    @Binding var selection: UUID?
    let onAddPapers: () -> Void
    let onDropURLs: ([URL]) -> Void
    let onClearRecentHistory: () throws -> Void
    let onRequestRemoval: (UUID) -> Void
    let onGetInfo: (UUID) -> Void
    let onSourceRecoveryAction: (SourceRecoveryAction, UUID) -> Void
    @Query(sort: \Paper.title) private var papers: [Paper]
    @State private var searchText = ""
    @State private var sortOrder = LibrarySortOrder.title
    @State private var isDropTargeted = false
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
    }

    private func paperRow(_ paper: Paper) -> some View {
        let sourcePresentation = SourceStatePresentation(paper.sourceState)
        return HStack(spacing: 8) {
            sourceStateSymbol(for: sourcePresentation)
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title)
                    .lineLimit(1)
                if !paper.authorsDisplayText.isEmpty {
                    Text(paper.authorsDisplayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let sourceStateLabel = sourcePresentation.label {
                    Text(sourceStateLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .tag(paper.id)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(paper.title)
        .accessibilityValue(paperAccessibilityValue(paper, presentation: sourcePresentation))
        .accessibilityHint("Select to open this Paper")
        .contextMenu {
            Button("Get Info", systemImage: "info.circle") {
                onGetInfo(paper.id)
            }

            Divider()

            let recoveryActions = sourcePresentation.actions
            ForEach(recoveryActions) { action in
                Button(
                    action.title,
                    systemImage: action.systemImage,
                    role: action == .removeFromLibrary ? .destructive : nil
                ) {
                    onSourceRecoveryAction(action, paper.id)
                }
            }

            if !recoveryActions.contains(.removeFromLibrary) {
                Button("Remove from Library…", systemImage: "trash", role: .destructive) {
                    onRequestRemoval(paper.id)
                }
            }
        }
    }

    private func paperAccessibilityValue(
        _ paper: Paper,
        presentation: SourceStatePresentation
    ) -> String {
        [paper.authorsDisplayText, presentation.label]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }

    private func clearRecentHistory() {
        do {
            try onClearRecentHistory()
        } catch {
            persistenceErrorTitle = "Couldn’t Clear Recent History"
            persistenceErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func sourceStateSymbol(for presentation: SourceStatePresentation) -> some View {
        if let systemImage = presentation.systemImage, let label = presentation.label {
            switch presentation.severity {
            case .neutral:
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .help(label)
                    .accessibilityHidden(true)
            case .warning:
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .help(label)
                    .accessibilityHidden(true)
            case .critical:
                Image(systemName: systemImage)
                    .foregroundStyle(.red)
                    .help(label)
                    .accessibilityHidden(true)
            }
        } else {
            EmptyView()
        }
    }
}
