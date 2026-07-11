import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("Canopy core persistence")
struct CanopyCoreTests {
    @Test("rejects identifier-shaped titles")
    func rejectsIdentifierTitles() {
        #expect(MetadataValidator.usableTitle("arXiv: 2401.12345") == nil)
        #expect(MetadataValidator.usableTitle("10.1000/example") == nil)
        #expect(MetadataValidator.usableTitle("A Useful Research Title") == "A Useful Research Title")
    }

    @MainActor
    @Test("paper round-trips through a reopened store")
    func paperRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Canopy.store")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: Schema(versionedSchema: CanopySchemaV1.self),
                migrationPlan: CanopyMigrationPlan.self,
                configurations: configuration
            )
            let repository = LibraryRepository(container: container)
            let paper = Paper(
                fingerprint: Data(repeating: 7, count: 32),
                title: "Persistent Paper",
                storageMode: .referenced,
                sourceFilename: "paper.pdf",
                sourceFileSize: 42
            )
            try repository.insert(paper)
        }

        let configuration = ModelConfiguration(url: storeURL)
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
        let papers = try reopened.mainContext.fetch(FetchDescriptor<Paper>())
        #expect(papers.map(\.title) == ["Persistent Paper"])
    }
}
