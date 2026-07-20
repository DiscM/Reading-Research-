import Foundation
import SwiftData

public struct CollectionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let dateCreated: Date
    public let documentIDs: [UUID]

    public init(
        id: UUID,
        name: String,
        dateCreated: Date,
        documentIDs: [UUID]
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.documentIDs = documentIDs
    }
}

@Model
public final class Collection {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var dateCreated: Date
    public var documents: [Document]

    public init(
        id: UUID = UUID(),
        name: String,
        dateCreated: Date = .now,
        documents: [Document] = []
    ) {
        self.id = id
        self.name = name
        self.dateCreated = dateCreated
        self.documents = documents
    }
}
