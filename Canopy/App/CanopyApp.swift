import CanopyCore
import SwiftData
import SwiftUI

@main
struct CanopyApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try CanopyModelContainer.make()
            try? LibraryRepository(container: container).reconcileManagedPaperRecovery()
        } catch {
            fatalError("Unable to open Canopy's library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 760)
        .commands {
            CanopyCommands()
        }
    }
}

private struct CanopyCommands: Commands {
    @FocusedValue(\.paperInfoCommandAction) private var paperInfoCommandAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Papers…") {
                NotificationCenter.default.post(name: .addPapersRequested, object: nil)
            }
                .keyboardShortcut("o")

            Divider()

            Button("Get Info") {
                paperInfoCommandAction?.perform()
            }
            .keyboardShortcut("i")
            .disabled(paperInfoCommandAction == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in Paper…") {
                NotificationCenter.default.post(name: .findInPaperRequested, object: nil)
            }
            .keyboardShortcut("f")
        }
    }
}
