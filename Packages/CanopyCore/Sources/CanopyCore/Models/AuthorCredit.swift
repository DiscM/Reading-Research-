import Foundation
import SwiftData

@Model
public final class AuthorCredit {
    @Attribute(.unique) public var id: UUID
    public var position: Int
    public var displayName: String
    public var familyName: String
    public var provenanceRawValue: String
    public var paper: Paper?

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
        paper: Paper? = nil
    ) {
        self.id = id
        self.position = position
        self.displayName = displayName
        self.familyName = familyName
        self.provenanceRawValue = provenance.rawValue
        self.paper = paper
    }
}

