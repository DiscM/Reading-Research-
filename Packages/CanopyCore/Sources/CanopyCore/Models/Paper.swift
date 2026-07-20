import Foundation
import SwiftData

public enum DocumentStorageMode: String, Codable, Sendable {
    case referenced
    case managedCopy
}

public typealias PaperStorageMode = DocumentStorageMode

public enum DocumentSourceState: String, Codable, Sendable, Equatable {
    case available
    case sourceUnavailable
    case brokenReference
    case sourceChanged
    case libraryCopyMissing
}

public typealias PaperSourceState = DocumentSourceState

public enum MetadataProvenance: String, Codable, Sendable {
    case embeddedMetadata
    case firstPage
    case filenameFallback
    case userEntry
}

public enum DocumentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case generalDocument
    case researchPaper
    case lectureSlides
    case classNotes
    case textbook
    case handout

    public var id: Self { self }

    public var displayName: String {
        switch self {
        case .generalDocument: "General Document"
        case .researchPaper: "Research Paper"
        case .lectureSlides: "Lecture Slides"
        case .classNotes: "Class Notes"
        case .textbook: "Textbook"
        case .handout: "Handout"
        }
    }

    public var systemImage: String {
        switch self {
        case .generalDocument: "doc.text"
        case .researchPaper: "doc.text.magnifyingglass"
        case .lectureSlides: "rectangle.on.rectangle.angled"
        case .classNotes: "note.text"
        case .textbook: "book.closed"
        case .handout: "doc.on.doc"
        }
    }

    public var creatorLabel: String {
        switch self {
        case .lectureSlides: "Presented by"
        case .classNotes: "Created by"
        case .generalDocument, .researchPaper, .textbook, .handout: "Authors"
        }
    }

    public var dateLabel: String {
        switch self {
        case .researchPaper, .textbook: "Publication Date"
        case .lectureSlides: "Presentation Date"
        case .classNotes: "Note Date"
        case .generalDocument, .handout: "Document Date"
        }
    }
}

public enum DocumentDatePrecision: String, CaseIterable, Codable, Sendable {
    case year
    case month
    case day
}

public struct DocumentDate: Codable, Equatable, Sendable {
    public let year: Int
    public let month: Int?
    public let day: Int?

    public var precision: DocumentDatePrecision {
        if day != nil { return .day }
        if month != nil { return .month }
        return .year
    }

    public init?(year: Int, month: Int? = nil, day: Int? = nil) {
        guard (1 ... 9_999).contains(year),
              day == nil || month != nil else {
            return nil
        }
        if let month {
            guard (1 ... 12).contains(month) else { return nil }
            if let day {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let components = DateComponents(
                    calendar: calendar,
                    timeZone: calendar.timeZone,
                    year: year,
                    month: month,
                    day: day
                )
                guard let date = calendar.date(from: components),
                      calendar.dateComponents([.year, .month, .day], from: date).year == year,
                      calendar.dateComponents([.year, .month, .day], from: date).month == month,
                      calendar.dateComponents([.year, .month, .day], from: date).day == day else {
                    return nil
                }
            }
        }
        self.year = year
        self.month = month
        self.day = day
    }
}

@Model
public final class Document {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var fingerprint: Data
    public var title: String
    public var titleProvenanceRawValue: String
    public var publicationYearProvenanceRawValue: String?
    public var doi: String?
    public var doiProvenanceRawValue: String?
    public var arxivID: String?
    public var arxivIDProvenanceRawValue: String?
    public var kindRawValue: String
    public var documentDateYear: Int?
    public var documentDateMonth: Int?
    public var documentDateDay: Int?
    public var documentDatePrecisionRawValue: String?
    public var documentNote: String
    public var storageModeRawValue: String
    public var sourceStateRawValue: String
    public var bookmarkData: Data?
    public var managedRelativePath: String?
    public var sourceFilename: String
    public var rememberedLocation: String?
    public var sourceFileSize: Int64
    public var sourceModificationDate: Date?
    public var pageCount: Int
    public var hasSelectableText: Bool
    public var dateAdded: Date
    public var lastOpenedAt: Date?
    public var lastPageIndex: Int?
    public var lastViewport: Data?
    public var lastZoomScale: Double?
    public var isInspectorPresented: Bool

    @Relationship(deleteRule: .cascade, inverse: \Annotation.paper)
    public var annotations: [Annotation]

    @Relationship(deleteRule: .cascade, inverse: \CreatorCredit.paper)
    public var creatorCredits: [CreatorCredit]

    @Relationship(deleteRule: .nullify, inverse: \Collection.documents)
    public var collections: [Collection]

    public var titleProvenance: MetadataProvenance {
        get { MetadataProvenance(rawValue: titleProvenanceRawValue) ?? .filenameFallback }
        set { titleProvenanceRawValue = newValue.rawValue }
    }

