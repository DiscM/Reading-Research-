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
        guard let undoManager else { return }
        registerRestore(
            snapshot: snapshot,
            repository: repository,
            managedStore: managedStore,
            target: target,
            undoManager: undoManager,
            onError: onError
        )
    }

    private static func registerRestore(
        snapshot: RemovedPaperSnapshot,
        repository: LibraryRepository,
        managedStore: ManagedPaperStore?,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                _ = try repository.restoreRemovedPaper(
                    snapshot: snapshot,
                    managedStore: managedStore
                )
                registerRemove(
                    paperID: snapshot.id,
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
        undoManager.setActionName("Remove Paper")
    }

    private static func registerRemove(
        paperID: UUID,
        repository: LibraryRepository,
        managedStore: ManagedPaperStore?,
        target: PaperRemovalUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                let snapshot = try repository.removePaper(
                    paperID: paperID,
                    managedStore: managedStore
                )
                registerRestore(
                    snapshot: snapshot,
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
        undoManager.setActionName("Remove Paper")
    }
}
