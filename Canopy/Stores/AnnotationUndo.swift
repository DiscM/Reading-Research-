import CanopyCore
import Foundation

@MainActor
final class AnnotationUndoTarget {}

@MainActor
enum AnnotationUndo {
    static func registerUndoForCreation(
        annotationIDs: [UUID],
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager?,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager, !annotationIDs.isEmpty else { return }
        registerDelete(
            annotationIDs: annotationIDs,
            repository: repository,
            target: target,
            undoManager: undoManager,
            actionName: "Add Annotation",
            onChange: onChange,
            onError: onError
        )
    }

    static func registerUndoForDeletion(
        snapshot: AnnotationSnapshot,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager?,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager else { return }
        registerRestore(
            snapshots: [snapshot],
            repository: repository,
            target: target,
            undoManager: undoManager,
            actionName: "Delete Annotation",
            onChange: onChange,
            onError: onError
        )
    }

    static func registerUndoForNoteChange(
        annotationID: UUID,
        previousNote: String,
        currentNote: String,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager?,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager else { return }
        registerNoteChange(
            annotationID: annotationID,
            noteToApply: previousNote,
            inverseNote: currentNote,
            repository: repository,
            target: target,
            undoManager: undoManager,
            onChange: onChange,
            onError: onError
        )
    }

    static func registerUndoForColorChange(
        annotationID: UUID,
        previousColor: HighlightColor,
        currentColor: HighlightColor,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager?,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager else { return }
        registerColorChange(
            annotationID: annotationID,
            colorToApply: previousColor,
            inverseColor: currentColor,
            repository: repository,
            target: target,
            undoManager: undoManager,
            onChange: onChange,
            onError: onError
        )
    }

    static func registerUndoForAnchorChange(
        annotationID: UUID,
        previousAnchor: AnnotationAnchorValue,
        currentAnchor: AnnotationAnchorValue,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager?,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        guard let undoManager else { return }
        registerAnchorChange(
            annotationID: annotationID,
            anchorToApply: previousAnchor,
            inverseAnchor: currentAnchor,
            repository: repository,
            target: target,
            undoManager: undoManager,
            onChange: onChange,
            onError: onError
        )
    }

    private static func registerDelete(
        annotationIDs: [UUID],
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager,
        actionName: String,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                let snapshots = try repository.deleteAnnotations(annotationIDs: annotationIDs)
                registerRestore(
                    snapshots: snapshots,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    actionName: actionName,
                    onChange: onChange,
                    onError: onError
                )
                onChange()
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName(actionName)
    }

    private static func registerRestore(
        snapshots: [AnnotationSnapshot],
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager,
        actionName: String,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                let annotationIDs = try repository.restoreAnnotations(snapshots).map(\.id)
                registerDelete(
                    annotationIDs: annotationIDs,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    actionName: actionName,
                    onChange: onChange,
                    onError: onError
                )
                onChange()
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName(actionName)
    }

    private static func registerNoteChange(
        annotationID: UUID,
        noteToApply: String,
        inverseNote: String,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                try repository.updateAnnotationNote(annotationID: annotationID, note: noteToApply)
                registerNoteChange(
                    annotationID: annotationID,
                    noteToApply: inverseNote,
                    inverseNote: noteToApply,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    onChange: onChange,
                    onError: onError
                )
                onChange()
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName("Edit Annotation Note")
    }

    private static func registerColorChange(
        annotationID: UUID,
        colorToApply: HighlightColor,
        inverseColor: HighlightColor,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                try repository.updateAnnotationColor(annotationID: annotationID, color: colorToApply)
                registerColorChange(
                    annotationID: annotationID,
                    colorToApply: inverseColor,
                    inverseColor: colorToApply,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    onChange: onChange,
                    onError: onError
                )
                onChange()
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName("Change Annotation Color")
    }

    private static func registerAnchorChange(
        annotationID: UUID,
        anchorToApply: AnnotationAnchorValue,
        inverseAnchor: AnnotationAnchorValue,
        repository: LibraryRepository,
        target: AnnotationUndoTarget,
        undoManager: UndoManager,
        onChange: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        undoManager.registerUndo(withTarget: target) { target in
            do {
                try repository.updateAnnotationAnchor(
                    annotationID: annotationID,
                    anchor: anchorToApply
                )
                registerAnchorChange(
                    annotationID: annotationID,
                    anchorToApply: inverseAnchor,
                    inverseAnchor: anchorToApply,
                    repository: repository,
                    target: target,
                    undoManager: undoManager,
                    onChange: onChange,
                    onError: onError
                )
                onChange()
            } catch {
                onError(error)
            }
        }
        undoManager.setActionName("Adjust Annotation")
    }
}
