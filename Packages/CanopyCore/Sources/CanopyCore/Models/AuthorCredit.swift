import Foundation
import SwiftData

@Model
public final class CreatorCredit {
    @Attribute(.unique) public var id: UUID
    public var position: Int
    public var displayName: String
    public var familyName: String
    public var provenanceRawValue: String
    public var paper: Document?

    public var document: Document? {
        get { paper }
        set { paper = newValue }
    }

    public var provenance: MetadataProvenance {
        get { MetadataProvenance(rawValue: provenanceRawValue) ?? .firstPage }
        set { provenanceRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        position: Int,
        displayName: String,
        familyName: String,
        provenance: MetadataProvenance,
        document: Document? = nil
    ) {
        self.id = id
        self.position = position
        self.displayName = displayName
        self.familyName = familyName
        self.provenanceRawValue = provenance.rawValue
        self.paper = document
    }

    public convenience init(
        id: UUID = UUID(),
        position: Int,
        displayName: String,
        familyName: String,
        provenance: MetadataProvenance,
        paper: Document
    ) {
        self.init(
            id: id,
            position: position,
            displayName: displayName,
            familyName: familyName,
            provenance: provenance,
            document: paper
        )
    }
}

public typealias AuthorCredit = CreatorCredit
