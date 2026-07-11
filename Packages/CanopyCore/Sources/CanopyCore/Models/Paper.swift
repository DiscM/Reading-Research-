import Foundation
import SwiftData

public enum PaperStorageMode: String, Codable, Sendable {
    case referenced
    case managedCopy
}

@Model
public final class Paper {
    @Attribute(.unique) public var id: UUID
    @Attribute(.unique) public var fingerprint: Data
    public var title: String
    public var authors: String
    public var publicationYear: Int?
    public var storageModeRawValue: String
    public var bookmarkData: Data?
    public var managedRelativePath: String?
    public var sourceFilename: String
    public var sourceFileSize: Int64
    public var sourceModificationDate: Date?
    public var dateAdded: Date
    public var lastOpenedAt: Date?
    public var lastPageIndex: Int?
    public var lastViewport: Data?
    public var lastZoomScale: Double?
    public var isInspectorPresented: Bool

    @Relationship(deleteRule: .cascade, inverse: \Annotation.paper)
    public var annotations: [Annotation]

    public var storageMode: PaperStorageMode {
        get { PaperStorageMode(rawValue: storageModeRawValue) ?? .referenced }
        set { storageModeRawValue = newValue.rawValue }
    }

    public var isInProgress: Bool { lastPageIndex != nil }

    public init(
        id: UUID = UUID(),
        fingerprint: Data,
        title: String,
        authors: String = "",
        publicationYear: Int? = nil,
        storageMode: PaperStorageMode,
        bookmarkData: Data? = nil,
        managedRelativePath: String? = nil,
        sourceFilename: String,
        sourceFileSize: Int64,
        sourceModificationDate: Date? = nil,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.authors = authors
        self.publicationYear = publicationYear
        self.storageModeRawValue = storageMode.rawValue
        self.bookmarkData = bookmarkData
        self.managedRelativePath = managedRelativePath
        self.sourceFilename = sourceFilename
        self.sourceFileSize = sourceFileSize
        self.sourceModificationDate = sourceModificationDate
        self.dateAdded = dateAdded
        self.lastOpenedAt = nil
        self.lastPageIndex = nil
        self.lastViewport = nil
        self.lastZoomScale = nil
        self.isInspectorPresented = true
        self.annotations = []
    }
}

