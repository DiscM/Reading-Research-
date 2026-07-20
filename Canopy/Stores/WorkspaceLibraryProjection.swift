import CanopyCore
import Foundation

enum WorkspaceNavigationDestination: Hashable, Identifiable, Sendable {
    case allDocuments
    case recent
    case unfiled
    case collection(UUID)

    var id: Self { self }
}

enum WorkspaceDocumentStorage: Hashable, Sendable {
    case referenced
    case managedCopy
}

enum WorkspaceDocumentAttention: Hashable, Sendable {
    case sourceUnavailable
    case brokenReference
    case sourceChanged
    case libraryCopyMissing
    case indexNeedsSource
    case indexFailed
}

struct WorkspaceDocumentListItem: Identifiable {
    let id: UUID
    let title: String
    let kind: DocumentKind
    let creatorSummary: String
    let documentDate: DocumentDate?
    let dateAdded: Date
    let lastOpenedAt: Date?
    let collectionIDs: Set<UUID>
    let collectionNames: [String]
    let storage: WorkspaceDocumentStorage
    let attention: WorkspaceDocumentAttention?

    init(
        id: UUID,
        title: String,
        kind: DocumentKind,
        creatorSummary: String,
        documentDate: DocumentDate?,
        dateAdded: Date,
        lastOpenedAt: Date?,
        collectionIDs: Set<UUID>,
        collectionNames: [String],
        storage: WorkspaceDocumentStorage,
        attention: WorkspaceDocumentAttention?
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.creatorSummary = creatorSummary
        self.documentDate = documentDate
        self.dateAdded = dateAdded
        self.lastOpenedAt = lastOpenedAt
        self.collectionIDs = collectionIDs
        self.collectionNames = collectionNames
        self.storage = storage
        self.attention = attention
    }
}

enum WorkspaceDocumentSortField: String, CaseIterable, Identifiable, Sendable {
    case title
    case documentDate
    case dateAdded
    case recentlyOpened

    var id: Self { self }

    var displayName: String {
        switch self {
        case .title: "Title"
        case .documentDate: "Document Date"
        case .dateAdded: "Date Added"
        case .recentlyOpened: "Recently Opened"
        }
    }

}

enum WorkspaceSortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending
    case descending

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }

    func displayName(for field: WorkspaceDocumentSortField) -> String {
        switch (field, self) {
        case (.title, .ascending): "A–Z"
        case (.title, .descending): "Z–A"
        case (.documentDate, .ascending), (.dateAdded, .ascending), (.recentlyOpened, .ascending):
            "Oldest First"
        case (.documentDate, .descending), (.dateAdded, .descending), (.recentlyOpened, .descending):
            "Newest First"
        }
    }
}

struct WorkspaceDocumentSort: Equatable, Sendable {
    var field: WorkspaceDocumentSortField
    var direction: WorkspaceSortDirection
}

struct WorkspaceLibraryProjection {
    let documents: [WorkspaceDocumentListItem]

    init(
        documents: [WorkspaceDocumentListItem],
        destination: WorkspaceNavigationDestination,
        selectedKinds: Set<DocumentKind>,
        sort: WorkspaceDocumentSort
    ) {
        self.documents = documents
            .filter { document in
                switch destination {
                case .allDocuments:
                    true
                case .recent:
                    document.lastOpenedAt != nil
                case .unfiled:
                    document.collectionIDs.isEmpty
                case let .collection(collectionID):
                    document.collectionIDs.contains(collectionID)
                }
            }
            .filter { selectedKinds.isEmpty || selectedKinds.contains($0.kind) }
            .sorted { lhs, rhs in
                Self.isOrderedBefore(lhs, rhs, sort: sort)
            }
    }

    private static func isOrderedBefore(
        _ lhs: WorkspaceDocumentListItem,
        _ rhs: WorkspaceDocumentListItem,
        sort: WorkspaceDocumentSort
    ) -> Bool {
        let primaryComparison: ComparisonResult?
        switch sort.field {
        case .title:
            primaryComparison = lhs.title.localizedStandardCompare(rhs.title)
        case .documentDate:
            primaryComparison = compare(lhs.documentDate, rhs.documentDate)
        case .dateAdded:
            primaryComparison = compare(lhs.dateAdded, rhs.dateAdded)
        case .recentlyOpened:
            primaryComparison = compare(lhs.lastOpenedAt, rhs.lastOpenedAt)
        }

        if let primaryComparison, primaryComparison != .orderedSame {
            return sort.direction == .ascending
                ? primaryComparison == .orderedAscending
                : primaryComparison == .orderedDescending
        }
        if primaryComparison == nil {
            let lhsHasValue = hasPrimaryValue(lhs, for: sort.field)
            let rhsHasValue = hasPrimaryValue(rhs, for: sort.field)
            if lhsHasValue != rhsHasValue {
                return lhsHasValue
            }
        }

        let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func hasPrimaryValue(
        _ document: WorkspaceDocumentListItem,
        for field: WorkspaceDocumentSortField
    ) -> Bool {
        switch field {
        case .title, .dateAdded:
            true
        case .documentDate:
            document.documentDate != nil
        case .recentlyOpened:
            document.lastOpenedAt != nil
        }
    }

    private static func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }

    private static func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult? {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil ? .orderedSame : nil }
        return compare(lhs, rhs)
    }

    private static func compare(
        _ lhs: DocumentDate?,
        _ rhs: DocumentDate?
    ) -> ComparisonResult? {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil ? .orderedSame : nil }
        let lhsComponents = [lhs.year, lhs.month ?? 0, lhs.day ?? 0]
        let rhsComponents = [rhs.year, rhs.month ?? 0, rhs.day ?? 0]
        if lhsComponents.lexicographicallyPrecedes(rhsComponents) { return .orderedAscending }
        if rhsComponents.lexicographicallyPrecedes(lhsComponents) { return .orderedDescending }
        return .orderedSame
    }
}

enum WorkspaceDocumentSelection {
    static func reconciled(
        _ selection: Set<UUID>,
        visibleDocuments: [WorkspaceDocumentListItem]
    ) -> Set<UUID> {
        selection.intersection(visibleDocuments.lazy.map(\.id))
    }
}

struct WorkspaceMultiSelectionSummary {
    let documentCount: Int
    let referencedCount: Int
    let managedCopyCount: Int
    let kinds: [DocumentKind]

    init(documents: [WorkspaceDocumentListItem]) {
        documentCount = documents.count
        referencedCount = documents.count { $0.storage == .referenced }
        managedCopyCount = documents.count { $0.storage == .managedCopy }
        let selectedKinds = Set(documents.map(\.kind))
        kinds = DocumentKind.allCases.filter(selectedKinds.contains)
    }
}

enum WorkspaceCollectionMembershipState: Equatable, Sendable {
    case checked
    case unchecked
    case mixed

    var systemImage: String {
        switch self {
        case .checked: "checkmark.square.fill"
        case .unchecked: "square"
        case .mixed: "minus.square.fill"
        }
    }

    static func resolve(
        collectionID: UUID,
        among documents: [WorkspaceDocumentListItem]
    ) -> Self {
        let memberCount = documents.count { $0.collectionIDs.contains(collectionID) }
        if memberCount == 0 { return .unchecked }
        if memberCount == documents.count { return .checked }
        return .mixed
    }
}
