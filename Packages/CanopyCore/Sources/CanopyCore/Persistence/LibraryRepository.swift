import Foundation
import SwiftData

@MainActor
public final class LibraryRepository {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
        context.autosaveEnabled = false
    }

    public func insert(_ paper: Paper) throws {
        context.insert(paper)
        try context.save()
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    public func remove(_ paper: Paper) throws {
        context.delete(paper)
        try context.save()
    }

    public func clearRecentHistory() throws {
        let descriptor = FetchDescriptor<Paper>()
        for paper in try context.fetch(descriptor) {
            paper.lastOpenedAt = nil
        }
        try save()
    }
}

