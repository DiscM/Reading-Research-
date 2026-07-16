import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("Canopy v1 refined core contract")
struct CanopyV1RefinementTests {
    @MainActor
    @Test("text and area annotations plus selectable-text capability survive a real-store reopen")
    func annotationKindsAndPaperCapabilityRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Canopy.store")
        let paperID = UUID()
        let textAnnotationID: UUID
        let areaAnnotationID: UUID

        let textAnchor = TextAnnotationAnchor(
            pageIndex: 1,
            quadrilaterals: [
                AnnotationQuadrilateral(
                    upperLeft: AnnotationPoint(x: 20, y: 180),
                    upperRight: AnnotationPoint(x: 220, y: 180),
                    lowerLeft: AnnotationPoint(x: 20, y: 160),
                    lowerRight: AnnotationPoint(x: 220, y: 160)
                )
            ],
            selectedText: "A result worth keeping"
        )
        let areaAnchor = AreaAnnotationAnchor(
            pageIndex: 2,
            rect: AnnotationRect(x: 40, y: 80, width: 240, height: 160)
        )

        do {
            let repository = LibraryRepository(container: try persistentContainer(at: storeURL))
            try repository.insert(Paper(
                id: paperID,
                fingerprint: Data(repeating: 31, count: 32),
                title: "Mixed Annotation Paper",
                storageMode: .managedCopy,
                sourceFilename: "mixed.pdf",
                sourceFileSize: 4_096,
                pageCount: 4,
                hasSelectableText: true
            ))
            let textAnnotation = try repository.createTextAnnotation(
                paperID: paperID,
                anchor: textAnchor,
                color: .yellow,
                note: "Text note"
            )
            let areaAnnotation = try repository.createAreaAnnotation(
                paperID: paperID,
                anchor: areaAnchor,
                color: .blue,
                note: "Figure note"
            )
            textAnnotationID = textAnnotation.id
            areaAnnotationID = areaAnnotation.id
            try repository.updateAnnotationColor(
                annotationID: textAnnotationID,
                color: .purple,
                at: Date(timeIntervalSince1970: 2_000)
            )
        }

        do {
            let repository = LibraryRepository(container: try persistentContainer(at: storeURL))
            let paper = try #require(try repository.paper(id: paperID))
            #expect(paper.hasSelectableText)

            let annotations = try repository.annotations(paperID: paperID)
            let byID = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })
            let textAnnotation = try #require(byID[textAnnotationID])
            #expect(textAnnotation.kind == .textHighlight)
            #expect(textAnnotation.textAnchor == textAnchor)
            #expect(textAnnotation.areaAnchor == nil)
            #expect(textAnnotation.color == .purple)
            #expect(textAnnotation.note == "Text note")
            #expect(textAnnotation.updatedAt == Date(timeIntervalSince1970: 2_000))

            let areaAnnotation = try #require(byID[areaAnnotationID])
            #expect(areaAnnotation.kind == .area)
            #expect(areaAnnotation.textAnchor == nil)
            #expect(areaAnnotation.areaAnchor == areaAnchor)
            #expect(areaAnnotation.color == .blue)
            #expect(areaAnnotation.note == "Figure note")

            try repository.updateAnnotationNote(
                annotationID: areaAnnotationID,
                note: "Edited figure note",
                at: Date(timeIntervalSince1970: 3_000)
            )
            let snapshot = try repository.deleteAnnotation(annotationID: areaAnnotationID)
            #expect(snapshot.kind == .area)
            #expect(snapshot.areaAnchor == areaAnchor)
            let restored = try repository.restoreAnnotation(snapshot)
            #expect(restored.areaAnchor == areaAnchor)
            #expect(restored.note == "Edited figure note")
        }

        let repository = LibraryRepository(container: try persistentContainer(at: storeURL))
        let restoredArea = try #require(
            try repository.annotations(paperID: paperID).first(where: { $0.id == areaAnnotationID })
        )
        #expect(restoredArea.kind == .area)
        #expect(restoredArea.areaAnchor == areaAnchor)
        #expect(restoredArea.note == "Edited figure note")
    }

    @Test("cancelling Preflight during fingerprinting stops before document analysis")
    func preflightCancellationStopsReadOnlyWork() async throws {
        let fixture = try CancellationFixture(byteCount: 4 * 1_024 * 1_024)
        defer { fixture.remove() }
        let analyzer = AnalysisCallRecorder()

        let task = Task.detached {
            try AddBatchPreflight(analyzer: analyzer).run(
                urls: [fixture.url],
                existingPapers: [],
                progress: { _ in
                    withUnsafeCurrentTask { task in
                        task?.cancel()
                    }
                }
            )
        }

        do {
            _ = try await task.value
            Issue.record("Preflight completed after its task was cancelled")
        } catch is CancellationError {
            // Cancellation is the public result, rather than a per-file failure.
        }
        #expect(analyzer.callCount == 0)
    }

    @Test("Preflight distinguishes missing and inaccessible selected PDFs")
    func preflightInputFailuresAreSpecific() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("missing.pdf")
        let inaccessibleURL = directory.appendingPathComponent("not-a-file.pdf", isDirectory: true)
        try FileManager.default.createDirectory(at: inaccessibleURL, withIntermediateDirectories: true)
        let analyzer = AnalysisCallRecorder()

        let result = try AddBatchPreflight(analyzer: analyzer).run(
            urls: [missingURL, inaccessibleURL],
            existingPapers: []
        )

        #expect(result.failures.map(\.message) == [
            AddBatchPreflightInputError.missing.localizedDescription,
            AddBatchPreflightInputError.inaccessible.localizedDescription
        ])
        #expect(analyzer.callCount == 0)
    }

    @Test("the unreleased draft store is replaced by an explicitly named v1 store")
    func explicitV1StoreURL() {
        #expect(CanopyModelContainer.defaultStoreURL.lastPathComponent == "CanopyV1.store")
        #expect(CanopyModelContainer.defaultStoreURL.deletingLastPathComponent().lastPathComponent == "Canopy")
    }
}

@MainActor
private func persistentContainer(at url: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url)
    return try ModelContainer(
        for: Schema(versionedSchema: CanopySchemaV1.self),
        migrationPlan: CanopyMigrationPlan.self,
        configurations: configuration
    )
}

private final class AnalysisCallRecorder: DocumentAnalyzing, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        lock.withLock { calls += 1 }
        return ParsedPaperMetadata(
            title: "Should Not Be Parsed",
            titleProvenance: .firstPage,
            pageCount: 1,
            hasSelectableText: true
        )
    }
}

private struct CancellationFixture: Sendable {
    let directory: URL
    let url: URL

    init(byteCount: Int) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("large.pdf")
        try Data(repeating: 7, count: byteCount).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