    public var publicationYear: Int? {
        get { documentDateYear }
        set {
            documentDateYear = newValue
            documentDateMonth = nil
            documentDateDay = nil
            documentDatePrecisionRawValue = newValue == nil ? nil : DocumentDatePrecision.year.rawValue
        }
    }

    public var publicationYearProvenance: MetadataProvenance? {
        get { publicationYearProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { publicationYearProvenanceRawValue = newValue?.rawValue }
    }

    public var documentDateProvenance: MetadataProvenance? {
        get { publicationYearProvenance }
        set { publicationYearProvenance = newValue }
    }

    public var doiProvenance: MetadataProvenance? {
        get { doiProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { doiProvenanceRawValue = newValue?.rawValue }
    }

    public var arxivIDProvenance: MetadataProvenance? {
        get { arxivIDProvenanceRawValue.flatMap(MetadataProvenance.init(rawValue:)) }
        set { arxivIDProvenanceRawValue = newValue?.rawValue }
    }

    public var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRawValue) ?? .generalDocument }
        set { kindRawValue = newValue.rawValue }
    }

    public var documentDate: DocumentDate? {
        get {
            guard let year = documentDateYear,
                  let precisionRawValue = documentDatePrecisionRawValue,
                  let precision = DocumentDatePrecision(rawValue: precisionRawValue) else {
                return nil
            }
            switch precision {
            case .year:
                return DocumentDate(year: year)
            case .month:
                guard let month = documentDateMonth else { return nil }
                return DocumentDate(year: year, month: month)
            case .day:
                guard let month = documentDateMonth, let day = documentDateDay else { return nil }
                return DocumentDate(year: year, month: month, day: day)
            }
        }
        set { setDocumentDate(newValue) }
    }

    public var storageMode: DocumentStorageMode {
        get { DocumentStorageMode(rawValue: storageModeRawValue) ?? .referenced }
        set { storageModeRawValue = newValue.rawValue }
    }

    public var sourceState: DocumentSourceState {
        get { DocumentSourceState(rawValue: sourceStateRawValue) ?? .available }
        set { sourceStateRawValue = newValue.rawValue }
    }

    public var isInProgress: Bool { lastPageIndex != nil }

    public var creatorsDisplayText: String {
        creatorCredits
            .sorted { $0.position < $1.position }
            .map(\.displayName)
            .joined(separator: ", ")
    }

    public var authorsDisplayText: String { creatorsDisplayText }

    public var authorCredits: [CreatorCredit] {
        get { creatorCredits }
        set { creatorCredits = newValue }
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
        kind: DocumentKind = .generalDocument,
        documentDate: DocumentDate? = nil,
        documentNote: String = "",
        storageMode: DocumentStorageMode,
        sourceState: DocumentSourceState = .available,
        bookmarkData: Data? = nil,
        managedRelativePath: String? = nil,
        sourceFilename: String,
        rememberedLocation: String? = nil,
        sourceFileSize: Int64,
        sourceModificationDate: Date? = nil,
        pageCount: Int = 0,
        hasSelectableText: Bool = false,
        dateAdded: Date = .now,
        authorCredits: [CreatorCredit] = []
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.titleProvenanceRawValue = titleProvenance.rawValue
        self.publicationYearProvenanceRawValue = publicationYearProvenance?.rawValue
        self.doi = doi
        self.doiProvenanceRawValue = doiProvenance?.rawValue
        self.arxivID = arxivID
        self.arxivIDProvenanceRawValue = arxivIDProvenance?.rawValue
        self.kindRawValue = kind.rawValue
        self.documentDateYear = nil
        self.documentDateMonth = nil
        self.documentDateDay = nil
        self.documentDatePrecisionRawValue = nil
        self.documentNote = documentNote
        self.storageModeRawValue = storageMode.rawValue
        self.sourceStateRawValue = sourceState.rawValue
        self.bookmarkData = bookmarkData
        self.managedRelativePath = managedRelativePath
        self.sourceFilename = sourceFilename
        self.rememberedLocation = rememberedLocation
        self.sourceFileSize = sourceFileSize
        self.sourceModificationDate = sourceModificationDate
        self.pageCount = pageCount
        self.hasSelectableText = hasSelectableText
        self.dateAdded = dateAdded
        self.lastOpenedAt = nil
        self.lastPageIndex = nil
        self.lastViewport = nil
        self.lastZoomScale = nil
        self.isInspectorPresented = true
        self.annotations = []
        self.creatorCredits = authorCredits
        self.collections = []
        setDocumentDate(documentDate ?? publicationYear.flatMap { DocumentDate(year: $0) })
        for credit in authorCredits {
            credit.paper = self
        }
    }

    private func setDocumentDate(_ documentDate: DocumentDate?) {
        documentDateYear = documentDate?.year
        documentDateMonth = documentDate?.month
        documentDateDay = documentDate?.day
        documentDatePrecisionRawValue = documentDate?.precision.rawValue
    }
}

public typealias Paper = Document
