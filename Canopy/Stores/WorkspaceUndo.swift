import CanopyCore
import Foundation

@MainActor
final class WorkspaceUndoTarget {}

enum WorkspaceUndoSnapshot {
    case documentKinds([UUID: DocumentKind])
    case documentNote(documentID: UUID, note: String)
    case documentDate(
        documentID: UUID,
        date: DocumentDate?,
        provenance: MetadataProvenance?
    )
    case collectionMembership(
        collectionID: UUID,
        documentIDs: [UUID],
        memberDocumentIDs: Set<UUID>
    )
    case collectionPresence(collectionID: UUID, snapshot: CollectionSnapshot?)
    case collectionName(collectionID: UUID, name: String)
}

@MainActor
enum WorkspaceUndo {
    static func register(
        previous: WorkspaceUndoSnapshot,
        current: WorkspaceUndoSnapshot,
        actionName: String,
        repository: LibraryRepository,
        target: WorkspaceUndoTarget,
        undoManager: UndoManager?,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager else { return }
        registerApply(
            snapshot: previous,
            inverse: current,
            actionName: actionName,
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: onError
        )
    }

    private static func registerApply(
        snapshot: WorkspaceUndoSnapshot,
        inverse: WorkspaceUndoSnapshot,
        actionName: String,
        repository: LibraryRepository,
        target: WorkspaceUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                try apply(snapshot, repository: repository)
                registerApply(
                    snapshot: inverse,
                    inverse: snapshot,
                    actionName: actionName,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    onError: onError
                )
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName(actionName)
    }

    private static func apply(
        _ snapshot: WorkspaceUndoSnapshot,
        repository: LibraryRepository
    ) throws {
        switch snapshot {
        case let .documentKinds(kinds):
            try repository.setDocumentKinds(kinds)
        case let .documentNote(documentID, note):
            try repository.updateDocumentNote(documentID: documentID, note: note)
        case let .documentDate(documentID, date, provenance):
            try repository.setDocumentDate(date, provenance: provenance, for: documentID)
        case let .collectionMembership(collectionID, documentIDs, memberDocumentIDs):
            try repository.setCollectionMembership(
                collectionID: collectionID,
                documentIDs: documentIDs,
                memberDocumentIDs: memberDocumentIDs
            )
        case let .collectionPresence(collectionID, snapshot):
            if let snapshot {
                if try repository.collection(id: collectionID) == nil {
                    try repository.restoreCollection(snapshot)
                }
            } else if try repository.collection(id: collectionID) != nil {
                try repository.deleteCollection(id: collectionID)
            }
        case let .collectionName(collectionID, name):
            try repository.renameCollection(id: collectionID, name: name)
        }
    }
}
