import SwiftUI

private enum AppWindowMetrics {
    static let minimumSize = CGSize(width: 960, height: 640)
    static let defaultSize = CGSize(width: 1180, height: 760)
}

@main
struct ResearchPaperReaderApp: App {
    @State private var store = PaperStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(.accentColor)
                .frame(
                    minWidth: AppWindowMetrics.minimumSize.width,
                    minHeight: AppWindowMetrics.minimumSize.height
                )
                .background {
                    WindowBoundsEnforcer(
                        minimumSize: AppWindowMetrics.minimumSize
                    )
                }
        }
        .defaultWindowPlacement { _, context in
            WindowPlacement(
                size: AppWindowMetrics.defaultSize.fitted(to: context.defaultDisplay.visibleRect.size)
            )
        }
        .windowIdealPlacement { _, context in
            WindowPlacement(
                size: AppWindowMetrics.defaultSize.fitted(to: context.defaultDisplay.visibleRect.size)
            )
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import PDF Documents...") {
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
