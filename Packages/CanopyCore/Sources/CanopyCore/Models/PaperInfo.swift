import Foundation

public struct PaperInfoSnapshot: Equatable, Sendable {
    public let paperID: UUID
    public let title: String
    public let titleProvenance: MetadataProvenance
    public let publicationYear: Int?
    public let publicationYearProvenance: MetadataProvenance?
    public let doi: String?
    public let doiProvenance: MetadataProvenance?
    public let arxivID: String?
    public let arxivIDProvenance: MetadataProvenance?
    public let authorCredits: [AuthorCreditSnapshot]

    public init(
        paperID: UUID,
        title: String,
        titleProvenance: MetadataProvenance,
        publicationYear: Int?,
        publicationYearProvenance: MetadataProvenance?,
        doi: String?,
        doiProvenance: MetadataProvenance?,
        arxivID: String?,
        arxivIDProvenance: MetadataProvenance?,
        authorCredits: [AuthorCreditSnapshot]
    ) {
        self.paperID = paperID
        self.title = title
        self.titleProvenance = titleProvenance
        self.publicationYear = publicationYear
        self.publicationYearProvenance = publicationYearProvenance
        self.doi = doi
        self.doiProvenance = doiProvenance
        self.arxivID = arxivID
        self.arxivIDProvenance = arxivIDProvenance
        self.authorCredits = authorCredits
    }
}

public struct AuthorCreditUpdate: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let displayName: String
    public let familyName: String

    public init(id: UUID, displayName: String, familyName: String) {
        self.id = id
        self.displayName = displayName
        self.familyName = familyName
    }
}

public struct PaperInfoUpdate: Equatable, Sendable {
    public let title: String
    public let publicationYear: Int?
    public let doi: String?
    public let arxivID: String?
    public let authorCredits: [AuthorCreditUpdate]

    public init(
        title: String,
        publicationYear: Int?,
        doi: String?,
        arxivID: String?,
        authorCredits: [AuthorCreditUpdate]
    ) {
        self.title = title
        self.publicationYear = publicationYear
        self.doi = doi
        self.arxivID = arxivID
        self.authorCredits = authorCredits
    }
}

public struct PaperInfoChange: Equatable, Sendable {
    public let before: PaperInfoSnapshot
    public let after: PaperInfoSnapshot

    public init(before: PaperInfoSnapshot, after: PaperInfoSnapshot) {
        self.before = before
        self.after = after
    }
}
