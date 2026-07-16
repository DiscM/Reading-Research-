import SwiftUI

struct AddPapersCommandAction {
    let perform: @MainActor () -> Void
}

struct PaperInfoCommandAction {
    let perform: @MainActor () -> Void
}

enum PaperCommand: Hashable {
    case focusFind
    case nextFindMatch
    case previousFindMatch
    case zoomIn
    case zoomOut
    case fitWidth
    case actualSize
    case toggleAnnotations
    case startAreaAnnotation

    static func availableReaderCommands(
        hasFindMatches: Bool,
        hasSelectableText: Bool = true
    ) -> Set<PaperCommand> {
        var commands: Set<PaperCommand> = [
            .zoomIn,
            .zoomOut,
            .fitWidth,
            .actualSize,
            .toggleAnnotations,
            .startAreaAnnotation
        ]
        if hasSelectableText {
            commands.insert(.focusFind)
            if hasFindMatches {
                commands.formUnion([.nextFindMatch, .previousFindMatch])
            }
        }
        return commands
    }
}

struct PaperCommandContext {
    let availableCommands: Set<PaperCommand>
    let perform: @MainActor (PaperCommand) -> Void

    func canPerform(_ command: PaperCommand) -> Bool {
        availableCommands.contains(command)
    }
}

private struct PaperInfoCommandActionKey: FocusedValueKey {
    typealias Value = PaperInfoCommandAction
}

private struct AddPapersCommandActionKey: FocusedValueKey {
    typealias Value = AddPapersCommandAction
}

private struct PaperCommandContextKey: FocusedValueKey {
    typealias Value = PaperCommandContext
}

extension FocusedValues {
    var addPapersCommandAction: AddPapersCommandAction? {
        get { self[AddPapersCommandActionKey.self] }
        set { self[AddPapersCommandActionKey.self] = newValue }
    }

    var paperInfoCommandAction: PaperInfoCommandAction? {
        get { self[PaperInfoCommandActionKey.self] }
        set { self[PaperInfoCommandActionKey.self] = newValue }
    }

    var paperCommandContext: PaperCommandContext? {
        get { self[PaperCommandContextKey.self] }
        set { self[PaperCommandContextKey.self] = newValue }
    }
}
