import CanopyCore
import Foundation

@MainActor
final class PaperInfoUndoTarget {}

@MainActor
enum PaperInfoUndo {
    static func register(
        change: PaperInfoChange,
        repository: LibraryRepository,
        target: PaperInfoUndoTarget,
        undoManager: UndoManager?,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager, change.before != change.after else { return }
        registerApply(
            snapshot: change.before,
            inverseSnapshot: change.after,
            repository: repository,
            target: target,
            undoManager: undoManager,
            onError: onError
        )
    }

    private static func registerApply(
        snapshot: PaperInfoSnapshot,
        inverseSnapshot: PaperInfoSnapshot,
        repository: LibraryRepository,
        target: PaperInfoUndoTarget,
        undoManager: UndoManager,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                _ = try repository.restorePaperInfoSnapshot(snapshot)
                registerApply(
                    snapshot: inverseSnapshot,
                    inverseSnapshot: snapshot,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    onError: onError
                )
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName("Edit Paper Info")
    }
}
