import CanopyCore
import Foundation

@MainActor
final class PaperRemovalUndoTarget {}

@MainActor
enum PaperRemovalUndo {
    static func register(
        snapshot: RemovedPaperSnapshot,
        repository: LibraryRepository,
        managedStore: ManagedPaperStore? = nil,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager?,
        onError: @escaping (Error) -> Void
    ) {
        register(
            snapshots: [snapshot],
            repository: repository,
            managedStore: managedStore,
            target: target,
            undoManager: undoManager,
            onError: onError
        )
    }

    static func register(
        snapshots: [RemovedPaperSnapshot],
        repository: LibraryRepository,
        managedStore: ManagedPaperStore? = nil,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager?,
        onError: @escaping (Error) -> Void
    ) {
        guard !snapshots.isEmpty else { return }
        guard let undoManager else { return }
        registerRestore(
            snapshots: snapshots,
            repository: repository,
            managedStore: managedStore,
            target: target,
            undoManager: undoManager,
            onError: onError
        )
    }

    private static func registerRestore(
        snapshots: [RemovedPaperSnapshot],
        repository: LibraryRepository,
        managedStore: ManagedPaperStore?,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                _ = try repository.restoreRemovedDocuments(
                    snapshots: snapshots,
                    managedStore: managedStore
                )
                registerRemove(
                    documentIDs: snapshots.map(\.id),
                    repository: repository,
                    managedStore: managedStore,
                    target: target,
                    undoManager: undoManager,
                    onError: onError
                )
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName(actionName(for: snapshots.count))
    }

    private static func registerRemove(
        documentIDs: [UUID],
        repository: LibraryRepository,
        managedStore: ManagedPaperStore?,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                let snapshots = try repository.removeDocuments(
                    documentIDs: documentIDs,
                    managedStore: managedStore
                )
                registerRestore(
                    snapshots: snapshots,
                    repository: repository,
                    managedStore: managedStore,
                    target: target,
                    undoManager: undoManager,
                    onError: onError
                )
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName(actionName(for: documentIDs.count))
    }

    private static func actionName(for documentCount: Int) -> String {
        documentCount == 1 ? "Remove Document" : "Remove Documents"
    }
}
