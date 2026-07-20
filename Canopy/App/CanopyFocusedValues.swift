import SwiftUI

struct AddDocumentsCommandAction {
    let perform: @MainActor () -> Void
}

struct DocumentInfoCommandAction {
    let perform: @MainActor () -> Void
}

enum DocumentCommand: Hashable {
    case focusFind
    case nextFindMatch
    case previousFindMatch
    case zoomIn
    case zoomOut
    case fitWidth
    case actualSize
    case toggleInspector
    case startAreaAnnotation

    static func availableReaderCommands(
        hasFindMatches: Bool,
        hasSelectableText: Bool = true
    ) -> Set<DocumentCommand> {
        var commands: Set<DocumentCommand> = [
            .zoomIn,
            .zoomOut,
            .fitWidth,
            .actualSize,
            .toggleInspector,
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

struct DocumentCommandContext {
    let availableCommands: Set<DocumentCommand>
    let perform: @MainActor (DocumentCommand) -> Void

    func canPerform(_ command: DocumentCommand) -> Bool {
        availableCommands.contains(command)
    }
}

enum WorkspaceCommand: Hashable {
    case toggleNavigationSidebar
    case toggleDocumentList
    case toggleInspector
    case showOverview
    case showAnnotations
    case focusSearch
    case focusContextualSearch
}

struct WorkspaceCommandContext {
    let perform: @MainActor (WorkspaceCommand) -> Void
}

private struct DocumentInfoCommandActionKey: FocusedValueKey {
    typealias Value = DocumentInfoCommandAction
}

private struct AddDocumentsCommandActionKey: FocusedValueKey {
    typealias Value = AddDocumentsCommandAction
}

private struct DocumentCommandContextKey: FocusedValueKey {
    typealias Value = DocumentCommandContext
}

private struct WorkspaceCommandContextKey: FocusedValueKey {
    typealias Value = WorkspaceCommandContext
}

extension FocusedValues {
    var addDocumentsCommandAction: AddDocumentsCommandAction? {
        get { self[AddDocumentsCommandActionKey.self] }
        set { self[AddDocumentsCommandActionKey.self] = newValue }
    }

    var documentInfoCommandAction: DocumentInfoCommandAction? {
        get { self[DocumentInfoCommandActionKey.self] }
        set { self[DocumentInfoCommandActionKey.self] = newValue }
    }

    var documentCommandContext: DocumentCommandContext? {
        get { self[DocumentCommandContextKey.self] }
        set { self[DocumentCommandContextKey.self] = newValue }
    }


    var workspaceCommandContext: WorkspaceCommandContext? {
        get { self[WorkspaceCommandContextKey.self] }
        set { self[WorkspaceCommandContextKey.self] = newValue }
    }
}
