import Foundation
import SwiftData
import Testing
@testable import CanopyCore

@Suite("General workspace persistence")
struct GeneralWorkspacePersistenceTests {
    @MainActor
    @Test("repository stores generalized Documents with a default kind")
    func storesGeneralizedDocumentWithDefaultKind() throws {
        let repository = try makeRepository()
        let document = makeDocument(title: "Lecture 1")

        try repository.insert(document)

        let stored = try #require(repository.documents().first)
        #expect(stored.id == document.id)
        #expect(stored.kind == .generalDocument)
    }

    @MainActor
    @Test("a Document Note is updated through the repository")
    func updatesDocumentNote() throws {
        let repository = try makeRepository()
        let document = makeDocument(title: "Cell Biology")
        try repository.insert(document)

        try repository.updateDocumentNote(
            documentID: document.id,
            note: "Key idea: membranes are selectively permeable.\nReview slide 18."
        )

        let stored = try #require(try repository.document(id: document.id))
        #expect(stored.documentNote == "Key idea: membranes are selectively permeable.\nReview slide 18.")
    }

    @MainActor
    @Test("Document Date preserves year, month, and day precision")
    func preservesDocumentDatePrecision() throws {
        let repository = try makeRepository()
        let document = makeDocument(title: "Course Materials")
        try repository.insert(document)
        let dates = [
            try #require(DocumentDate(year: 2024)),
            try #require(DocumentDate(year: 2025, month: 9)),
            try #require(DocumentDate(year: 2026, month: 7, day: 20))
        ]

        for date in dates {
            try repository.updateDocumentDate(documentID: document.id, date: date)
            let stored = try #require(try repository.document(id: document.id))
            #expect(stored.documentDate == date)
            #expect(stored.documentDate?.precision == date.precision)
        }

        try repository.updateDocumentDate(documentID: document.id, date: nil)
        #expect(try repository.document(id: document.id)?.documentDate == nil)
    }

    @MainActor
    @Test("Document Info edits preserve a precision-aware Document Date")
    func documentInfoPreservesDatePrecision() throws {
        let repository = try makeRepository()
        let date = try #require(DocumentDate(year: 2026, month: 7, day: 20))
        let document = Document(
            fingerprint: Data([13]),
            title: "Course Notes",
            titleProvenance: .firstPage,
            publicationYear: date.year,
            publicationYearProvenance: .embeddedMetadata,
            kind: .classNotes,
            documentDate: date,
            storageMode: .referenced,
            sourceFilename: "course-notes.pdf",
            sourceFileSize: 128
        )
        try repository.insert(document)

        _ = try repository.updatePaperInfo(
            paperID: document.id,
            update: PaperInfoUpdate(
                title: "Edited Course Notes",
                publicationYear: 2026,
                doi: nil,
                arxivID: nil,
                authorCredits: []
            )
        )

        let stored = try #require(try repository.document(id: document.id))
        #expect(stored.documentDate == date)
        #expect(stored.documentDateProvenance == .embeddedMetadata)
    }

    @MainActor
    @Test("Document Kind can be changed for a selected set atomically")
    func bulkUpdatesDocumentKind() throws {
        let repository = try makeRepository()
        let lecture = makeDocument(fingerprintByte: 2, title: "Lecture 2")
        let review = makeDocument(fingerprintByte: 3, title: "Midterm Review")
        try repository.insert(lecture)
        try repository.insert(review)

        try repository.setDocumentKind(.lectureSlides, for: [lecture.id, review.id])

        #expect(try repository.document(id: lecture.id)?.kind == .lectureSlides)
        #expect(try repository.document(id: review.id)?.kind == .lectureSlides)
    }

    @MainActor
    @Test("creating a Collection trims its name and makes it browsable")
    func createsCollection() throws {
        let repository = try makeRepository()

        let collection = try repository.createCollection(name: "  BIO 201 \n")

        #expect(collection.name == "BIO 201")
        #expect(try repository.collections().map(\.id) == [collection.id])
    }

