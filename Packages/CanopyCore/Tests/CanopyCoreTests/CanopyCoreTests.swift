import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("Canopy core persistence")
struct CanopyCoreTests {
    @Test("rejects identifier-shaped titles")
    func rejectsIdentifierTitles() {
        #expect(MetadataValidator.usableTitle("arXiv: 2401.12345") == nil)
        #expect(MetadataValidator.usableTitle("arXiv:2504.19874v1 [cs.LG] 28 Apr 2025") == nil)
        #expect(MetadataValidator.usableTitle("10.1000/example") == nil)
        #expect(MetadataValidator.usableTitle("paper.pdf") == nil)
        #expect(MetadataValidator.usableTitle("draft.odt") == nil)
        #expect(MetadataValidator.usableTitle("draft.md") == nil)
        #expect(MetadataValidator.usableTitle("paper.txt") == nil)
        #expect(MetadataValidator.usableTitle("Microsoft Word") == nil)
        #expect(MetadataValidator.usableTitle("LibreOffice Writer") == nil)
        #expect(MetadataValidator.usableTitle("PDFCreator") == nil)
        #expect(MetadataValidator.usableTitle("fulltext") == nil)
        #expect(MetadataValidator.usableTitle("AI") == "AI")
        #expect(MetadataValidator.usableTitle("A Useful Research Title") == "A Useful Research Title")
    }

    @Test("Preflight classifies an exact library duplicate as unaddable")
    func exactDuplicatePreflight() throws {
        let fixture = try TemporaryFile(contents: Data("same-pdf-bytes".utf8), filename: "candidate.pdf")
        defer { fixture.remove() }
        let fingerprint = try DocumentFingerprint.sha256(of: fixture.url)
        let existing = PaperIdentitySnapshot(
            id: UUID(),
            fingerprint: fingerprint,
            title: "Existing Paper",
            authorFamilyNames: ["Smith"],
            publicationYear: 2026,
            doi: nil,
            arxivID: nil,
            sourceState: .available,
            rememberedLocation: "/Research/existing.pdf"
        )
        let analyzer = StubDocumentAnalyzer(metadata: .init(title: "Candidate", titleProvenance: .firstPage))

        let result = AddBatchPreflight(analyzer: analyzer).run(urls: [fixture.url], existingPapers: [existing])

        #expect(result.ready.isEmpty)
        #expect(result.exactDuplicates.count == 1)
        #expect(result.exactDuplicates.first?.existingPaper.id == existing.id)
    }

    @Test("Preflight triggers Potential Duplicate Review only from deterministic evidence")
    func potentialDuplicateEvidence() throws {
        let existing = PaperIdentitySnapshot(
            id: UUID(),
            fingerprint: Data(repeating: 1, count: 32),
            title: "A Canopy Study: Results",
            authorFamilyNames: ["Smith"],
            publicationYear: 2025,
            doi: "10.1000/canopy",
            arxivID: nil,
            sourceState: .available,
            rememberedLocation: nil
        )
        let doiFile = try TemporaryFile(contents: Data("doi-candidate".utf8), filename: "doi.pdf")
        let titleYearFile = try TemporaryFile(contents: Data("title-year-candidate".utf8), filename: "title-year.pdf")
        let titleOnlyFile = try TemporaryFile(contents: Data("title-only-candidate".utf8), filename: "title-only.pdf")
        defer { doiFile.remove(); titleYearFile.remove(); titleOnlyFile.remove() }

        let doiResult = AddBatchPreflight(analyzer: StubDocumentAnalyzer(metadata: .init(
            title: "Different title",
            titleProvenance: .firstPage,
            doi: "https://doi.org/10.1000/CANOPY"
        ))).run(urls: [doiFile.url], existingPapers: [existing])
        let titleYearResult = AddBatchPreflight(analyzer: StubDocumentAnalyzer(metadata: .init(
            title: "A canopy study results",
            titleProvenance: .firstPage,
            publicationYear: 2025
        ))).run(urls: [titleYearFile.url], existingPapers: [existing])
        let titleOnlyResult = AddBatchPreflight(analyzer: StubDocumentAnalyzer(metadata: .init(
            title: "A canopy study results",
            titleProvenance: .firstPage
        ))).run(urls: [titleOnlyFile.url], existingPapers: [existing])

        #expect(doiResult.potentialDuplicates.count == 1)
        #expect(titleYearResult.potentialDuplicates.count == 1)
        #expect(titleOnlyResult.potentialDuplicates.isEmpty)
        #expect(titleOnlyResult.ready.count == 1)
    }

    @Test("Preflight detects exact duplicates inside one Add Batch")
    func withinBatchExactDuplicate() throws {
        let first = try TemporaryFile(contents: Data("identical".utf8), filename: "first.pdf")
        let second = try TemporaryFile(contents: Data("identical".utf8), filename: "second.pdf")
        defer { first.remove(); second.remove() }
        let analyzer = StubDocumentAnalyzer(metadata: .init(title: "Same Paper", titleProvenance: .firstPage))

        let result = AddBatchPreflight(analyzer: analyzer).run(urls: [first.url, second.url], existingPapers: [])

        #expect(result.ready.count == 1)
        #expect(result.withinBatchExactDuplicates.count == 1)
        #expect(result.withinBatchExactDuplicates.first?.retained.url == first.url)
        #expect(result.withinBatchExactDuplicates.first?.duplicate.url == second.url)
    }

