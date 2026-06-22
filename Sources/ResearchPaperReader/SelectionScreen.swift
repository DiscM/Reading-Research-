import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title"
    case author = "Author"
    case year = "Year"
    var id: String { rawValue }
}

struct SelectionScreen: View {
    @Environment(PaperStore.self) private var store
    @Binding var selectedPaperID: Paper.ID?
    @Binding var searchText: String
    @Binding var debouncedSearch: String
    @Binding var statusFilter: ReadingStatus?
    @State private var sortOrder: SortOrder = .recent

    private var papers: [Paper] {
        store.papers
            .filtered(searchText: searchText, debouncedSearch: debouncedSearch, status: statusFilter)
            .sorted(by: sortOrder)
    }

    private var continueReadingPapers: [Paper] {
        store.papers
            .filter { $0.status == .reading && $0.canResumeReading }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }

    private var showsContinueReading: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && statusFilter == nil
            && !continueReadingPapers.isEmpty
    }

    var body: some View {
        Group {
            if store.papers.isEmpty {
                emptyState
            } else if papers.isEmpty {
                noMatchState
            } else {
                content
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { _ in
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            if !pdfs.isEmpty { store.importDocuments(pdfs) }
            return !pdfs.isEmpty
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Document Library", systemImage: "doc.richtext")
        } description: {
            Text("Import research papers, lecture slides, study notes, or other PDFs to get started.")
        } actions: {
            Button {
                store.importWithOpenPanel()
            } label: {
                Label("Import PDFs", systemImage: "plus")
            }
            .help("Import PDF documents into your library")
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                if showsContinueReading {
                    ContinueReadingShelf(
                        papers: Array(continueReadingPapers.prefix(6)),
                        selectedPaperID: $selectedPaperID
                    )
                    .padding(.horizontal, 20)
                }

                ForEach(papers) { paper in
                    PaperCard(paper: paper, isSelected: selectedPaperID == paper.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedPaperID = paper.id
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                        .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .background(SolarpunkTheme.canvas)
        .scrollIndicators(.hidden)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: sortOrder)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: statusFilter?.rawValue)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: searchText)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your living library")
                    .font(.system(.title, design: .rounded, weight: .bold))

                Text("Tend ideas, trace evidence, and return to what matters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("\(papers.count) document\(papers.count == 1 ? "" : "s")", systemImage: "books.vertical.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SolarpunkTheme.spruce)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SolarpunkTheme.lichen.opacity(0.22), in: Capsule())

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
            .labelsHidden()
        }
        .padding(.vertical, 8)
    }
}

private struct PaperCard: View {
    let paper: Paper
    let isSelected: Bool

    private var dateText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: paper.importedAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            statusStrip

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(paper.title)
                                .font(.headline.weight(.semibold))
                                .lineLimit(2)

                            Label(paper.documentKind.rawValue, systemImage: paper.documentKind.systemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        statusBadge
                    }

                    if !paper.authors.isEmpty {
                        Text(paper.authors)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !paper.abstract.isEmpty {
                    Text(paper.abstract)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.top, 5)
                }

                Divider()
                    .padding(.vertical, 6)

                HStack(spacing: 16) {
                    Label(dateText, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !paper.notes.isEmpty {
                        Label("\(paper.notes.count)", systemImage: "note.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let lastReadPage = paper.lastReadPage, lastReadPage > 1 {
                        Label("Page \(lastReadPage)", systemImage: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(SolarpunkTheme.moss)
                    }

                    if !paper.year.isEmpty {
                        Text(paper.year)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if !paper.venue.isEmpty {
                        Label(paper.venue, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !paper.doi.isEmpty {
                        Text("DOI")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SolarpunkTheme.fern)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(SolarpunkTheme.fern.opacity(0.1), in: Capsule())
                    }

                    if !paper.arxivId.isEmpty {
                        Text("arXiv")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SolarpunkTheme.clay)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(SolarpunkTheme.clay.opacity(0.1), in: Capsule())
                    }

                    if !paper.tags.isEmpty {
                        Spacer()
                        ForEach(paper.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(paper.status.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(paper.status.color.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding(10)
        }
        .solarpunkCard(cornerRadius: 12)
        .scaleEffect(isSelected ? 0.97 : 1)
        .opacity(isSelected ? 0.6 : 1)
    }

    private var statusStrip: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(paper.status.color)
            .frame(width: 5)
            .padding(.trailing, 0)
            .offset(x: -2)
    }

    private var statusBadge: some View {
        Text(paper.status.rawValue)
            .font(.caption2.weight(.medium))
            .foregroundStyle(paper.status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(paper.status.color.opacity(0.12), in: Capsule())
    }
}

private struct ContinueReadingShelf: View {
    let papers: [Paper]
    @Binding var selectedPaperID: Paper.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Continue Reading", systemImage: "bookmark.fill")
                .font(.headline)
                .foregroundStyle(SolarpunkTheme.spruce)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(papers) { paper in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedPaperID = paper.id
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(paper.documentKind.rawValue, systemImage: paper.documentKind.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(paper.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Spacer(minLength: 0)

                                if let progress = paper.readingProgress {
                                    ProgressView(value: progress)
                                        .tint(SolarpunkTheme.fern)
                                }

                                Text(pageLabel(for: paper))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .frame(width: 190, height: 104, alignment: .leading)
                            .solarpunkCard(cornerRadius: 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 4)
    }

    private func pageLabel(for paper: Paper) -> String {
        guard let page = paper.lastReadPage else { return "Reading" }
        return paper.pageCount > 0 ? "Page \(page) of \(paper.pageCount)" : "Page \(page)"
    }
}
