import CanopyCore
import Foundation

struct WorkspaceCollectionListItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let documentCount: Int

    init(id: UUID, name: String, documentCount: Int) {
        self.id = id
        self.name = name
        self.documentCount = documentCount
    }

    init(collection: CanopyCore.Collection) {
        self.init(
            id: collection.id,
            name: collection.name,
            documentCount: collection.documents.count
        )
    }
}

struct WorkspaceNavigationCounts: Equatable, Sendable {
    let allDocuments: Int
    let recent: Int
    let unfiled: Int

    init(allDocuments: Int, recent: Int, unfiled: Int) {
        self.allDocuments = allDocuments
        self.recent = recent
        self.unfiled = unfiled
    }

    init(documents: [WorkspaceDocumentListItem]) {
        self.init(
            allDocuments: documents.count,
            recent: documents.count { $0.lastOpenedAt != nil },
            unfiled: documents.count { $0.collectionIDs.isEmpty }
        )
    }
}

enum WorkspaceStatusSeverity: Equatable, Sendable {
    case neutral
    case warning
    case critical
}

struct WorkspaceOverviewStatus: Equatable, Sendable {
    let title: String
    let detail: String?
    let systemImage: String
    let severity: WorkspaceStatusSeverity
    let actionTitle: String?
}

struct WorkspaceCollectionMembershipOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let state: WorkspaceCollectionMembershipState
}

struct WorkspaceDocumentOverviewModel {
    let id: UUID
    let title: String
    let documentNote: String
    let kind: DocumentKind
    let documentDate: DocumentDate?
    let creatorSummary: String
    let sourceStatus: WorkspaceOverviewStatus
    let indexStatus: WorkspaceOverviewStatus?
    let collectionMemberships: [WorkspaceCollectionMembershipOption]

    init(
        id: UUID,
        title: String,
        documentNote: String,
        kind: DocumentKind,
        documentDate: DocumentDate?,
        creatorSummary: String,
        sourceStatus: WorkspaceOverviewStatus,
        indexStatus: WorkspaceOverviewStatus?,
        collectionMemberships: [WorkspaceCollectionMembershipOption]
    ) {
        self.id = id
        self.title = title
        self.documentNote = documentNote
        self.kind = kind
        self.documentDate = documentDate
        self.creatorSummary = creatorSummary
        self.sourceStatus = sourceStatus
        self.indexStatus = indexStatus
        self.collectionMemberships = collectionMemberships
    }

    init(
        document: Document,
        availableCollections: [CanopyCore.Collection],
        indexStatus: PDFTextIndexStatus? = nil
    ) {
        let memberIDs = Set(document.collections.map(\.id))
        self.init(
            id: document.id,
            title: document.title,
            documentNote: document.documentNote,
            kind: document.kind,
            documentDate: document.documentDate,
            creatorSummary: document.creatorsDisplayText,
            sourceStatus: WorkspaceOverviewStatus(sourceState: document.sourceState, storage: document.storageMode),
            indexStatus: indexStatus.map(WorkspaceOverviewStatus.init(indexStatus:)),
            collectionMemberships: availableCollections
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { collection in
                    WorkspaceCollectionMembershipOption(
                        id: collection.id,
                        name: collection.name,
                        state: memberIDs.contains(collection.id) ? .checked : .unchecked
                    )
                }
        )
    }
}

extension WorkspaceDocumentListItem {
    init(
        document: Document,
        indexStatus: PDFTextIndexStatus? = nil
    ) {
        let sourceAttention = WorkspaceDocumentAttention(sourceState: document.sourceState)
        self.init(
            id: document.id,
            title: document.title,
            kind: document.kind,
            creatorSummary: document.creatorsDisplayText,
            documentDate: document.documentDate,
            dateAdded: document.dateAdded,
            lastOpenedAt: document.lastOpenedAt,
            collectionIDs: Set(document.collections.map(\.id)),
            collectionNames: document.collections
                .map(\.name)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            storage: document.storageMode == .managedCopy ? .managedCopy : .referenced,
            attention: sourceAttention ?? indexStatus.flatMap(WorkspaceDocumentAttention.init(indexStatus:))
        )
    }

