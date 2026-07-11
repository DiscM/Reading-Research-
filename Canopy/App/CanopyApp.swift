import CanopyCore
import SwiftData
import SwiftUI

@main
struct CanopyApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try CanopyModelContainer.make()
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
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Import PDFs…") {}
                .keyboardShortcut("o")
        }
    }
}

