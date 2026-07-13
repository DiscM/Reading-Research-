import CanopyCore
import Foundation

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case title
    case dateAdded

    var id: Self { self }

    var displayName: String {
        switch self {
        case .title: "Title"
        case .dateAdded: "Date Added"
        }
    }
}

struct LibraryContents {
    let recent: [Paper]
    let library: [Paper]

    init(papers: [Paper], searchText: String, sortOrder: LibrarySortOrder) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = papers.compactMap { paper in
            LibraryMatch(paper: paper, query: query)
        }

        recent = matches
            .filter { $0.paper.lastOpenedAt != nil }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return LibraryContents.recentOrder(lhs.paper, rhs.paper)
            }
            .map(\.paper)

        let remaining = matches.filter { $0.paper.lastOpenedAt == nil }
        let sortedRemaining = switch sortOrder {
        case .title:
            remaining.sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return LibraryContents.titleOrder(lhs.paper, rhs.paper)
            }
        case .dateAdded:
            remaining.sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }
                return LibraryContents.dateAddedOrder(lhs.paper, rhs.paper)
            }
        }
        library = sortedRemaining.map(\.paper)
    }

    private static func recentOrder(_ lhs: Paper, _ rhs: Paper) -> Bool {
        if lhs.lastOpenedAt != rhs.lastOpenedAt {
            return lhs.lastOpenedAt! > rhs.lastOpenedAt!
        }
        return titleOrder(lhs, rhs)
    }

    private static func titleOrder(_ lhs: Paper, _ rhs: Paper) -> Bool {
        let comparison = lhs.title.localizedStandardCompare(rhs.title)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        if lhs.dateAdded != rhs.dateAdded {
            return lhs.dateAdded > rhs.dateAdded
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func dateAddedOrder(_ lhs: Paper, _ rhs: Paper) -> Bool {
        if lhs.dateAdded != rhs.dateAdded {
            return lhs.dateAdded > rhs.dateAdded
        }
        return titleOrder(lhs, rhs)
    }
}

private struct LibraryMatch {
    let paper: Paper
    let rank: Int

    init?(paper: Paper, query: String) {
        self.paper = paper
        guard !query.isEmpty else {
            rank = 0
            return
        }
        if paper.title.localizedStandardContains(query) {
            rank = 0
        } else if paper.authorsDisplayText.localizedStandardContains(query)
                    || paper.publicationYear.map(String.init)?.localizedStandardContains(query) == true {
            rank = 1
        } else if paper.annotations.contains(where: { $0.note.localizedStandardContains(query) }) {
            rank = 2
        } else {
            return nil
        }
    }
}
