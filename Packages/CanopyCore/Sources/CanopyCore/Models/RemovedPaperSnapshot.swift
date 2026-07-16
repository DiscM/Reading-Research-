import Foundation

public struct AuthorCreditSnapshot: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let position: Int
    public let displayName: String
    public let familyName: String
    public let provenance: MetadataProvenance

    public init(
        id: UUID,
        position: Int,
        displayName: String,
        familyName: String,
        provenance: MetadataProvenance
    ) {
        self.id = id
        self.position = position
        self.displayName = displayName
        self.familyName = familyName
        self.provenance = provenance
    }

    init(authorCredit: AuthorCredit) {
        self.init(
            id: authorCredit.id,
            position: authorCredit.position,
            displayName: authorCredit.displayName,
            familyName: authorCredit.familyName,
            provenance: authorCredit.provenance
        )
    }
}

public struct RemovedPaperSnapshot: Equatable, Sendable {
    public let id: UUID
    public let fingerprint: Data
    public let title: String
    public let titleProvenance: MetadataProvenance
    public let publicationYear: Int?
    public let publicationYearProvenance: MetadataProvenance?
    public let doi: String?
    public let doiProvenance: MetadataProvenance?
    public let arxivID: String?
    public let arxivIDProvenance: MetadataProvenance?
    public let storageMode: PaperStorageMode
    public let sourceState: PaperSourceState
    public let bookmarkData: Data?
    public let managedRelativePath: String?
    public let sourceFilename: String
    public let rememberedLocation: String?
    public let sourceFileSize: Int64
    public let sourceModificationDate: Date?
    public let pageCount: Int
    public let hasSelectableText: Bool
    public let dateAdded: Date
    public let lastOpenedAt: Date?
    public let lastPageIndex: Int?
    public let lastViewport: Data?
    public let lastZoomScale: Double?
    public let isInspectorPresented: Bool
    public let authorCredits: [AuthorCreditSnapshot]
    public let annotations: [AnnotationSnapshot]
    public let managedCopyWasStaged: Bool

    init(paper: Paper, managedCopyWasStaged: Bool) {
        id = paper.id
        fingerprint = paper.fingerprint
        title = paper.title
        titleProvenance = paper.titleProvenance
        publicationYear = paper.publicationYear
        publicationYearProvenance = paper.publicationYearProvenance
        doi = paper.doi
        doiProvenance = paper.doiProvenance
        arxivID = paper.arxivID
        arxivIDProvenance = paper.arxivIDProvenance
        storageMode = paper.storageMode
        sourceState = paper.sourceState
        bookmarkData = paper.bookmarkData
        managedRelativePath = paper.managedRelativePath
        sourceFilename = paper.sourceFilename
        rememberedLocation = paper.rememberedLocation
        sourceFileSize = paper.sourceFileSize
        sourceModificationDate = paper.sourceModificationDate
        pageCount = paper.pageCount
        hasSelectableText = paper.hasSelectableText
        dateAdded = paper.dateAdded
        lastOpenedAt = paper.lastOpenedAt
        lastPageIndex = paper.lastPageIndex
        lastViewport = paper.lastViewport
        lastZoomScale = paper.lastZoomScale
        isInspectorPresented = paper.isInspectorPresented
        authorCredits = paper.authorCredits
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map(AuthorCreditSnapshot.init)
        annotations = paper.annotations
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { AnnotationSnapshot(annotation: $0, paperID: paper.id) }
        self.managedCopyWasStaged = managedCopyWasStaged
    }
}
