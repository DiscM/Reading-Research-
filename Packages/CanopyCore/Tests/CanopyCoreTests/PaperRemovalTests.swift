import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("Paper removal and restoration")
struct PaperRemovalTests {
    @MainActor
    @Test("a managed Paper can be removed, restored, and removed again without losing its file or work")
    func managedPaperRemovalRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let managedStore = ManagedPaperStore(rootURL: directory)
        let relativePath = "managed-paper.pdf"
        let sourceURL = directory.appendingPathComponent(relativePath)
        let sourceBytes = Data("managed-pdf-bytes".utf8)
        try sourceBytes.write(to: sourceURL)

        let paperID = UUID()
        let firstAuthorID = UUID()
        let secondAuthorID = UUID()
        let textAnnotationID = UUID()
        let areaAnnotationID = UUID()
        let sourceModifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let addedAt = Date(timeIntervalSince1970: 1_680_000_000)
        let openedAt = Date(timeIntervalSince1970: 1_710_000_000)
        let annotationCreatedAt = Date(timeIntervalSince1970: 1_705_000_000)
        let annotationUpdatedAt = Date(timeIntervalSince1970: 1_706_000_000)
        let viewport = PaperViewport(x: 12, y: 34, width: 560, height: 720)
        let anchor = TextAnnotationAnchor(
            pageIndex: 3,
            quadrilaterals: [
                AnnotationQuadrilateral(
                    upperLeft: AnnotationPoint(x: 10, y: 40),
                    upperRight: AnnotationPoint(x: 80, y: 40),
                    lowerLeft: AnnotationPoint(x: 10, y: 20),
                    lowerRight: AnnotationPoint(x: 80, y: 20)
                )
            ],
            selectedText: "A retained finding"
        )
        let areaAnchor = AreaAnnotationAnchor(
            pageIndex: 5,
            rect: AnnotationRect(x: 30, y: 60, width: 180, height: 120)
        )

        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            id: paperID,
            fingerprint: try DocumentFingerprint.sha256(of: sourceURL),
            title: "Restorable Managed Paper",
            titleProvenance: .firstPage,
            publicationYear: 2025,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/restorable",
            doiProvenance: .firstPage,
            arxivID: "2501.12345v2",
            arxivIDProvenance: .embeddedMetadata,
            storageMode: .managedCopy,
            sourceState: .available,
            managedRelativePath: relativePath,
            sourceFilename: "source-name.pdf",
            sourceFileSize: Int64(sourceBytes.count),
            sourceModificationDate: sourceModifiedAt,
            pageCount: 9,
            hasSelectableText: true,
            dateAdded: addedAt,
            authorCredits: [
                AuthorCredit(
                    id: secondAuthorID,
                    position: 1,
                    displayName: "Grace Hopper",
                    familyName: "Hopper",
                    provenance: .userEntry
                ),
                AuthorCredit(
                    id: firstAuthorID,
                    position: 0,
                    displayName: "Ada Lovelace",
                    familyName: "Lovelace",
                    provenance: .firstPage
                )
            ]
        )
        try repository.insert(paper)
        try repository.recordPaperOpened(paperID: paperID, at: openedAt)
        try repository.saveReaderState(
            paperID: paperID,
            state: PaperReaderState(
                pageIndex: 4,
                viewport: viewport,
                zoomScale: 1.75,
                isInspectorPresented: false
            )
        )
        _ = try repository.createTextAnnotations(
            paperID: paperID,
            anchors: [anchor],
            color: .purple,
            note: "Original note"
        ).map { annotation in
            annotation.id = textAnnotationID
            annotation.createdAt = annotationCreatedAt
            annotation.updatedAt = annotationCreatedAt
        }
        let areaAnnotation = try repository.createAreaAnnotation(
            paperID: paperID,
            anchor: areaAnchor,
            color: .green,
            note: "Area note"
        )
        areaAnnotation.id = areaAnnotationID
        areaAnnotation.createdAt = annotationCreatedAt.addingTimeInterval(1)
        areaAnnotation.updatedAt = annotationCreatedAt.addingTimeInterval(1)
        try repository.save()
        try repository.updateAnnotationNote(
            annotationID: textAnnotationID,
            note: "Updated note",
            at: annotationUpdatedAt
        )

        let snapshot = try repository.removePaper(paperID: paperID, managedStore: managedStore)

        #expect(try repository.paper(id: paperID) == nil)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(snapshot.authorCredits.map(\.id) == [firstAuthorID, secondAuthorID])
        #expect(Set(snapshot.annotations.map(\.id)) == [textAnnotationID, areaAnnotationID])

        try repository.restoreRemovedPaper(snapshot: snapshot, managedStore: managedStore)

        let restored = try #require(try repository.paper(id: paperID))
        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
        #expect(restored.fingerprint == snapshot.fingerprint)
        #expect(restored.title == "Restorable Managed Paper")
        #expect(restored.titleProvenance == .firstPage)
        #expect(restored.publicationYear == 2025)
        #expect(restored.publicationYearProvenance == .embeddedMetadata)
        #expect(restored.doi == "10.1000/restorable")
        #expect(restored.doiProvenance == .firstPage)
        #expect(restored.arxivID == "2501.12345v2")
        #expect(restored.arxivIDProvenance == .embeddedMetadata)
        #expect(restored.storageMode == .managedCopy)
        #expect(restored.sourceState == .available)
        #expect(restored.bookmarkData == nil)
        #expect(restored.managedRelativePath == relativePath)
        #expect(restored.sourceFilename == "source-name.pdf")
        #expect(restored.rememberedLocation == nil)
        #expect(restored.sourceFileSize == Int64(sourceBytes.count))
        #expect(restored.sourceModificationDate == sourceModifiedAt)
        #expect(restored.pageCount == 9)
        #expect(restored.hasSelectableText)
        #expect(restored.dateAdded == addedAt)
        #expect(restored.lastOpenedAt == openedAt)
        #expect(try repository.readerState(paperID: paperID) == PaperReaderState(
            pageIndex: 4,
            viewport: viewport,
            zoomScale: 1.75,
            isInspectorPresented: false
        ))
        #expect(restored.authorCredits.sorted { $0.position < $1.position }.map(\.id) == [firstAuthorID, secondAuthorID])
        let restoredAnnotations = Dictionary(
            uniqueKeysWithValues: try repository.annotations(paperID: paperID).map { ($0.id, $0) }
        )
        let restoredTextAnnotation = try #require(restoredAnnotations[textAnnotationID])
        #expect(restoredTextAnnotation.textAnchor == anchor)
        #expect(restoredTextAnnotation.color == .purple)
        #expect(restoredTextAnnotation.note == "Updated note")
        #expect(restoredTextAnnotation.createdAt == annotationCreatedAt)
        #expect(restoredTextAnnotation.updatedAt == annotationUpdatedAt)
        let restoredAreaAnnotation = try #require(restoredAnnotations[areaAnnotationID])
        #expect(restoredAreaAnnotation.areaAnchor == areaAnchor)
        #expect(restoredAreaAnnotation.color == .green)
        #expect(restoredAreaAnnotation.note == "Area note")
        #expect(try regularFiles(in: directory) == [relativePath])

        let redoSnapshot = try repository.removePaper(paperID: paperID, managedStore: managedStore)
        #expect(redoSnapshot == snapshot)
        try repository.restoreRemovedPaper(snapshot: redoSnapshot, managedStore: managedStore)
        #expect(try regularFiles(in: directory) == [relativePath])
    }

    @MainActor
    @Test("a missing managed copy is not invented when its Paper is restored")
    func missingManagedCopyRemovalRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedStore = ManagedPaperStore(rootURL: directory)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 16, count: 32),
            title: "Missing Managed Copy",
            storageMode: .managedCopy,
            sourceState: .libraryCopyMissing,
            managedRelativePath: "missing.pdf",
            sourceFilename: "missing.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)

        let snapshot = try repository.removePaper(paperID: paper.id, managedStore: managedStore)
        #expect(!snapshot.managedCopyWasStaged)

        try repository.restoreRemovedPaper(snapshot: snapshot, managedStore: managedStore)

        let restored = try #require(try repository.paper(id: paper.id))
        #expect(restored.sourceState == .libraryCopyMissing)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("missing.pdf").path))
    }

    @MainActor
    @Test("launch recovery restores staged bytes only when their Paper still exists")
    func launchRecoveryReconcilesCommittedState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedStore = ManagedPaperStore(rootURL: directory)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 17, count: 32),
            title: "Interrupted Removal",
            storageMode: .managedCopy,
            managedRelativePath: "interrupted.pdf",
            sourceFilename: "interrupted.pdf",
            sourceFileSize: 10
        )
        try repository.insert(paper)
        let sourceURL = directory.appendingPathComponent("interrupted.pdf")
        try Data("interrupted".utf8).write(to: sourceURL)
        try managedStore.stageForRecovery(relativePath: "interrupted.pdf", paperID: paper.id)

        try repository.reconcileManagedPaperRecovery(managedStore: managedStore)

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try regularFiles(in: directory) == ["interrupted.pdf"])

        _ = try repository.removePaper(paperID: paper.id, managedStore: managedStore)
        try repository.reconcileManagedPaperRecovery(managedStore: managedStore)

        #expect(try repository.paper(id: paper.id) == nil)
        #expect(try regularFiles(in: directory).isEmpty)
    }

    @MainActor
    @Test("batch removal deletes every requested Document in one repository transaction")
    func batchRemovalSucceedsAtomically() throws {
        let repository = LibraryRepository(container: try CanopyModelContainer.make(inMemory: true))
        let first = Document(
            fingerprint: Data(repeating: 31, count: 32),
            title: "First Document",
            storageMode: .referenced,
            bookmarkData: Data([1]),
            sourceFilename: "first.pdf",
            sourceFileSize: 1
        )
        let second = Document(
            fingerprint: Data(repeating: 32, count: 32),
            title: "Second Document",
            storageMode: .referenced,
            bookmarkData: Data([2]),
            sourceFilename: "second.pdf",
            sourceFileSize: 1
        )
        try repository.insert(first)
        try repository.insert(second)

        let snapshots = try repository.removeDocuments(
            documentIDs: [second.id, first.id, second.id]
        )

        #expect(snapshots.map(\.id) == [second.id, first.id])
        #expect(try repository.paper(id: first.id) == nil)
        #expect(try repository.paper(id: second.id) == nil)
    }

    @MainActor
    @Test("a failed batch database deletion restores every managed copy and Document")
    func batchRemovalSaveFailureIsAtomic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Canopy.store")
        let managedDirectory = directory.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedStore = ManagedPaperStore(rootURL: managedDirectory)
        let firstSourceURL = managedDirectory.appendingPathComponent("first.pdf")
        let secondSourceURL = managedDirectory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: firstSourceURL)
        try Data("second".utf8).write(to: secondSourceURL)
        let firstID = UUID()
        let secondID = UUID()

        do {
            let repository = LibraryRepository(
                container: try persistentContainer(url: storeURL, allowsSave: true)
            )
            try repository.insert(Document(
                id: firstID,
                fingerprint: Data(repeating: 33, count: 32),
                title: "First Atomic Document",
                storageMode: .managedCopy,
                managedRelativePath: "first.pdf",
                sourceFilename: "first.pdf",
                sourceFileSize: 5
            ))
            try repository.insert(Document(
                id: secondID,
                fingerprint: Data(repeating: 34, count: 32),
                title: "Second Atomic Document",
                storageMode: .managedCopy,
                managedRelativePath: "second.pdf",
                sourceFilename: "second.pdf",
                sourceFileSize: 6
            ))
        }

        do {
            let repository = LibraryRepository(
                container: try persistentContainer(url: storeURL, allowsSave: false)
            )
            #expect(throws: (any Error).self) {
                _ = try repository.removeDocuments(
                    documentIDs: [firstID, secondID],
                    managedStore: managedStore
                )
            }
        }

        #expect(FileManager.default.fileExists(atPath: firstSourceURL.path))
        #expect(FileManager.default.fileExists(atPath: secondSourceURL.path))
        #expect(try regularFiles(in: managedDirectory) == ["first.pdf", "second.pdf"])
        let reopened = LibraryRepository(
            container: try persistentContainer(url: storeURL, allowsSave: true)
        )
        #expect(try reopened.paper(id: firstID) != nil)
        #expect(try reopened.paper(id: secondID) != nil)
    }

    @MainActor
    @Test("a failed batch restoration re-stages every managed copy and restores no Documents")
    func batchRestorationSaveFailureIsAtomic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Canopy.store")
        let managedDirectory = directory.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedStore = ManagedPaperStore(rootURL: managedDirectory)
        let firstSourceURL = managedDirectory.appendingPathComponent("first.pdf")
        let secondSourceURL = managedDirectory.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: firstSourceURL)
        try Data("second".utf8).write(to: secondSourceURL)
        let firstID = UUID()
        let secondID = UUID()
        let snapshots: [RemovedPaperSnapshot]

        do {
            let repository = LibraryRepository(
                container: try persistentContainer(url: storeURL, allowsSave: true)
            )
            try repository.insert(Document(
                id: firstID,
                fingerprint: Data(repeating: 35, count: 32),
                title: "First Restored Document",
                storageMode: .managedCopy,
                managedRelativePath: "first.pdf",
                sourceFilename: "first.pdf",
                sourceFileSize: 5
            ))
            try repository.insert(Document(
                id: secondID,
                fingerprint: Data(repeating: 36, count: 32),
                title: "Second Restored Document",
                storageMode: .managedCopy,
                managedRelativePath: "second.pdf",
                sourceFilename: "second.pdf",
                sourceFileSize: 6
            ))
            snapshots = try repository.removeDocuments(
                documentIDs: [firstID, secondID],
                managedStore: managedStore
            )
        }

        do {
            let repository = LibraryRepository(
                container: try persistentContainer(url: storeURL, allowsSave: false)
            )
            #expect(throws: (any Error).self) {
                _ = try repository.restoreRemovedDocuments(
                    snapshots: snapshots,
                    managedStore: managedStore
                )
            }
        }

        #expect(!FileManager.default.fileExists(atPath: firstSourceURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondSourceURL.path))
        #expect(try regularFiles(in: managedDirectory) == [
            "\(firstID.uuidString).pdf",
            "\(secondID.uuidString).pdf"
        ].sorted())
        let reopened = LibraryRepository(
            container: try persistentContainer(url: storeURL, allowsSave: true)
        )
        #expect(try reopened.paper(id: firstID) == nil)
        #expect(try reopened.paper(id: secondID) == nil)

        _ = try reopened.restoreRemovedDocuments(
            snapshots: snapshots,
            managedStore: managedStore
        )
        #expect(try reopened.paper(id: firstID) != nil)
        #expect(try reopened.paper(id: secondID) != nil)
        #expect(FileManager.default.fileExists(atPath: firstSourceURL.path))
        #expect(FileManager.default.fileExists(atPath: secondSourceURL.path))
    }

    @MainActor
    @Test("a failed database deletion restores the managed copy and Paper")
    func removalSaveFailureIsAtomic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Canopy.store")
        let managedDirectory = directory.appendingPathComponent("Papers", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedStore = ManagedPaperStore(rootURL: managedDirectory)
        let sourceURL = managedDirectory.appendingPathComponent("atomic.pdf")
        try Data("atomic".utf8).write(to: sourceURL)
        let paperID = UUID()

        do {
            let repository = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: true))
            try repository.insert(Paper(
                id: paperID,
                fingerprint: Data(repeating: 18, count: 32),
                title: "Atomic Removal",
                storageMode: .managedCopy,
                managedRelativePath: "atomic.pdf",
                sourceFilename: "atomic.pdf",
                sourceFileSize: 6
            ))
        }

        do {
            let repository = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: false))
            #expect(throws: (any Error).self) {
                _ = try repository.removePaper(paperID: paperID, managedStore: managedStore)
            }
        }

        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try regularFiles(in: managedDirectory) == ["atomic.pdf"])
        let reopened = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: true))
        #expect(try reopened.paper(id: paperID) != nil)
    }

    @MainActor
    @Test("a failed database restoration re-stages the managed copy for retry")
    func restorationSaveFailureIsAtomic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Canopy.store")
        let managedDirectory = directory.appendingPathComponent("Papers", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        let managedStore = ManagedPaperStore(rootURL: managedDirectory)
        let sourceURL = managedDirectory.appendingPathComponent("retry.pdf")
        try Data("retry".utf8).write(to: sourceURL)
        let paperID = UUID()
        let snapshot: RemovedPaperSnapshot

        do {
            let repository = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: true))
            try repository.insert(Paper(
                id: paperID,
                fingerprint: Data(repeating: 19, count: 32),
                title: "Atomic Restoration",
                storageMode: .managedCopy,
                managedRelativePath: "retry.pdf",
                sourceFilename: "retry.pdf",
                sourceFileSize: 5
            ))
            snapshot = try repository.removePaper(paperID: paperID, managedStore: managedStore)
        }

        do {
            let repository = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: false))
            #expect(throws: (any Error).self) {
                _ = try repository.restoreRemovedPaper(snapshot: snapshot, managedStore: managedStore)
            }
        }

        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(try regularFiles(in: managedDirectory) == ["\(paperID.uuidString).pdf"])

        let reopened = LibraryRepository(container: try persistentContainer(url: storeURL, allowsSave: true))
        try reopened.restoreRemovedPaper(snapshot: snapshot, managedStore: managedStore)
        #expect(try reopened.paper(id: paperID) != nil)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test("managed lifecycle paths cannot escape Canopy's store")
    func managedLifecycleRejectsPathTraversal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let managedStore = ManagedPaperStore(rootURL: directory)

        #expect(throws: PaperFileAccessError.self) {
            _ = try managedStore.stageForRecovery(relativePath: "../outside.pdf", paperID: UUID())
        }
        #expect(throws: PaperFileAccessError.self) {
            try managedStore.restoreFromRecovery(relativePath: "nested/outside.pdf", paperID: UUID())
        }
    }
}

private func persistentContainer(url: URL, allowsSave: Bool) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url, allowsSave: allowsSave)
    return try ModelContainer(
        for: Schema(versionedSchema: CanopySchemaV1.self),
        migrationPlan: CanopyMigrationPlan.self,
        configurations: configuration
    )
}

private func regularFiles(in directory: URL) throws -> [String] {
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey]
    ) else {
        return []
    }

    return try enumerator.compactMap { item in
        guard let url = item as? URL,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            return nil
        }
        return url.lastPathComponent
    }.sorted()
}