    var secondaryText: String {
        [kind.displayName, creatorSummary, documentDate?.workspaceDisplayText]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }
}

extension WorkspaceDocumentAttention {
    init?(sourceState: DocumentSourceState) {
        switch sourceState {
        case .available:
            return nil
        case .sourceUnavailable:
            self = .sourceUnavailable
        case .brokenReference:
            self = .brokenReference
        case .sourceChanged:
            self = .sourceChanged
        case .libraryCopyMissing:
            self = .libraryCopyMissing
        }
    }

    init?(indexStatus: PDFTextIndexStatus) {
        switch indexStatus.lifecycle {
        case .needsSource:
            self = .indexNeedsSource
        case .failed:
            self = .indexFailed
        case .pending, .indexing, .ready:
            return nil
        }
    }

    var label: String {
        switch self {
        case .sourceUnavailable: "Source Unavailable"
        case .brokenReference: "Broken Reference"
        case .sourceChanged: "Source Changed"
        case .libraryCopyMissing: "Library Copy Missing"
        case .indexNeedsSource: "Index Needs Source"
        case .indexFailed: "Indexing Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .sourceUnavailable, .indexNeedsSource: "externaldrive.badge.exclamationmark"
        case .brokenReference: "link.badge.plus"
        case .sourceChanged: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .libraryCopyMissing: "doc.badge.ellipsis"
        case .indexFailed: "magnifyingglass.circle.fill"
        }
    }

    var severity: WorkspaceStatusSeverity {
        switch self {
        case .sourceUnavailable, .indexNeedsSource:
            .warning
        case .brokenReference, .sourceChanged, .libraryCopyMissing, .indexFailed:
            .critical
        }
    }

    var actionTitle: String {
        switch self {
        case .sourceUnavailable, .indexNeedsSource: "Locate Source…"
        case .brokenReference: "Repair Reference…"
        case .sourceChanged: "Review Source…"
        case .libraryCopyMissing: "Restore Copy…"
        case .indexFailed: "Retry Indexing"
        }
    }
}

extension WorkspaceOverviewStatus {
    init(sourceState: DocumentSourceState, storage: DocumentStorageMode) {
        let storageDescription = storage == .managedCopy ? "Managed Copy" : "Referenced Original"
        switch sourceState {
        case .available:
            self.init(
                title: "Available",
                detail: storageDescription,
                systemImage: "checkmark.circle",
                severity: .neutral,
                actionTitle: nil
            )
        default:
            let attention = WorkspaceDocumentAttention(sourceState: sourceState)!
            self.init(
                title: attention.label,
                detail: storageDescription,
                systemImage: attention.systemImage,
                severity: attention.severity,
                actionTitle: attention.actionTitle
            )
        }
    }

    init(indexStatus: PDFTextIndexStatus) {
        switch indexStatus.lifecycle {
        case .pending:
            self.init(
                title: "Pending",
                detail: nil,
                systemImage: "clock",
                severity: .neutral,
                actionTitle: nil
            )
        case .indexing:
            self.init(
                title: "Indexing",
                detail: "\(indexStatus.indexedPageCount) of \(indexStatus.totalPageCount) pages",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                severity: .neutral,
                actionTitle: nil
            )
        case .ready:
            self.init(
                title: "Ready",
                detail: "\(indexStatus.totalPageCount) pages indexed",
                systemImage: "checkmark.circle",
                severity: .neutral,
                actionTitle: nil
            )
        case .needsSource:
            self.init(
                title: "Needs Source",
                detail: nil,
                systemImage: "externaldrive.badge.exclamationmark",
                severity: .warning,
                actionTitle: "Locate Source…"
            )
        case .failed:
            self.init(
                title: "Indexing Failed",
                detail: indexStatus.failureDescription,
                systemImage: "exclamationmark.triangle",
                severity: .critical,
                actionTitle: "Retry"
            )
        }
    }
}

extension DocumentDate {
    var workspaceDisplayText: String {
        guard let month else { return String(year) }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day ?? 1
        guard let date = components.date else { return String(year) }
        if day == nil {
            return date.formatted(.dateTime.month(.abbreviated).year())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
