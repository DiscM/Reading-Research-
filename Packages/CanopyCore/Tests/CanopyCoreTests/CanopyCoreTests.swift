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
