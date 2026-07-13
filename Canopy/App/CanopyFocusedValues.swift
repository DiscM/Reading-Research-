import SwiftUI

struct PaperInfoCommandAction {
    let perform: @MainActor () -> Void
}

private struct PaperInfoCommandActionKey: FocusedValueKey {
    typealias Value = PaperInfoCommandAction
}

extension FocusedValues {
    var paperInfoCommandAction: PaperInfoCommandAction? {
        get { self[PaperInfoCommandActionKey.self] }
        set { self[PaperInfoCommandActionKey.self] = newValue }
    }
}
