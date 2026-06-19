import SwiftUI

enum SortOrder: String, CaseIterable, Identifiable {
    case recent = "Recent"
    case title = "Title"
    case author = "Author"
    case year = "Year"
    var id: String { rawValue }
}

struct SelectionScreen: View {
    @EnvironmentObject private var store: PaperStore
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
        VStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .symbolEffect(.bounce, options: .nonRepeating)

            Text("Your document library is empty.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Import research papers, lecture slides, study notes, or other PDFs.")
                .font(.callout)
                .foregroundStyle(.tertiary)

            Button {
                store.importWithOpenPanel()
            } label: {
                Label("Import PDFs", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .nonRepeating)

            Text("No documents match your search.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Try adjusting the search text or status filter.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                    .padding(.horizontal)
                    .padding(.top, 8)

                if showsContinueReading {
                    ContinueReadingShelf(
                        papers: Array(continueReadingPapers.prefix(6)),
                        selectedPaperID: $selectedPaperID
                    )
                    .padding(.horizontal)
                }

                ForEach(papers) { paper in
                    PaperCard(paper: paper, isSelected: selectedPaperID == paper.id)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                selectedPaperID = paper.id
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .scrollIndicators(.hidden)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: sortOrder)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: statusFilter?.rawValue)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: searchText)
    }

    private var header: some View {
        HStack {
            Text("\(papers.count) document\(papers.count == 1 ? "" : "s")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Sort", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .labelsHidden()
        }
    }
}

private struct PaperCard: View {
    let paper: Paper
    let isSelected: Bool

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
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .padding(.top, 8)
                }

                Divider()
                    .padding(.vertical, 10)

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
                            .foregroundStyle(.green)
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
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }

                    if !paper.arxivId.isEmpty {
                        Text("arXiv")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1), in: Capsule())
                    }

                    if !paper.tags.isEmpty {
                        Spacer()
                        ForEach(paper.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(statusColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(statusColor.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
        .scaleEffect(isSelected ? 0.97 : 1)
        .opacity(isSelected ? 0.6 : 1)
    }

    private var statusStrip: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(statusColor)
            .frame(width: 5)
            .padding(.trailing, 0)
            .offset(x: -2)
    }

    private var statusBadge: some View {
        Text(paper.status.rawValue)
            .font(.caption2.weight(.medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.12), in: Capsule())
    }
}

private struct ContinueReadingShelf: View {
    let papers: [Paper]
    @Binding var selectedPaperID: Paper.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Continue Reading", systemImage: "bookmark.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
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
                                        .tint(.green)
                                }

                                Text(pageLabel(for: paper))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(width: 220, height: 126, alignment: .leading)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.quaternary, lineWidth: 1)
                            }
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