    @Test("Preflight detects Potential Duplicates inside one Add Batch")
    func withinBatchPotentialDuplicate() throws {
        let first = try TemporaryFile(contents: Data("first-version".utf8), filename: "first.pdf")
        let second = try TemporaryFile(contents: Data("second-version".utf8), filename: "second.pdf")
        defer { first.remove(); second.remove() }
        let analyzer = StubDocumentAnalyzer(metadata: .init(
            title: "Shared Research Title",
            titleProvenance: .firstPage,
            publicationYear: 2026
        ))

        let result = AddBatchPreflight(analyzer: analyzer).run(urls: [first.url, second.url], existingPapers: [])

        #expect(result.ready.count == 1)
        #expect(result.potentialDuplicates.count == 1)
        #expect(result.potentialDuplicates.first?.candidate.url == second.url)
        #expect(result.potentialDuplicates.first?.existingPapers.first?.rememberedLocation == first.url.path)
    }

    @Test("Preflight byte progress is monotonic and completes")
    func preflightProgress() throws {
        let fixture = try TemporaryFile(contents: Data(repeating: 7, count: 2_500_000), filename: "large.pdf")
        defer { fixture.remove() }
        let analyzer = StubDocumentAnalyzer(metadata: .init(title: "Large Paper", titleProvenance: .firstPage))
        let recorder = ProgressRecorder()

        _ = AddBatchPreflight(analyzer: analyzer).run(urls: [fixture.url], existingPapers: []) { update in
            recorder.append(update.fractionCompleted)
        }

        let values = recorder.values
        #expect(values.count >= 3)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.last == 1)
    }

    @MainActor
    @Test("repository adds an approved referenced candidate as one complete Paper")
    func repositoryAddsReferencedPaper() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let metadata = ParsedPaperMetadata(
            title: "Approved Paper",
            titleProvenance: .firstPage,
            authors: [.init(displayName: "Jane Smith", familyName: "Smith", provenance: .firstPage)],
            publicationYear: 2026,
            publicationYearProvenance: .firstPage,
            doi: "10.1000/approved",
            doiProvenance: .firstPage
        )
        let candidate = PreflightCandidate(
            url: URL(fileURLWithPath: "/Research/approved.pdf"),
            fingerprint: Data(repeating: 9, count: 32),
            fileSize: 128,
            modificationDate: Date(timeIntervalSince1970: 100),
            metadata: metadata
        )

        let paper = try repository.add(
            candidate,
            source: .referenced(bookmarkData: Data([1, 2, 3]), rememberedLocation: "/Research/approved.pdf")
        )

