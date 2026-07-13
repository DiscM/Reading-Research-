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
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
    }
}
