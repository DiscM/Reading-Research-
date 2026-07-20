import CanopyCore
import Foundation
import Testing
@testable import Canopy

@Suite("Workspace native Undo")
struct WorkspaceUndoTests {
    @MainActor
    @Test("kind and note edits undo and redo their exact values")
    func kindAndNoteUndoRedo() throws {
        let repository = LibraryRepository(
            container: try CanopyModelContainer.make(inMemory: true)
        )
        let document = makeDocument(fingerprintByte: 61, title: "Lecture")
        try repository.insert(document)
        let undoManager = UndoManager()
        let target = WorkspaceUndoTarget()
        var errors: [Error] = []

        try repository.setDocumentKind(.lectureSlides, for: [document.id])
        WorkspaceUndo.register(
            previous: .documentKinds([document.id: .generalDocument]),
            current: .documentKinds([document.id: .lectureSlides]),
            actionName: "Change Document Kind",
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.document(id: document.id)?.kind == .generalDocument)
        undoManager.redo()
        #expect(try repository.document(id: document.id)?.kind == .lectureSlides)

        try repository.updateDocumentNote(documentID: document.id, note: "Remember this")
        WorkspaceUndo.register(
            previous: .documentNote(documentID: document.id, note: ""),
            current: .documentNote(documentID: document.id, note: "Remember this"),
            actionName: "Edit Document Note",
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.document(id: document.id)?.documentNote == "")
        undoManager.redo()
        #expect(try repository.document(id: document.id)?.documentNote == "Remember this")
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("membership undo restores a mixed selection exactly")
    func membershipUndoRedo() throws {
        let repository = LibraryRepository(
            container: try CanopyModelContainer.make(inMemory: true)
        )
        let first = makeDocument(fingerprintByte: 62, title: "First")
        let second = makeDocument(fingerprintByte: 63, title: "Second")
        try repository.insert(first)
        try repository.insert(second)
        let collection = try repository.createCollection(name: "Course")
        try repository.addDocuments([first.id], toCollection: collection.id)
        let undoManager = UndoManager()
        let target = WorkspaceUndoTarget()
        var errors: [Error] = []

        try repository.addDocuments([first.id, second.id], toCollection: collection.id)
        WorkspaceUndo.register(
            previous: .collectionMembership(
                collectionID: collection.id,
                documentIDs: [first.id, second.id],
                memberDocumentIDs: [first.id]
            ),
            current: .collectionMembership(
                collectionID: collection.id,
                documentIDs: [first.id, second.id],
                memberDocumentIDs: [first.id, second.id]
            ),
            actionName: "Add to Collection",
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.collectionMemberships(for: first.id).map(\.id) == [collection.id])
        #expect(try repository.collectionMemberships(for: second.id).isEmpty)
        undoManager.redo()
        #expect(try repository.collectionMemberships(for: second.id).map(\.id) == [collection.id])
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("Collection deletion undo restores the same Collection and memberships")
    func collectionDeletionUndoRedo() throws {
        let repository = LibraryRepository(
            container: try CanopyModelContainer.make(inMemory: true)
        )
        let document = makeDocument(fingerprintByte: 64, title: "Reading")
        try repository.insert(document)
        let collection = try repository.createCollection(name: "Seminar")
        try repository.addDocuments([document.id], toCollection: collection.id)
        let snapshot = try repository.collectionSnapshot(id: collection.id)
        try repository.deleteCollection(id: collection.id)
        let undoManager = UndoManager()
        let target = WorkspaceUndoTarget()
        var errors: [Error] = []

        WorkspaceUndo.register(
            previous: .collectionPresence(collectionID: collection.id, snapshot: snapshot),
            current: .collectionPresence(collectionID: collection.id, snapshot: nil),
            actionName: "Delete Collection",
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.collection(id: collection.id)?.name == "Seminar")
        #expect(try repository.collectionMemberships(for: document.id).map(\.id) == [collection.id])
        undoManager.redo()
        #expect(try repository.collection(id: collection.id) == nil)
        #expect(try repository.document(id: document.id) != nil)
        #expect(errors.isEmpty)
    }

    private func makeDocument(fingerprintByte: UInt8, title: String) -> Document {
        Document(
            fingerprint: Data([fingerprintByte]),
            title: title,
            storageMode: .referenced,
            sourceFilename: "\(title).pdf",
            sourceFileSize: 128
        )
    }
}
