import Foundation
import SwiftData

public enum CanopySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Paper.self, AuthorCredit.self, Annotation.self]
    }
}

public enum CanopyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CanopySchemaV1.self]
    }

    public static var stages: [MigrationStage] { [] }
}

public enum CanopyModelContainer {
    public static var defaultStoreURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Canopy", isDirectory: true)
            .appendingPathComponent("CanopyV1.store")
    }

    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            try FileManager.default.createDirectory(
                at: defaultStoreURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(url: defaultStoreURL)
        }
        return try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
    }
}
