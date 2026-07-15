import Foundation
import SwiftData

public enum PaperStorageMode: String, Codable, Sendable {
    case referenced
    case managedCopy
}

public enum PaperSourceState: String, Codable, Sendable, Equatable {
    case available
    case sourceUnavailable
    case brokenReference
    case sourceChanged
    case libraryCopyMissing
}

public enum MetadataProvenance: String, Codable, Sendable {
    case embeddedMetadata
    case firstPage
    case filenameFallback
    case userEntry
}

@Model
public final class Paper {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var fingerprint: Data
    public var title: String
    public var titleProvenanceRawValue: String
    public var publicationYear: Int?
    public var publicationYearProvenanceRawValue: String?
    public var doi: String?
    public var doiProvenanceRawValue: String?
    public var arxivID: String?
    public var arxivIDProvenanceRawValue: String?
    public var storageModeRawValue: String
    public var sourceStateRawValue: String
    public var bookmarkData: Data?
    public var managedRelativePath: String?
    public var sourceFilename: String
    public var rememberedLocation: String?
    public var sourceFileSize: Int64
    public var sourceModificationDate: Date?
    public var pageCount: Int
    public var embeddedCreationDate: Date?
    public var embeddedModificationDate: Date?
    public var dateAdded: Date
    public var lastOpenedAt: Date?
    public var lastPageIndex: Int?
    public var lastViewport: Data?
    public var lastZoomScale: Double?
    public var isInspectorPresented: Bool

    @Relationship(deleteRule: .cascade, inverse: \Annotation.paper)
    public var annotations: [Annotation]

    @Relationship(deleteRule: .cascade, inverse: \AuthorCredit.paper)
    public var authorCredits: [AuthorCredit]

    public var titleProvenance: MetadataProvenance {
        get { MetadataProvenance(rawValue: titleProvenanceRawValue) ?? .filenameFallback }
        set { titleProvenanceRawValue = newValue.rawValue }
    }

    public var publicationYearProvenance: MetadataProvenance? {
        get { publicationYearProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { publicationYearProvenanceRawValue = newValue?.rawValue }
    }

    public var doiProvenance: MetadataProvenance? {
        get { doiProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { doiProvenanceRawValue = newValue?.rawValue }
    }

    public var arxivIDProvenance: MetadataProvenance? {
        get { arxivIDProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { arxivIDProvenanceRawValue = newValue?.rawValue }
    }

    public var storageMode: PaperStorageMode {
        get { PaperStorageMode(rawValue: storageModeRawValue) ?? .referenced }
        set { storageModeRawValue = newValue.rawValue }
    }

    public var sourceState: PaperSourceState {
        get { PaperSourceState(rawValue: sourceStateRawValue) ?? .available }
        set { sourceStateRawValue = newValue.rawValue }
    }

    public var isInProgress: Bool { lastPageIndex != nil }

    public var authorsDisplayText: String {
        authorCredits
            .sorted { $0.position < $1.position }
            .map(\.displayName)
            .joined(separator: ", ")
    }

    public init(
        id: UUID = UUID(),
        fingerprint: Data,
        title: String,
        titleProvenance: MetadataProvenance = .filenameFallback,
        publicationYear: Int? = nil,
        publicationYearProvenance: MetadataProvenance? = nil,
        doi: String? = nil,
        doiProvenance: MetadataProvenance? = nil,
        arxivID: String? = nil,
        arxivIDProvenance: MetadataProvenance? = nil,
        storageMode: PaperStorageMode,
        sourceState: PaperSourceState = .available,
        bookmarkData: Data? = nil,
        managedRelativePath: String? = nil,
        sourceFilename: String,
        rememberedLocation: String? = nil,
        sourceFileSize: Int64,
        sourceModificationDate: Date? = nil,
        pageCount: Int = 0,
        embeddedCreationDate: Date? = nil,
        embeddedModificationDate: Date? = nil,
        dateAdded: Date = .now,
        authorCredits: [AuthorCredit] = []
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.titleProvenanceRawValue = titleProvenance.rawValue
        self.publicationYear = publicationYear
        self.publicationYearProvenanceRawValue = publicationYearProvenance?.rawValue
        self.doi = doi
        self.doiProvenanceRawValue = doiProvenance?.rawValue
        self.arxivID = arxivID
        self.arxivIDProvenanceRawValue = arxivIDProvenance?.rawValue
        self.storageModeRawValue = storageMode.rawValue
        self.sourceStateRawValue = sourceState.rawValue
        self.bookmarkData = bookmarkData
        self.managedRelativePath = managedRelativePath
        self.sourceFilename = sourceFilename
        self.rememberedLocation = rememberedLocation
        self.sourceFileSize = sourceFileSize
        self.sourceModificationDate = sourceModificationDate
        self.pageCount = pageCount
        self.embeddedCreationDate = embeddedCreationDate
        self.embeddedModificationDate = embeddedModificationDate
        self.dateAdded = dateAdded
        self.lastOpenedAt = nil
        self.lastPageIndex = nil
        self.lastViewport = nil
        self.lastZoomScale = nil
        self.isInspectorPresented = true
        self.annotations = []
        self.authorCredits = authorCredits
        for credit in authorCredits {
            credit.paper = self
        }
    }
}
