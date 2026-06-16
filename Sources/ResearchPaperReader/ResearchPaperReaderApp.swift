import SwiftUI

@main
struct ResearchPaperReaderApp: App {
    @StateObject private var store = PaperStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Papers...") {
                    store.importWithOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .frame(width: 520)
                .padding()
        }
    }
}
