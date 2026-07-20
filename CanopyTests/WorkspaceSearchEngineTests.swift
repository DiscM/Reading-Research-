import CanopyCore
import Foundation
import Testing
@testable import Canopy

@Suite("Grouped workspace search")
struct WorkspaceSearchEngineTests {
    @Test("groups Documents and ranks title, metadata, then indexed PDF matches")
    func groupsAndRanksSearchSources() throws {
        let titleDocument = document(
            id: "00000000-0000-0000-0000-000000000001",
            fingerprintByte: 0x01,
            title: "Mitosis Study Guide"
        )
        let metadataDocument = document(
            id: "00000000-0000-0000-0000-000000000002",
            fingerprintByte: 0x02,
            title: "Week Seven",
            collectionNames: ["Mitosis Review"]
        )
        let bodyDocument = document(
            id: "00000000-0000-0000-0000-000000000003",
            fingerprintByte: 0x03,
            title: "Cell Cycle Handout"
        )
        let bodyKey = try PDFTextIndexKey(
            fingerprint: bodyDocument.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )
        let bodyHit = PDFTextSearchHit(
            key: bodyKey,
            pageIndex: 4,
            snippet: "Chromosomes align during mitosis.",
            relevanceScore: -1.25
        )

        let groups = WorkspaceSearchEngine.search(
            query: "mitosis",
            documents: [bodyDocument, metadataDocument, titleDocument],
            pdfTextHits: [bodyHit],
            scope: .all
        )

        #expect(groups.map(\.documentID) == [
            titleDocument.id,
            metadataDocument.id,
            bodyDocument.id
        ])
        #expect(groups.map { $0.childHits.first?.source } == [
            .title,
            .collection,
            .pdfBody
        ])
        #expect(groups.last?.childHits.first?.pageIndex == 4)
    }

    @Test("orders every local source ahead of body text and exposes three initial matches")
    func ranksChildHitsAndCapsInitialMatches() throws {
        let annotationID = UUID(uuidString: "00000000-0000-0000-0000-000000000110")!
        let searchableDocument = document(
            id: "00000000-0000-0000-0000-000000000010",
            fingerprintByte: 0x10,
            title: "Lecture on Cell Division",
            collectionNames: ["Lecture Review"],
            creatorNames: ["Lecture Faculty"],
            kind: .lectureSlides,
            documentNote: "Revisit the lecture before the exam.",
            annotations: [
                WorkspaceSearchAnnotation(
                    id: annotationID,
                    pageIndex: 6,
                    note: "Explain this lecture diagram.",
                    selectedQuotation: "The lecture calls this metaphase."
                )
            ]
        )
        let key = try PDFTextIndexKey(
            fingerprint: searchableDocument.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )
        let pdfHit = PDFTextSearchHit(
            key: key,
            pageIndex: 8,
            snippet: "Body text from the lecture.",
            relevanceScore: -2
        )

        let group = try #require(WorkspaceSearchEngine.search(
            query: "lecture",
            documents: [searchableDocument],
            pdfTextHits: [pdfHit],
            scope: .all
        ).first)

        #expect(group.childHits.map(\.source) == [
            .title,
            .collection,
            .creator,
            .documentKind,
            .documentNote,
            .annotationNote,
            .annotationQuotation,
            .pdfBody
        ])
        #expect(group.initialChildHits.count == 3)
        #expect(group.additionalMatchCount == 5)
        let annotationNote = try #require(group.childHits.first { $0.source == .annotationNote })
        #expect(annotationNote.pageIndex == 6)
        #expect(annotationNote.annotationID == annotationID)
        #expect(group.childHits.last?.pageNumber == 9)
    }

    @Test("scopes by allowed Document IDs and fingerprints while searching Document Date")
    func scopesIDsFingerprintsAndDateMetadata() throws {
        let datedDocument = document(
            id: "00000000-0000-0000-0000-000000000020",
            fingerprintByte: 0x20,
            title: "Course Timeline",
            documentDate: DocumentDate(year: 2026, month: 7)
        )
        let bodyDocument = document(
            id: "00000000-0000-0000-0000-000000000021",
            fingerprintByte: 0x21,
            title: "Archived Notes"
        )
        let bodyKey = try PDFTextIndexKey(
            fingerprint: bodyDocument.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )
        let bodyHit = PDFTextSearchHit(
            key: bodyKey,
            pageIndex: 2,
            snippet: "The course was revised in 2026.",
            relevanceScore: -1
        )
        let documents = [datedDocument, bodyDocument]

        let idScoped = WorkspaceSearchEngine.search(
            query: "2026",
            documents: documents,
            pdfTextHits: [bodyHit],
            scope: WorkspaceSearchScope(allowedDocumentIDs: [datedDocument.id])
        )
        let fingerprintScoped = WorkspaceSearchEngine.search(
            query: "2026",
            documents: documents,
            pdfTextHits: [bodyHit],
            scope: WorkspaceSearchScope(allowedFingerprints: [bodyDocument.fingerprint])
        )
        let intersectionScoped = WorkspaceSearchEngine.search(
            query: "2026",
            documents: documents,
            pdfTextHits: [bodyHit],
            scope: WorkspaceSearchScope(
                allowedDocumentIDs: [datedDocument.id],
                allowedFingerprints: [bodyDocument.fingerprint]
            )
        )

        #expect(idScoped.map(\.documentID) == [datedDocument.id])
        #expect(idScoped.first?.childHits.first?.source == .documentDate)
        #expect(fingerprintScoped.map(\.documentID) == [bodyDocument.id])
        #expect(intersectionScoped.isEmpty)
    }

    @Test("matches all normalized query tokens and centers a bounded note snippet on a match")
    func tokenizesQueryAndBuildsBoundedSnippet() throws {
        let longPrefix = String(repeating: "introductory context ", count: 14)
        let searchableDocument = document(
            id: "00000000-0000-0000-0000-000000000030",
            fingerprintByte: 0x30,
            title: "Plant Biology",
            documentNote: "\(longPrefix)VÁSCULAR tissue is produced by the CAMBIUM near the stem."
        )

        let group = try #require(WorkspaceSearchEngine.search(
            query: "cambium, vascular!",
            documents: [searchableDocument],
            pdfTextHits: [],
            scope: .all
        ).first)
        let noteHit = try #require(group.childHits.first)

        #expect(noteHit.source == .documentNote)
        #expect(noteHit.snippet.count <= 160)
        #expect(noteHit.snippet.localizedCaseInsensitiveContains("cambium"))
        #expect(noteHit.snippet.hasPrefix("…"))
    }

    @Test("builds a deterministic search snapshot from one persisted Document")
    func buildsSnapshotFromDocument() {
        let laterCreator = CreatorCredit(
            position: 1,
            displayName: "Alan Turing",
            familyName: "Turing",
            provenance: .userEntry
        )
        let firstCreator = CreatorCredit(
            position: 0,
            displayName: "Ada Lovelace",
            familyName: "Lovelace",
            provenance: .userEntry
        )
        let source = Document(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            fingerprint: Data(repeating: 0x40, count: 32),
            title: "Computing Notes",
            kind: .classNotes,
            documentDate: DocumentDate(year: 2026, month: 7, day: 20),
            documentNote: "Review before class.",
            storageMode: .referenced,
            sourceFilename: "Computing Notes.pdf",
            sourceFileSize: 100,
            authorCredits: [laterCreator, firstCreator]
        )
        source.collections = [
            Collection(name: "Final Review"),
            Collection(name: "CS 101")
        ]

        let snapshot = WorkspaceSearchDocument(document: source)

        #expect(snapshot.id == source.id)
        #expect(snapshot.creatorNames == ["Ada Lovelace", "Alan Turing"])
        #expect(snapshot.collectionNames == ["CS 101", "Final Review"])
        #expect(snapshot.annotations.isEmpty)
    }

    @Test("orders body-only Document groups by the supplied full-text relevance score")
    func ordersBodyGroupsByRelevance() throws {
        let weaker = document(
            id: "00000000-0000-0000-0000-000000000050",
            fingerprintByte: 0x50,
            title: "A Weaker Match"
        )
        let stronger = document(
            id: "00000000-0000-0000-0000-000000000051",
            fingerprintByte: 0x51,
            title: "Z Stronger Match"
        )
        let weakerKey = try PDFTextIndexKey(
            fingerprint: weaker.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )
        let strongerKey = try PDFTextIndexKey(
            fingerprint: stronger.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )

        let groups = WorkspaceSearchEngine.search(
            query: "osmosis",
            documents: [weaker, stronger],
            pdfTextHits: [
                PDFTextSearchHit(
                    key: weakerKey,
                    pageIndex: 0,
                    snippet: "A weaker osmosis match.",
                    relevanceScore: -1
                ),
                PDFTextSearchHit(
                    key: strongerKey,
                    pageIndex: 3,
                    snippet: "A stronger osmosis match.",
                    relevanceScore: -8
                )
            ],
            scope: .all
        )

        #expect(groups.map(\.documentID) == [stronger.id, weaker.id])
    }

    private func document(
        id: String,
        fingerprintByte: UInt8,
        title: String,
        collectionNames: [String] = [],
        creatorNames: [String] = [],
        kind: DocumentKind = .generalDocument,
        documentDate: DocumentDate? = nil,
        documentNote: String = "",
        annotations: [WorkspaceSearchAnnotation] = []
    ) -> WorkspaceSearchDocument {
        WorkspaceSearchDocument(
            id: UUID(uuidString: id)!,
            fingerprint: Data(repeating: fingerprintByte, count: 32),
            title: title,
            collectionNames: collectionNames,
            creatorNames: creatorNames,
            kind: kind,
            documentDate: documentDate,
            documentNote: documentNote,
            annotations: annotations
        )
    }
}