    @MainActor
    @Test("creating a Collection from a selection is atomic")
    func createsCollectionFromSelectionAtomically() throws {
        let repository = try makeRepository()
        let document = makeDocument(fingerprintByte: 14, title: "Reading")
        try repository.insert(document)

        let collection = try repository.createCollection(
            name: "Seminar",
            documentIDs: [document.id]
        )
        #expect(try repository.collectionMemberships(for: document.id).map(\.id) == [collection.id])

        #expect(throws: LibraryRepositoryError.documentNotFound) {
            try repository.createCollection(name: "Broken", documentIDs: [UUID()])
        }
        #expect(try repository.collections().map(\.name) == ["Seminar"])
    }

    @MainActor
    @Test("renaming a Collection persists its normalized name")
    func renamesCollection() throws {
        let repository = try makeRepository()
        let collection = try repository.createCollection(name: "Review")

        try repository.renameCollection(id: collection.id, name: "  Midterm Review  ")

        #expect(try repository.collection(id: collection.id)?.name == "Midterm Review")
    }

    @MainActor
    @Test("adding Documents to a Collection is many-to-many and idempotent")
    func addsCollectionMembershipsIdempotently() throws {
        let repository = try makeRepository()
        let slides = makeDocument(fingerprintByte: 4, title: "Lecture Slides")
        let notes = makeDocument(fingerprintByte: 5, title: "Class Notes")
        try repository.insert(slides)
        try repository.insert(notes)
        let course = try repository.createCollection(name: "BIO 201")
        let exam = try repository.createCollection(name: "Midterm")

        try repository.addDocuments([slides.id, notes.id], toCollection: course.id)
        try repository.addDocuments([slides.id], toCollection: course.id)
        try repository.addDocuments([slides.id], toCollection: exam.id)

        #expect(try repository.collectionMemberships(for: slides.id).map(\.name) == ["BIO 201", "Midterm"])
        #expect(try repository.collectionMemberships(for: notes.id).map(\.name) == ["BIO 201"])
        #expect(try repository.collection(id: course.id)?.documents.count == 2)
    }

    @MainActor
    @Test("removing one Collection membership preserves the Document and its other memberships")
    func removesOnlyRequestedCollectionMembership() throws {
        let repository = try makeRepository()
        let document = makeDocument(fingerprintByte: 6, title: "Membranes")
        try repository.insert(document)
        let course = try repository.createCollection(name: "BIO 201")
        let exam = try repository.createCollection(name: "Final")
        try repository.addDocuments([document.id], toCollection: course.id)
        try repository.addDocuments([document.id], toCollection: exam.id)

        try repository.removeDocuments([document.id], fromCollection: course.id)
        try repository.removeDocuments([document.id], fromCollection: course.id)

        #expect(try repository.collectionMemberships(for: document.id).map(\.name) == ["Final"])
        #expect(try repository.document(id: document.id)?.title == "Membranes")
    }

    @MainActor
    @Test("deleting a Collection preserves every member Document")
    func deletesCollectionWithoutDeletingDocuments() throws {
        let repository = try makeRepository()
        let document = makeDocument(fingerprintByte: 7, title: "Cell Cycle")
        try repository.insert(document)
        let collection = try repository.createCollection(name: "BIO 201")
        try repository.addDocuments([document.id], toCollection: collection.id)

        try repository.deleteCollection(id: collection.id)

        #expect(try repository.collection(id: collection.id) == nil)
        #expect(try repository.document(id: document.id)?.title == "Cell Cycle")
        #expect(try repository.collectionMemberships(for: document.id).isEmpty)
    }

    @MainActor
    @Test("Collection names are required and case-insensitively unique")
    func validatesCollectionNames() throws {
        let repository = try makeRepository()
        let biology = try repository.createCollection(name: "BIO 201")
        let review = try repository.createCollection(name: "Review")

        #expect(throws: LibraryRepositoryError.invalidCollectionName) {
            try repository.createCollection(name: " \n ")
        }
        #expect(throws: LibraryRepositoryError.duplicateCollectionName) {
            try repository.createCollection(name: "bio 201")
        }
        #expect(throws: LibraryRepositoryError.duplicateCollectionName) {
            try repository.renameCollection(id: review.id, name: "  bio 201 ")
        }

        #expect(try repository.collection(id: biology.id)?.name == "BIO 201")
        #expect(try repository.collection(id: review.id)?.name == "Review")
    }

    @MainActor
    @Test("a missing Document rejects a bulk kind update before any Document changes")
    func bulkKindUpdateIsAtomic() throws {
        let repository = try makeRepository()
        let document = makeDocument(fingerprintByte: 8, title: "Lecture")
        try repository.insert(document)

        #expect(throws: LibraryRepositoryError.documentNotFound) {
            try repository.setDocumentKind(.lectureSlides, for: [document.id, UUID()])
        }

        #expect(try repository.document(id: document.id)?.kind == .generalDocument)
    }

    @MainActor
    @Test("removal undo restores generalized Document state and Collection memberships")
    func removalUndoRestoresGeneralizedState() throws {
        let repository = try makeRepository()
        let date = try #require(DocumentDate(year: 2026, month: 7, day: 20))
        let document = Document(
            fingerprint: Data([9]),
            title: "Lecture Notes",
            kind: .classNotes,
            documentDate: date,
            documentNote: "Review diagrams before the final.",
            storageMode: .referenced,
            sourceFilename: "lecture-notes.pdf",
            sourceFileSize: 128
        )
        try repository.insert(document)
        let collection = try repository.createCollection(name: "BIO 201")
        try repository.addDocuments([document.id], toCollection: collection.id)

        let snapshot = try repository.removePaper(paperID: document.id)
        let restored = try repository.restoreRemovedPaper(snapshot: snapshot)

        #expect(restored.kind == .classNotes)
        #expect(restored.documentDate == date)
        #expect(restored.documentNote == "Review diagrams before the final.")
        #expect(try repository.collectionMemberships(for: restored.id).map(\.name) == ["BIO 201"])
    }

    @MainActor
    @Test("workspace edit snapshots restore kinds, date provenance, and exact memberships")
    func restoresWorkspaceEditSnapshots() throws {
        let repository = try makeRepository()
        let slides = makeDocument(fingerprintByte: 10, title: "Slides")
        let notes = makeDocument(fingerprintByte: 11, title: "Notes")
        try repository.insert(slides)
        try repository.insert(notes)
        let course = try repository.createCollection(name: "BIO 201")
        try repository.addDocuments([slides.id], toCollection: course.id)

        try repository.setDocumentKinds([
            slides.id: .lectureSlides,
            notes.id: .classNotes
        ])
        let embeddedDate = try #require(DocumentDate(year: 2025, month: 9))
        try repository.setDocumentDate(
            embeddedDate,
            provenance: .embeddedMetadata,
            for: slides.id
        )
        try repository.setCollectionMembership(
            collectionID: course.id,
            documentIDs: [slides.id, notes.id],
            memberDocumentIDs: [notes.id]
        )

        #expect(try repository.document(id: slides.id)?.kind == .lectureSlides)
        #expect(try repository.document(id: notes.id)?.kind == .classNotes)
        #expect(try repository.document(id: slides.id)?.documentDate == embeddedDate)
        #expect(try repository.document(id: slides.id)?.documentDateProvenance == .embeddedMetadata)
        #expect(try repository.collectionMemberships(for: slides.id).isEmpty)
        #expect(try repository.collectionMemberships(for: notes.id).map(\.id) == [course.id])
    }

    @MainActor
    @Test("a deleted Collection snapshot restores identity and memberships")
    func restoresCollectionSnapshot() throws {
        let repository = try makeRepository()
        let document = makeDocument(fingerprintByte: 12, title: "Handout")
        try repository.insert(document)
        let collection = try repository.createCollection(name: "Seminar")
        try repository.addDocuments([document.id], toCollection: collection.id)
        let snapshot = try repository.collectionSnapshot(id: collection.id)

        try repository.deleteCollection(id: collection.id)
        try repository.restoreCollection(snapshot)

        let restored = try #require(try repository.collection(id: collection.id))
        #expect(restored.name == "Seminar")
        #expect(restored.dateCreated == collection.dateCreated)
        #expect(try repository.collectionMemberships(for: document.id).map(\.id) == [collection.id])
    }

    @MainActor
    private func makeRepository() throws -> LibraryRepository {
        LibraryRepository(container: try CanopyModelContainer.make(inMemory: true))
    }

    private func makeDocument(
        id: UUID = UUID(),
        fingerprintByte: UInt8 = 1,
        title: String
    ) -> Document {
        Document(
            id: id,
            fingerprint: Data([fingerprintByte]),
            title: title,
            storageMode: .referenced,
            sourceFilename: "\(title).pdf",
            sourceFileSize: 128
        )
    }
}
