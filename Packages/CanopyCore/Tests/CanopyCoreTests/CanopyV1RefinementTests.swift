import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("Canopy v1 refined core contract")
struct CanopyV1RefinementTests {
    @MainActor
    @Test("annotation activity ignores color and anchor adjustments but includes note edits")
    func annotationActivitySemantics() throws {
        let repository = LibraryRepository(container: try CanopyModelContainer.make(inMemory: true))
        let paperID = UUID()
        try repository.insert(Paper(
            id: paperID,
            fingerprint: Data(repeating: 41, count: 32),
            title: "Activity Semantics",
            storageMode: .managedCopy,
            sourceFilename: "activity.pdf",
            sourceFileSize: 2_048,
            pageCount: 3,
            hasSelectableText: true
        ))
        let originalAnchor = TextAnnotationAnchor(
            pageIndex: 0,
            quadrilaterals: [quadrilateral(top: 180, bottom: 160)],
            selectedText: "Original selection"
        )
        let annotation = try repository.createTextAnnotation(
            paperID: paperID,
            anchor: originalAnchor,
            color: .yellow
        )
        let activityDate = Date(timeIntervalSince1970: 1_000)
        annotation.createdAt = activityDate
        annotation.updatedAt = activityDate
        try repository.save()

        try repository.updateAnnotationColor(
            annotationID: annotation.id,
            color: .purple
        )
        let adjustedAnchor = TextAnnotationAnchor(
            pageIndex: 0,
            quadrilaterals: [quadrilateral(top: 140, bottom: 120)],
            selectedText: "Adjusted selection"
        )
        try repository.updateTextAnnotationAnchor(
            annotationID: annotation.id,
            anchor: adjustedAnchor
        )

        let adjusted = try #require(
            try repository.annotations(paperID: paperID).first(where: { $0.id == annotation.id })
        )
        #expect(adjusted.color == .purple)
        #expect(adjusted.textAnchor == adjustedAnchor)
        #expect(adjusted.updatedAt == activityDate)

