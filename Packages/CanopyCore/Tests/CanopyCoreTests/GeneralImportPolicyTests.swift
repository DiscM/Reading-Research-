import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("General document import policy")
struct GeneralImportPolicyTests {
    @Test("bibliographic duplicate review is limited to research papers")
    func potentialDuplicatesAreResearchOnly() throws {
        let fixture = try ImportPolicyTemporaryFile(contents: Data("new bytes".utf8))
        defer { fixture.remove() }

        let matchingResearchPaper = PaperIdentitySnapshot(
            id: UUID(),
            fingerprint: Data(repeating: 1, count: 32),
            kind: .researchPaper,
            title: "Shared Title",
            authorFamilyNames: ["Rivera"],
            publicationYear: 2026,
            doi: "10.1000/shared",
            arxivID: nil,
            sourceState: .available,
            rememberedLocation: nil
        )
        let analyzer = ImportPolicyAnalyzer(metadata: ParsedPaperMetadata(
            title: "Shared Title",
            titleProvenance: .embeddedMetadata,
            authors: [
                ParsedAuthorCredit(
                    displayName: "Alex Rivera",
                    familyName: "Rivera",
                    provenance: .embeddedMetadata
                )
            ],
            publicationYear: 2026,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/shared",
            doiProvenance: .embeddedMetadata
        ))

        let generalResult = try AddBatchPreflight(analyzer: analyzer).run(
            urls: [fixture.url],
            existingPapers: [matchingResearchPaper],
            documentKind: .generalDocument
        )
        let researchResult = try AddBatchPreflight(analyzer: analyzer).run(
            urls: [fixture.url],
            existingPapers: [matchingResearchPaper],
            documentKind: .researchPaper
        )

        #expect(generalResult.ready.count == 1)
        #expect(generalResult.potentialDuplicates.isEmpty)
        #expect(researchResult.ready.isEmpty)
        #expect(researchResult.potentialDuplicates.count == 1)
    }

    @Test("exact content duplicates apply to every document kind")
    func exactDuplicatesRemainUniversal() throws {
        let fixture = try ImportPolicyTemporaryFile(contents: Data("same bytes".utf8))
        defer { fixture.remove() }
        let fingerprint = try DocumentFingerprint.sha256(of: fixture.url)
        let existing = PaperIdentitySnapshot(
            id: UUID(),
            fingerprint: fingerprint,
            kind: .lectureSlides,
            title: "Week One",
            authorFamilyNames: [],
            publicationYear: nil,
            doi: nil,
            arxivID: nil,
            sourceState: .available,
            rememberedLocation: nil
        )

        let result = try AddBatchPreflight(
            analyzer: ImportPolicyAnalyzer(metadata: ParsedPaperMetadata(
                title: "Week One",
                titleProvenance: .filenameFallback
            ))
        ).run(
            urls: [fixture.url],
            existingPapers: [existing],
            documentKind: .classNotes
        )

        #expect(result.exactDuplicates.count == 1)
        #expect(result.ready.isEmpty)
    }

    @MainActor
    @Test("non-research imports keep only trustworthy generalized metadata")
    func nonResearchMetadataIsConservative() throws {
        let repository = LibraryRepository(
            container: try CanopyModelContainer.make(inMemory: true)
        )
        let candidate = PreflightCandidate(
            url: URL(fileURLWithPath: "/Lecture/Week One.pdf"),
            fingerprint: Data(repeating: 7, count: 32),
            fileSize: 256,
            modificationDate: nil,
            metadata: ParsedPaperMetadata(
                title: "Week One",
                titleProvenance: .firstPage,
                authors: [
                    ParsedAuthorCredit(
                        displayName: "A Guess",
                        familyName: "Guess",
                        provenance: .firstPage
                    ),
                    ParsedAuthorCredit(
                        displayName: "Dr. Rivera",
                        familyName: "Rivera",
                        provenance: .embeddedMetadata
                    )
                ],
                publicationYear: 2026,
                publicationYearProvenance: .firstPage,
                doi: "10.1000/not-research-metadata",
                doiProvenance: .firstPage,
                arxivID: "2601.12345",
                arxivIDProvenance: .firstPage
            )
        )

        let document = try repository.add(
            candidate,
            source: .referenced(bookmarkData: Data([1]), rememberedLocation: candidate.url.path),
            kind: .lectureSlides
        )

        #expect(document.title == "Week One")
        #expect(document.creatorCredits.map(\.displayName) == ["Dr. Rivera"])
        #expect(document.documentDate == nil)
        #expect(document.doi == nil)
        #expect(document.arxivID == nil)
    }

    @MainActor
    @Test("adding directly to a Collection commits the Document and membership atomically")
    func directCollectionImportIsAtomic() throws {
        let repository = LibraryRepository(
            container: try CanopyModelContainer.make(inMemory: true)
        )
        let collection = try repository.createCollection(name: "Course")
        let candidate = PreflightCandidate(
            url: URL(fileURLWithPath: "/Lecture/Week Two.pdf"),
            fingerprint: Data(repeating: 8, count: 32),
            fileSize: 256,
            modificationDate: nil,
            metadata: ParsedPaperMetadata(
                title: "Week Two",
                titleProvenance: .firstPage
            )
        )

        let document = try repository.add(
            candidate,
            source: .referenced(bookmarkData: Data([2]), rememberedLocation: candidate.url.path),
            kind: .lectureSlides,
            toCollection: collection.id
        )

        #expect(try repository.collectionMemberships(for: document.id).map(\.id) == [collection.id])

        let missingCollectionCandidate = PreflightCandidate(
            url: URL(fileURLWithPath: "/Lecture/Week Three.pdf"),
            fingerprint: Data(repeating: 9, count: 32),
            fileSize: 256,
            modificationDate: nil,
            metadata: ParsedPaperMetadata(
                title: "Week Three",
                titleProvenance: .firstPage
            )
        )
        #expect(throws: LibraryRepositoryError.collectionNotFound) {
            try repository.add(
                missingCollectionCandidate,
                source: .referenced(
                    bookmarkData: Data([3]),
                    rememberedLocation: missingCollectionCandidate.url.path
                ),
                kind: .lectureSlides,
                toCollection: UUID()
            )
        }
        #expect(try repository.documents().map(\.title) == ["Week Two"])
    }
}

private struct ImportPolicyAnalyzer: DocumentAnalyzing {
    let metadata: ParsedPaperMetadata

    func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        metadata
    }
}

private struct ImportPolicyTemporaryFile {
    let directory: URL
    let url: URL

    init(contents: Data) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("candidate.pdf")
        try contents.write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