        #expect(paper.title == "Approved Paper")
        #expect(paper.storageMode == .referenced)
        #expect(paper.bookmarkData == Data([1, 2, 3]))
        #expect(paper.authorCredits.map(\.displayName) == ["Jane Smith"])
        #expect(try repository.paperIdentitySnapshots().map(\.id) == [paper.id])
    }

    @MainActor
    @Test("reference repair requires the Paper's exact content fingerprint")
    func exactReferenceRepair() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let fingerprint = Data(repeating: 4, count: 32)
        let paper = Paper(
            fingerprint: fingerprint,
            title: "Missing Source",
            storageMode: .referenced,
            sourceState: .brokenReference,
            sourceFilename: "missing.pdf",
            rememberedLocation: "/Old/missing.pdf",
            sourceFileSize: 10
        )
        try repository.insert(paper)
        #expect(throws: LibraryRepositoryError.contentIdentityMismatch) {
            try repository.repairReference(
                paperID: paper.id,
                fingerprint: Data(repeating: 5, count: 32),
                bookmarkData: Data([8]),
                rememberedLocation: "/New/wrong.pdf"
            )
        }
        try repository.repairReference(
            paperID: paper.id,
            fingerprint: fingerprint,
            bookmarkData: Data([9]),
            rememberedLocation: "/New/missing.pdf"
        )

        #expect(paper.sourceState == .available)
        #expect(paper.bookmarkData == Data([9]))
        #expect(paper.rememberedLocation == "/New/missing.pdf")
    }

    @MainActor
    @Test("managed copy recovery restores only the Paper's exact Source PDF")
    func exactManagedCopyRecovery() async throws {
        let source = try TemporaryFile(contents: Data("original-source".utf8), filename: "located.pdf")
        defer { source.remove() }
        let managedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: managedDirectory) }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: source.url),
            title: "Missing Library Copy",
            storageMode: .managedCopy,
            sourceState: .libraryCopyMissing,
            managedRelativePath: "managed-source.pdf",
            sourceFilename: "original.pdf",
            sourceFileSize: 0
        )
        try repository.insert(paper)

        try await repository.restoreManagedCopy(
            paperID: paper.id,
            from: source.url,
            managedStore: ManagedPaperStore(rootURL: managedDirectory)
        )

        let restoredURL = managedDirectory.appendingPathComponent("managed-source.pdf")
        #expect(try Data(contentsOf: restoredURL) == Data("original-source".utf8))
        #expect(paper.sourceState == .available)
        #expect(paper.sourceFileSize == Int64(Data("original-source".utf8).count))
    }

    @MainActor
    @Test("managed copy recovery rejects different PDF bytes and leaves the copy missing")
    func managedCopyRecoveryRejectsMismatch() async throws {
        let original = try TemporaryFile(contents: Data("original-source".utf8), filename: "original.pdf")
        let different = try TemporaryFile(contents: Data("different-source".utf8), filename: "different.pdf")
        defer {
            original.remove()
            different.remove()
        }
        let managedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: managedDirectory) }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: original.url),
            title: "Missing Library Copy",
            storageMode: .managedCopy,
            sourceState: .libraryCopyMissing,
            managedRelativePath: "managed-source.pdf",
            sourceFilename: "original.pdf",
            sourceFileSize: 0
        )
        try repository.insert(paper)
        let unrelatedPaper = Paper(
            fingerprint: Data(repeating: 19, count: 32),
            title: "Saved title",
            storageMode: .referenced,
            sourceFilename: "unrelated.pdf",
            sourceFileSize: 1
        )
        try repository.insert(unrelatedPaper)
        unrelatedPaper.title = "Pending user edit"

        await #expect(throws: LibraryRepositoryError.contentIdentityMismatch) {
            try await repository.restoreManagedCopy(
                paperID: paper.id,
                from: different.url,
                managedStore: ManagedPaperStore(rootURL: managedDirectory)
            )
        }

        #expect(!FileManager.default.fileExists(
            atPath: managedDirectory.appendingPathComponent("managed-source.pdf").path
        ))
        #expect(paper.sourceState == .libraryCopyMissing)
        #expect(unrelatedPaper.title == "Pending user edit")
        #expect(repository.context.hasChanges)
    }

    @MainActor
    @Test("paper metadata and source identity round-trip through a reopened store")
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
                titleProvenance: .firstPage,
                publicationYear: 2026,
                publicationYearProvenance: .embeddedMetadata,
                doi: "10.1000/canopy",
                doiProvenance: .userEntry,
                arxivID: "2607.01234v2",
                arxivIDProvenance: .firstPage,
                storageMode: .referenced,
                sourceState: .available,
                sourceFilename: "paper.pdf",
                rememberedLocation: "/Volumes/Research/paper.pdf",
                sourceFileSize: 42,
                authorCredits: [
                    AuthorCredit(position: 0, displayName: "Jane A. Smith", familyName: "Smith", provenance: .firstPage),
                    AuthorCredit(position: 1, displayName: "OpenAI Research", familyName: "OpenAI Research", provenance: .userEntry)
                ]
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
        let paper = try #require(papers.first)
        #expect(paper.title == "Persistent Paper")
        #expect(paper.titleProvenance == .firstPage)
        #expect(paper.publicationYear == 2026)
        #expect(paper.doi == "10.1000/canopy")
        #expect(paper.arxivID == "2607.01234v2")
        #expect(paper.sourceState == .available)
        #expect(paper.rememberedLocation == "/Volumes/Research/paper.pdf")
        #expect(paper.authorCredits.sorted { $0.position < $1.position }.map(\.displayName) == ["Jane A. Smith", "OpenAI Research"])
    }

    @MainActor
    @Test("reader state survives closing and reopening the library")
    func readerStateRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Canopy.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paperID = UUID()
        let openedAt = Date(timeIntervalSince1970: 1_789_000_000)

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: Schema(versionedSchema: CanopySchemaV1.self),
                migrationPlan: CanopyMigrationPlan.self,
                configurations: configuration
            )
            let repository = LibraryRepository(container: container)
            let paper = Paper(
                id: paperID,
                fingerprint: Data(repeating: 8, count: 32),
                title: "Resume Me",
                storageMode: .referenced,
                sourceFilename: "resume.pdf",
                sourceFileSize: 512
            )
            try repository.insert(paper)

            try repository.recordPaperOpened(paperID: paperID, at: openedAt)
            try repository.saveReaderState(
                paperID: paperID,
                state: PaperReaderState(
                    pageIndex: 12,
                    viewport: PaperViewport(x: 14.5, y: 220.25, width: 640, height: 720),
                    zoomScale: 1.35,
                    isInspectorPresented: false
                )
            )
        }

        let configuration = ModelConfiguration(url: storeURL)
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
        let repository = LibraryRepository(container: reopened)
        let paper = try #require(try repository.paper(id: paperID))

        #expect(paper.lastOpenedAt == openedAt)
        #expect(try repository.readerState(paperID: paperID) == PaperReaderState(
            pageIndex: 12,
            viewport: PaperViewport(x: 14.5, y: 220.25, width: 640, height: 720),
            zoomScale: 1.35,
            isInspectorPresented: false
        ))
    }

    @MainActor
    @Test("Paper Info normalizes and persists one staged scalar update")
    func paperInfoUpdateNormalizesAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Canopy.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paperID = UUID()
        let authorID = UUID()
        let fingerprint = Data(repeating: 6, count: 32)
        var committedChange: PaperInfoChange?

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: Schema(versionedSchema: CanopySchemaV1.self),
                migrationPlan: CanopyMigrationPlan.self,
                configurations: configuration
            )
            let repository = LibraryRepository(container: container)
            let paper = Paper(
                id: paperID,
                fingerprint: fingerprint,
                title: "Original Study",
                titleProvenance: .firstPage,
                publicationYear: 2024,
                publicationYearProvenance: .embeddedMetadata,
                doi: "10.1000/original",
                doiProvenance: .firstPage,
                arxivID: "2401.01234",
                arxivIDProvenance: .embeddedMetadata,
                storageMode: .referenced,
                bookmarkData: Data([1, 2, 3]),
                sourceFilename: "original.pdf",
                rememberedLocation: "/Research/original.pdf",
                sourceFileSize: 4_096,
                authorCredits: [
                    AuthorCredit(
                        id: authorID,
                        position: 0,
                        displayName: "Ada Researcher",
                        familyName: "Researcher",
                        provenance: .firstPage
                    )
                ]
            )
            try repository.insert(paper)

            let before = try repository.paperInfoSnapshot(paperID: paperID)
            let change = try repository.updatePaperInfo(
                paperID: paperID,
                update: PaperInfoUpdate(
                    title: "  Revised Canopy Study\n",
                    publicationYear: 2026,
                    doi: " HTTPS://DOI.ORG/10.5555/Canopy.Test ",
                    arxivID: " arXiv: 2607.01234V2 ",
                    authorCredits: [
                        AuthorCreditUpdate(
                            id: authorID,
                            displayName: "Ada Researcher",
                            familyName: "Researcher"
                        )
                    ]
                )
            )
            committedChange = change

            #expect(change.before == before)
            #expect(change.after.title == "Revised Canopy Study")
            #expect(change.after.titleProvenance == .userEntry)
            #expect(change.after.publicationYear == 2026)
            #expect(change.after.publicationYearProvenance == .userEntry)
            #expect(change.after.doi == "10.5555/canopy.test")
            #expect(change.after.doiProvenance == .userEntry)
            #expect(change.after.arxivID == "2607.01234v2")
            #expect(change.after.arxivIDProvenance == .userEntry)
            #expect(paper.fingerprint == fingerprint)
            #expect(paper.bookmarkData == Data([1, 2, 3]))
            #expect(paper.rememberedLocation == "/Research/original.pdf")
            #expect(paper.authorCredits.map(\.id) == [authorID])
            #expect(paper.authorCredits.map(\.provenance) == [.firstPage])
        }

        let configuration = ModelConfiguration(url: storeURL)
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
        let repository = LibraryRepository(container: reopened)
        let expectedAfter = try #require(committedChange).after
        #expect(try repository.paperInfoSnapshot(paperID: paperID) == expectedAfter)
        let paper = try #require(try repository.paper(id: paperID))
        #expect(paper.fingerprint == fingerprint)
        #expect(paper.rememberedLocation == "/Research/original.pdf")
        #expect(paper.authorCredits.map(\.id) == [authorID])
    }

    @MainActor
    @Test("Paper Info atomically adds, edits, removes, and reorders Author Credits")
    func paperInfoAuthorCreditEdits() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let firstAuthorID = UUID()
        let secondAuthorID = UUID()
        let removedAuthorID = UUID()
        let addedAuthorID = UUID()
        let paper = Paper(
            fingerprint: Data(repeating: 18, count: 32),
            title: "Ordered Authors",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "ordered-authors.pdf",
            sourceFileSize: 512,
            authorCredits: [
                AuthorCredit(
                    id: firstAuthorID,
                    position: 0,
                    displayName: "Ada Byron",
                    familyName: "Byron",
                    provenance: .firstPage
                ),
                AuthorCredit(
                    id: secondAuthorID,
                    position: 1,
                    displayName: "Grace Hopper",
                    familyName: "Hopper",
                    provenance: .embeddedMetadata
                ),
                AuthorCredit(
                    id: removedAuthorID,
                    position: 2,
                    displayName: "Remove Me",
                    familyName: "Me",
                    provenance: .embeddedMetadata
                )
            ]
        )
        try repository.insert(paper)

        let change = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "Ordered Authors",
                publicationYear: nil,
                doi: nil,
                arxivID: nil,
                authorCredits: [
                    AuthorCreditUpdate(
                        id: secondAuthorID,
                        displayName: "Grace Hopper",
                        familyName: "Hopper"
                    ),
                    AuthorCreditUpdate(
                        id: firstAuthorID,
                        displayName: "Ada Lovelace",
                        familyName: "Lovelace"
                    ),
                    AuthorCreditUpdate(
                        id: addedAuthorID,
                        displayName: "Katherine Johnson",
                        familyName: "Johnson"
                    )
                ]
            )
        )

        #expect(change.after.authorCredits.map(\.id) == [secondAuthorID, firstAuthorID, addedAuthorID])
        #expect(change.after.authorCredits.map(\.position) == [0, 1, 2])
        #expect(change.after.authorCredits.map(\.displayName) == ["Grace Hopper", "Ada Lovelace", "Katherine Johnson"])
        #expect(change.after.authorCredits.map(\.familyName) == ["Hopper", "Lovelace", "Johnson"])
        #expect(change.after.authorCredits.map(\.provenance) == [.embeddedMetadata, .userEntry, .userEntry])
        #expect(!change.after.authorCredits.map(\.id).contains(removedAuthorID))
        #expect(change.after.titleProvenance == .firstPage)
    }

    @MainActor
    @Test("invalid Author Credits reject the entire Paper Info transaction")
    func invalidPaperInfoAuthorCreditsRejectWholeUpdate() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let authorID = UUID()
        let foreignAuthorID = UUID()
        let paper = Paper(
            fingerprint: Data(repeating: 19, count: 32),
            title: "Valid Authors",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "valid-authors.pdf",
            sourceFileSize: 256,
            authorCredits: [
                AuthorCredit(
                    id: authorID,
                    position: 0,
                    displayName: "Ada Lovelace",
                    familyName: "Lovelace",
                    provenance: .firstPage
                )
            ]
        )
        let foreignPaper = Paper(
            fingerprint: Data(repeating: 20, count: 32),
            title: "Another Paper",
            storageMode: .referenced,
            sourceFilename: "another.pdf",
            sourceFileSize: 256,
            authorCredits: [
                AuthorCredit(
                    id: foreignAuthorID,
                    position: 0,
                    displayName: "Grace Hopper",
                    familyName: "Hopper",
                    provenance: .embeddedMetadata
                )
            ]
        )
        try repository.insert(paper)
        try repository.insert(foreignPaper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let invalidAuthorLists = [
            [AuthorCreditUpdate(id: authorID, displayName: " ", familyName: "Lovelace")],
            [
                AuthorCreditUpdate(id: authorID, displayName: "Ada Lovelace", familyName: "Lovelace"),
                AuthorCreditUpdate(id: authorID, displayName: "Ada Again", familyName: "Again")
            ],
            [AuthorCreditUpdate(id: foreignAuthorID, displayName: "Grace Hopper", familyName: "Hopper")]
        ]

        for authorCredits in invalidAuthorLists {
            #expect(throws: LibraryRepositoryError.invalidAuthorCredit) {
                _ = try repository.updatePaperInfo(
                    paperID: paper.id,
                    update: PaperInfoUpdate(
                        title: "This Must Not Persist",
                        publicationYear: 2026,
                        doi: nil,
                        arxivID: nil,
                        authorCredits: authorCredits
                    )
                )
            }
            #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
        }
    }

    @MainActor
    @Test("an invalid Paper Info field rejects the whole staged update")
    func invalidPaperInfoRejectsWholeUpdate() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 11, count: 32),
            title: "Original Metadata",
            titleProvenance: .firstPage,
            publicationYear: 2024,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/original",
            doiProvenance: .firstPage,
            arxivID: "2401.01234",
            arxivIDProvenance: .embeddedMetadata,
            storageMode: .referenced,
            sourceFilename: "original.pdf",
            sourceFileSize: 512
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let invalidUpdates: [(PaperInfoUpdate, LibraryRepositoryError)] = [
            (
                PaperInfoUpdate(
                    title: " ",
                    publicationYear: 2026,
                    doi: "10.5555/revised",
                    arxivID: "2607.12345",
                    authorCredits: []
                ),
                .invalidTitle
            ),
            (
                PaperInfoUpdate(
                    title: "Revised Metadata",
                    publicationYear: 999,
                    doi: "10.5555/revised",
                    arxivID: "2607.12345",
                    authorCredits: []
                ),
                .invalidPublicationYear
            ),
            (
                PaperInfoUpdate(
                    title: "Revised Metadata",
                    publicationYear: 2026,
                    doi: "not a DOI",
                    arxivID: "2607.12345",
                    authorCredits: []
                ),
                .invalidDOI
            ),
            (
                PaperInfoUpdate(
                    title: "Revised Metadata",
                    publicationYear: 2026,
                    doi: "10.5555/revised",
                    arxivID: "not an arXiv ID",
                    authorCredits: []
                ),
                .invalidArxivID
            )
        ]

        for (update, expectedError) in invalidUpdates {
            #expect(throws: expectedError) {
                _ = try repository.updatePaperInfo(paperID: paper.id, update: update)
            }
            #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
        }
    }

    @MainActor
    @Test("only changed Paper Info fields replace their existing provenance")
    func unchangedPaperInfoPreservesProvenance() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 12, count: 32),
            title: "Same Metadata",
            titleProvenance: .firstPage,
            publicationYear: 2025,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/same",
            doiProvenance: .firstPage,
            arxivID: "2401.12345v2",
            arxivIDProvenance: .filenameFallback,
            storageMode: .referenced,
            sourceFilename: "same.pdf",
            sourceFileSize: 256
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)

        let change = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "Changed Title Only",
                publicationYear: 2025,
                doi: "HTTPS://DOI.ORG/10.1000/SAME",
                arxivID: "arXiv: 2401.12345V2",
                authorCredits: []
            )
        )

        #expect(change.before == before)
        #expect(change.after.title == "Changed Title Only")
        #expect(paper.titleProvenance == .userEntry)
        #expect(change.after.publicationYear == before.publicationYear)
        #expect(paper.publicationYearProvenance == .embeddedMetadata)
        #expect(change.after.doi == before.doi)
        #expect(paper.doiProvenance == .firstPage)
        #expect(change.after.arxivID == before.arxivID)
        #expect(paper.arxivIDProvenance == .filenameFallback)
    }

    @MainActor
    @Test("empty optional Paper Info identifiers clear their values and provenance")
    func emptyPaperInfoIdentifiersBecomeNil() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 13, count: 32),
            title: "Optional Identifiers",
            titleProvenance: .embeddedMetadata,
            doi: "10.1000/remove",
            doiProvenance: .firstPage,
            arxivID: "2401.12345",
            arxivIDProvenance: .firstPage,
            storageMode: .managedCopy,
            sourceFilename: "optional.pdf",
            sourceFileSize: 128
        )
        try repository.insert(paper)

        let change = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "Optional Identifiers",
                publicationYear: nil,
                doi: " \n ",
                arxivID: nil,
                authorCredits: []
            )
        )

        #expect(change.after.doi == nil)
        #expect(change.after.doiProvenance == nil)
        #expect(change.after.arxivID == nil)
        #expect(change.after.arxivIDProvenance == nil)
        #expect(change.after.titleProvenance == .embeddedMetadata)
    }

    @MainActor
    @Test("restoring a Paper Info snapshot restores values and provenance atomically")
    func restoringPaperInfoSnapshotPreservesProvenance() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 14, count: 32),
            title: "Before Edit",
            titleProvenance: .filenameFallback,
            publicationYear: 2023,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/before",
            doiProvenance: .firstPage,
            arxivID: "2301.12345",
            arxivIDProvenance: .embeddedMetadata,
            storageMode: .referenced,
            bookmarkData: Data([9, 8, 7]),
            sourceFilename: "before.pdf",
            sourceFileSize: 1_024,
            authorCredits: [
                AuthorCredit(
                    position: 0,
                    displayName: "Grace Author",
                    familyName: "Author",
                    provenance: .firstPage
                )
            ]
        )
        try repository.insert(paper)
        let original = try repository.paperInfoSnapshot(paperID: paper.id)
        let edit = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "After Edit",
                publicationYear: 2026,
                doi: "10.1000/after",
                arxivID: "2607.12345",
                authorCredits: original.authorCredits.map {
                    AuthorCreditUpdate(
                        id: $0.id,
                        displayName: $0.displayName,
                        familyName: $0.familyName
                    )
                }
            )
        )

        let restore = try repository.restorePaperInfoSnapshot(original)

        #expect(restore.before == edit.after)
        #expect(restore.after == original)
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == original)
        #expect(paper.bookmarkData == Data([9, 8, 7]))
        #expect(paper.authorCredits.map(\.displayName) == ["Grace Author"])
        #expect(paper.authorCredits.map(\.provenance) == [.firstPage])
    }

    @MainActor
    @Test("applying an explicit Paper Info snapshot preserves mixed provenance atomically")
    func applyingPaperInfoSnapshotPreservesMixedProvenance() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let originalAuthorID = UUID()
        let manualAuthorID = UUID()
        let parsedAuthorID = UUID()
        let paper = Paper(
            fingerprint: Data(repeating: 22, count: 32),
            title: "Original Metadata",
            titleProvenance: .filenameFallback,
            publicationYear: 2022,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/original",
            doiProvenance: .embeddedMetadata,
            storageMode: .referenced,
            sourceFilename: "mixed-provenance.pdf",
            sourceFileSize: 2_048,
            authorCredits: [
                AuthorCredit(
                    id: originalAuthorID,
                    position: 0,
                    displayName: "Original Author",
                    familyName: "Author",
                    provenance: .embeddedMetadata
                ),
                AuthorCredit(
                    id: manualAuthorID,
                    position: 1,
                    displayName: "Manual Curator",
                    familyName: "Curator",
                    provenance: .userEntry
                )
            ]
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let target = PaperInfoSnapshot(
            paperID: paper.id,
            title: "Freshly Parsed Title",
            titleProvenance: .firstPage,
            publicationYear: 2026,
            publicationYearProvenance: .userEntry,
            doi: "10.1000/original",
            doiProvenance: .embeddedMetadata,
            arxivID: "2607.01234",
            arxivIDProvenance: .firstPage,
            authorCredits: [
                AuthorCreditSnapshot(
                    id: originalAuthorID,
                    position: 0,
                    displayName: "Original Author",
                    familyName: "Author",
                    provenance: .embeddedMetadata
                ),
                AuthorCreditSnapshot(
                    id: manualAuthorID,
                    position: 1,
                    displayName: "Manual Curator",
                    familyName: "Curator",
                    provenance: .userEntry
                ),
                AuthorCreditSnapshot(
                    id: parsedAuthorID,
                    position: 2,
                    displayName: "Parsed Researcher",
                    familyName: "Researcher",
                    provenance: .firstPage
                )
            ]
        )

        let change = try repository.applyPaperInfoSnapshot(target)

        #expect(change == PaperInfoChange(before: before, after: target))
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == target)
    }

    @MainActor
    @Test("restoring Paper Info rejects inconsistent optional metadata provenance")
    func restoringPaperInfoRejectsInconsistentProvenance() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 15, count: 32),
            title: "Consistent Metadata",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "consistent.pdf",
            sourceFileSize: 64
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let inconsistent = PaperInfoSnapshot(
            paperID: paper.id,
            title: "Changed Metadata",
            titleProvenance: .userEntry,
            publicationYear: nil,
            publicationYearProvenance: nil,
            doi: "10.1000/missing-provenance",
            doiProvenance: nil,
            arxivID: nil,
            arxivIDProvenance: nil,
            authorCredits: before.authorCredits
        )

        #expect(throws: LibraryRepositoryError.invalidMetadataProvenance) {
            _ = try repository.restorePaperInfoSnapshot(inconsistent)
        }
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
    }

    @MainActor
    @Test("annotation lifecycle survives reopening and preserves its composite anchor")
    func annotationLifecycleRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Canopy.store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let paperID = UUID()
        let annotationID: UUID
        let anchor = AnnotationAnchor(
            pageIndex: 2,
            quadrilaterals: [
                AnnotationQuadrilateral(
                    upperLeft: AnnotationPoint(x: 10, y: 80),
                    upperRight: AnnotationPoint(x: 90, y: 80),
                    lowerLeft: AnnotationPoint(x: 10, y: 64),
                    lowerRight: AnnotationPoint(x: 90, y: 64)
                ),
                AnnotationQuadrilateral(
                    upperLeft: AnnotationPoint(x: 10, y: 60),
                    upperRight: AnnotationPoint(x: 140, y: 60),
                    lowerLeft: AnnotationPoint(x: 10, y: 44),
                    lowerRight: AnnotationPoint(x: 140, y: 44)
                )
            ],
            selectedText: "A composite selection",
            contextBefore: "before ",
            contextAfter: " after"
        )

        do {
            let configuration = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(
                for: Schema(versionedSchema: CanopySchemaV1.self),
                migrationPlan: CanopyMigrationPlan.self,
                configurations: configuration
            )
            let repository = LibraryRepository(container: container)
            let paper = Paper(
                id: paperID,
                fingerprint: Data(repeating: 3, count: 32),
                title: "Annotated Paper",
                storageMode: .managedCopy,
                sourceFilename: "annotated.pdf",
                sourceFileSize: 1_024,
                pageCount: 5
            )
            try repository.insert(paper)
            let annotations = try repository.createAnnotations(
                paperID: paperID,
                anchors: [anchor],
                color: .purple,
                note: "Initial note"
            )
            annotationID = try #require(annotations.first).id
        }

        let configuration = ModelConfiguration(url: storeURL)
        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CanopySchemaV1.self),
            migrationPlan: CanopyMigrationPlan.self,
            configurations: configuration
        )
        let repository = LibraryRepository(container: reopened)
        let annotation = try #require(try repository.annotations(paperID: paperID).first)
        #expect(annotation.id == annotationID)
        #expect(annotation.anchor == anchor)
        #expect(annotation.color == .purple)
        #expect(annotation.note == "Initial note")

        try repository.updateAnnotationNote(annotationID: annotationID, note: "Edited note")
        let snapshot = try repository.deleteAnnotation(annotationID: annotationID)
        #expect(try repository.annotations(paperID: paperID).isEmpty)

        let restored = try repository.restoreAnnotation(snapshot)
        #expect(restored.note == "Edited note")
        #expect(restored.anchor == anchor)
        #expect(try repository.annotations(paperID: paperID).map(\.id) == [annotationID])
    }

    @MainActor
    @Test("annotation changes are blocked when source identity is not verified")
    func annotationsRequireVerifiedSource() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 2, count: 32),
            title: "Changed Source",
            storageMode: .referenced,
            sourceState: .sourceChanged,
            sourceFilename: "changed.pdf",
            sourceFileSize: 20,
            pageCount: 1
        )
        try repository.insert(paper)
        let anchor = AnnotationAnchor(
            pageIndex: 0,
            quadrilaterals: [
                AnnotationQuadrilateral(
                    upperLeft: AnnotationPoint(x: 0, y: 10),
                    upperRight: AnnotationPoint(x: 10, y: 10),
                    lowerLeft: AnnotationPoint(x: 0, y: 0),
                    lowerRight: AnnotationPoint(x: 10, y: 0)
                )
            ],
            selectedText: "Blocked"
        )

        #expect(throws: LibraryRepositoryError.annotationsUnavailable) {
            _ = try repository.annotations(paperID: paper.id)
        }
        #expect(throws: LibraryRepositoryError.annotationsUnavailable) {
            _ = try repository.createAnnotations(paperID: paper.id, anchors: [anchor], color: .yellow)
        }
    }

    @Test("source access rejects changed PDF bytes before opening")
    func sourceAccessRejectsChangedContent() throws {
        let fixture = try TemporaryFile(contents: Data("original-pdf".utf8), filename: "paper.pdf")
        defer { fixture.remove() }
        let originalAttributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        let originalModificationDate = try #require(originalAttributes[.modificationDate] as? Date)
        let fingerprint = try DocumentFingerprint.sha256(of: fixture.url)
        let paper = Paper(
            fingerprint: fingerprint,
            title: "Identity Matters",
            storageMode: .managedCopy,
            managedRelativePath: fixture.url.lastPathComponent,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: Int64(Data("original-pdf".utf8).count),
            sourceModificationDate: originalModificationDate
        )
        try Data("modified-pdf".utf8).write(to: fixture.url)
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate.addingTimeInterval(10)],
            ofItemAtPath: fixture.url.path
        )

        #expect(throws: PaperSourceAccessError.sourceChanged) {
            _ = try PaperSourceAccess(paper: paper, managedStore: ManagedPaperStore(rootURL: fixture.directory))
        }
    }

    @MainActor
    @Test("repository persists verified source attributes and changed identity state")
    func repositoryPersistsSourceVerification() throws {
        let fixture = try TemporaryFile(contents: Data("stable-pdf".utf8), filename: "paper.pdf")
        defer { fixture.remove() }
        let fingerprint = try DocumentFingerprint.sha256(of: fixture.url)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: fingerprint,
            title: "Verified Paper",
            storageMode: .managedCopy,
            managedRelativePath: fixture.url.lastPathComponent,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: 0,
            sourceModificationDate: .distantPast
        )
        try repository.insert(paper)

        let access = try repository.sourceAccess(
            paperID: paper.id,
            managedStore: ManagedPaperStore(rootURL: fixture.directory)
        )

        #expect(access.attributesChanged)
        #expect(paper.sourceFileSize == Int64(Data("stable-pdf".utf8).count))
        #expect(paper.sourceModificationDate == access.verifiedModificationDate)
        #expect(paper.sourceState == .available)

        try Data("altered-pdf".utf8).write(to: fixture.url)
        #expect(throws: PaperSourceAccessError.sourceChanged) {
            _ = try repository.sourceAccess(
                paperID: paper.id,
                managedStore: ManagedPaperStore(rootURL: fixture.directory)
            )
        }
        #expect(paper.sourceState == .sourceChanged)
    }

    @MainActor
    @Test("retry returns a transiently unavailable source to healthy")
    func retryUnavailableSource() throws {
        let fixture = try TemporaryFile(contents: Data("available-again".utf8), filename: "paper.pdf")
        defer { fixture.remove() }
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        let modificationDate = try #require(attributes[.modificationDate] as? Date)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: fixture.url),
            title: "Available Again",
            storageMode: .managedCopy,
            sourceState: .sourceUnavailable,
            managedRelativePath: fixture.url.lastPathComponent,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: Int64(Data("available-again".utf8).count),
            sourceModificationDate: modificationDate
        )
        try repository.insert(paper)

        _ = try repository.sourceAccess(
            paperID: paper.id,
            managedStore: ManagedPaperStore(rootURL: fixture.directory)
        )

        #expect(paper.sourceState == .available)
    }

    @MainActor
    @Test("removing a referenced Paper preserves its user-controlled Source PDF")
    func removingReferencedPaperPreservesSource() throws {
        let fixture = try TemporaryFile(contents: Data("referenced-pdf".utf8), filename: "referenced.pdf")
        defer { fixture.remove() }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: fixture.url),
            title: "Referenced Paper",
            storageMode: .referenced,
            sourceFilename: fixture.url.lastPathComponent,
            rememberedLocation: fixture.url.path,
            sourceFileSize: Int64(Data("referenced-pdf".utf8).count)
        )
        try repository.insert(paper)

        let snapshot = try repository.removePaper(
            paperID: paper.id,
            managedStore: ManagedPaperStore(rootURL: fixture.directory)
        )

        #expect(try repository.paper(id: paper.id) == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.url.path))

        try repository.restoreRemovedPaper(
            snapshot: snapshot,
            managedStore: ManagedPaperStore(rootURL: fixture.directory)
        )
        #expect(try repository.paper(id: paper.id)?.title == "Referenced Paper")
        #expect(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    @MainActor
    @Test("removing a managed Paper deletes Canopy's Source PDF copy")
    func removingManagedPaperDeletesSourceCopy() throws {
        let fixture = try TemporaryFile(contents: Data("managed-pdf".utf8), filename: "managed.pdf")
        defer { fixture.remove() }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: fixture.url),
            title: "Managed Paper",
            storageMode: .managedCopy,
            managedRelativePath: fixture.url.lastPathComponent,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: Int64(Data("managed-pdf".utf8).count)
        )
        try repository.insert(paper)

        let snapshot = try repository.removePaper(
            paperID: paper.id,
            managedStore: ManagedPaperStore(rootURL: fixture.directory)
        )

        #expect(try repository.paper(id: paper.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
        #expect(snapshot.managedCopyWasStaged)
    }
}

private struct StubDocumentAnalyzer: DocumentAnalyzing {
    let metadata: ParsedPaperMetadata

    func analyze(_ url: URL) throws -> ParsedPaperMetadata { metadata }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}

private struct TemporaryFile {
    let directory: URL
    let url: URL

    init(contents: Data, filename: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
        try contents.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