        try repository.updateAnnotationNote(
            annotationID: annotation.id,
            note: "A useful note",
            at: Date(timeIntervalSince1970: 3_000)
        )
        #expect(adjusted.updatedAt == Date(timeIntervalSince1970: 3_000))
    }

    @MainActor
    @Test("recent activity orders note edits and creations newest first")
    func recentAnnotationActivityOrdering() throws {
        let repository = LibraryRepository(container: try CanopyModelContainer.make(inMemory: true))
        let paperID = UUID()
        try repository.insert(Paper(
            id: paperID,
            fingerprint: Data(repeating: 42, count: 32),
            title: "Recent Activity",
            storageMode: .managedCopy,
            sourceFilename: "recent.pdf",
            sourceFileSize: 2_048,
            pageCount: 3
        ))
        let first = try repository.createAreaAnnotation(
            paperID: paperID,
            anchor: AreaAnnotationAnchor(
                pageIndex: 0,
                rect: AnnotationRect(x: 10, y: 10, width: 40, height: 40)
            ),
            color: .yellow
        )
        let second = try repository.createAreaAnnotation(
            paperID: paperID,
            anchor: AreaAnnotationAnchor(
                pageIndex: 1,
                rect: AnnotationRect(x: 20, y: 20, width: 40, height: 40)
            ),
            color: .blue
        )
        first.createdAt = Date(timeIntervalSince1970: 100)
        first.updatedAt = Date(timeIntervalSince1970: 300)
        second.createdAt = Date(timeIntervalSince1970: 200)
        second.updatedAt = Date(timeIntervalSince1970: 200)
        try repository.save()

        #expect(Annotation.sortedByRecentActivity([second, first]).map(\.id) == [first.id, second.id])
    }

    @MainActor
    @Test("storage-mode conversion preserves the Paper and its annotations")
    func storageModeConversionPreservesPaperWork() throws {
        let repository = LibraryRepository(container: try CanopyModelContainer.make(inMemory: true))
        let paperID = UUID()
        let fingerprint = Data(repeating: 43, count: 32)
        try repository.insert(Paper(
            id: paperID,
            fingerprint: fingerprint,
            title: "Storage Conversion",
            storageMode: .referenced,
            bookmarkData: Data([1, 2, 3]),
            sourceFilename: "source.pdf",
            rememberedLocation: "/Research/source.pdf",
            sourceFileSize: 2_048,
            sourceModificationDate: Date(timeIntervalSince1970: 100),
            pageCount: 2
        ))
        let annotation = try repository.createAreaAnnotation(
            paperID: paperID,
            anchor: AreaAnnotationAnchor(
                pageIndex: 0,
                rect: AnnotationRect(x: 10, y: 20, width: 80, height: 60)
            ),
            color: .green,
            note: "Preserve this"
        )

        try repository.convertReferencedPaperToManagedCopy(
            paperID: paperID,
            expectedFingerprint: fingerprint,
            managedRelativePath: "\(paperID.uuidString).pdf",
            fileSize: 2_048,
            modificationDate: Date(timeIntervalSince1970: 200)
        )
        let managed = try #require(try repository.paper(id: paperID))
        #expect(managed.storageMode == .managedCopy)
        #expect(managed.bookmarkData == nil)
        #expect(managed.rememberedLocation == nil)
        #expect(managed.managedRelativePath == "\(paperID.uuidString).pdf")
        #expect(try repository.annotations(paperID: paperID).map(\.id) == [annotation.id])

        try repository.convertManagedPaperToReferenced(
            paperID: paperID,
            expectedFingerprint: fingerprint,
            bookmarkData: Data([9, 8, 7]),
            rememberedLocation: "/Archive/source.pdf",
            sourceFilename: "source.pdf",
            fileSize: 2_048,
            modificationDate: Date(timeIntervalSince1970: 300)
        )
        let referenced = try #require(try repository.paper(id: paperID))
        #expect(referenced.storageMode == .referenced)
        #expect(referenced.bookmarkData == Data([9, 8, 7]))
        #expect(referenced.managedRelativePath == nil)
        #expect(referenced.rememberedLocation == "/Archive/source.pdf")
        #expect(try repository.annotations(paperID: paperID).first?.note == "Preserve this")
    }

    @Test("managed storage verifies conversion copies before publishing them")
    func managedStorageVerifiesConversionCopy() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = directory.appendingPathComponent("Managed", isDirectory: true)
        let source = directory.appendingPathComponent("source.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("verified-pdf-bytes".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ManagedPaperStore(rootURL: root)
        let paperID = UUID()
        let fingerprint = try DocumentFingerprint.sha256(of: source)

        let relativePath = try store.copyVerified(
            source,
            paperID: paperID,
            expectedFingerprint: fingerprint
        )
        #expect(relativePath == "\(paperID.uuidString).pdf")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path))

        let rejectedID = UUID()
        #expect(throws: PaperFileAccessError.contentIdentityMismatch) {
            _ = try store.copyVerified(
                source,
                paperID: rejectedID,
                expectedFingerprint: Data(repeating: 0, count: 32)
            )
        }
        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent("\(rejectedID.uuidString).pdf").path
        ))
    }

    @Test("prepared file transfer restores an existing destination when rolled back")
    func preparedFileTransferRollback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = directory.appendingPathComponent("source.pdf")
        let destination = directory.appendingPathComponent("destination.pdf")
        let sourceData = Data("new-source".utf8)
        let existingData = Data("existing-destination".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try sourceData.write(to: source)
        try existingData.write(to: destination)
        defer { try? FileManager.default.removeItem(at: directory) }

        let prepared = try PaperFileTransfer().prepareVerifiedCopy(
            from: source,
            to: destination,
            expectedFingerprint: DocumentFingerprint.sha256(of: source)
        )
        #expect(try Data(contentsOf: destination) == existingData)

        _ = try prepared.publish()
        #expect(try Data(contentsOf: destination) == sourceData)

        try prepared.rollback()
        #expect(try Data(contentsOf: destination) == existingData)
    }

    @Test("area adjustment geometry clamps moves and resizes to one page")
    func areaAdjustmentGeometry() {
        let page = AnnotationRect(x: 0, y: 0, width: 200, height: 300)
        let start = AnnotationRect(x: 20, y: 30, width: 80, height: 60)

        #expect(AreaAnnotationGeometry.adjustedRect(
            start,
            handle: .move,
            pagePoint: AnnotationPoint(x: 0, y: 0),
            delta: AnnotationPoint(x: 500, y: -500),
            pageBounds: page
        ) == AnnotationRect(x: 120, y: 0, width: 80, height: 60))

        #expect(AreaAnnotationGeometry.adjustedRect(
            start,
            handle: .topRight,
            pagePoint: AnnotationPoint(x: 400, y: 500),
            delta: AnnotationPoint(x: 0, y: 0),
            pageBounds: page
        ) == AnnotationRect(x: 20, y: 30, width: 180, height: 270))

        #expect(AreaAnnotationGeometry.adjustedRect(
            start,
            handle: .bottomLeft,
            pagePoint: AnnotationPoint(x: 98, y: 88),
            delta: AnnotationPoint(x: 0, y: 0),
            pageBounds: page
        ) == AnnotationRect(x: 92, y: 82, width: 8, height: 8))
    }

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
            textAnnotation.createdAt = Date(timeIntervalSince1970: 1_500)
            textAnnotation.updatedAt = Date(timeIntervalSince1970: 1_500)
            try repository.save()
            try repository.updateAnnotationColor(
                annotationID: textAnnotationID,
                color: .purple
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
            #expect(textAnnotation.updatedAt == Date(timeIntervalSince1970: 1_500))

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

    @Test("the unreleased research-only draft store is replaced by the workspace v1 store")
    func explicitV1StoreURL() {
        #expect(CanopyModelContainer.defaultStoreURL.lastPathComponent == "CanopyWorkspaceV1.store")
        #expect(CanopyModelContainer.defaultStoreURL.deletingLastPathComponent().lastPathComponent == "Canopy")
    }
}

private func quadrilateral(top: Double, bottom: Double) -> AnnotationQuadrilateral {
    AnnotationQuadrilateral(
        upperLeft: AnnotationPoint(x: 20, y: top),
        upperRight: AnnotationPoint(x: 220, y: top),
        lowerLeft: AnnotationPoint(x: 20, y: bottom),
        lowerRight: AnnotationPoint(x: 220, y: bottom)
    )
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
