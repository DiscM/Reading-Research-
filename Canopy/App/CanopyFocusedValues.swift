import SwiftUI

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

    static func availableReaderCommands(hasFindMatches: Bool) -> Set<PaperCommand> {
        var commands: Set<PaperCommand> = [
            .focusFind,
            .zoomIn,
            .zoomOut,
            .fitWidth,
            .actualSize,
            .toggleAnnotations
        ]
        if hasFindMatches {
            commands.formUnion([.nextFindMatch, .previousFindMatch])
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

private struct PaperCommandContextKey: FocusedValueKey {
    typealias Value = PaperCommandContext
}

extension FocusedValues {
    var paperInfoCommandAction: PaperInfoCommandAction? {
        get { self[PaperInfoCommandActionKey.self] }
        set { self[PaperInfoCommandActionKey.self] = newValue }
    }

    var paperCommandContext: PaperCommandContext? {
        get { self[PaperCommandContextKey.self] }
        set { self[PaperCommandContextKey.self] = newValue }
    }
}
