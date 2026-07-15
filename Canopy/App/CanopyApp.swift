import CanopyCore
import SwiftData
import SwiftUI

@main
struct CanopyApp: App {
    private let container: ModelContainer
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

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
            CanopyContentRoot(
                appearanceMode: accessibilityPreferences.appearanceMode,
                accessibilityOverrides: accessibilityPreferences.overrides
            )
        }
        .modelContainer(container)
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CanopyCommands()
        }
    }
}

private struct CanopyContentRoot: View {
    let appearanceMode: CanopyAppearanceMode
    let accessibilityOverrides: CanopyAccessibilityOverrides

    @Environment(\.colorSchemeContrast) private var systemColorSchemeContrast

    var body: some View {
        ContentView()
            .frame(minWidth: 900, minHeight: 600)
            .environment(\.canopyAccessibilityOverrides, accessibilityOverrides)
            .contrast(appContrastAmount)
            .preferredColorScheme(appearanceMode.preferredColorScheme)
    }

    private var appContrastAmount: Double {
        accessibilityOverrides.interfaceContrastAmount(
            systemIncreasedContrast: systemColorSchemeContrast == .increased
        )
    }
}

private struct CanopyCommands: Commands {
    @FocusedValue(\.paperInfoCommandAction) private var paperInfoCommandAction
    @FocusedValue(\.paperCommandContext) private var paperCommandContext
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

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
                paperCommandContext?.perform(.focusFind)
            }
            .keyboardShortcut("f")
            .disabled(!canPerform(.focusFind))
        }
        CommandMenu("Paper") {
            Button("Find Next") {
                paperCommandContext?.perform(.nextFindMatch)
            }
            .keyboardShortcut("g")
            .disabled(!canPerform(.nextFindMatch))

            Button("Find Previous") {
                paperCommandContext?.perform(.previousFindMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!canPerform(.previousFindMatch))

            Divider()

            Button("Zoom In") {
                paperCommandContext?.perform(.zoomIn)
            }
            .keyboardShortcut("+")
            .disabled(!canPerform(.zoomIn))

            Button("Zoom Out") {
                paperCommandContext?.perform(.zoomOut)
            }
            .keyboardShortcut("-")
            .disabled(!canPerform(.zoomOut))

            Button("Actual Size") {
                paperCommandContext?.perform(.actualSize)
            }
            .keyboardShortcut("0")
            .disabled(!canPerform(.actualSize))

            Button("Fit Width") {
                paperCommandContext?.perform(.fitWidth)
            }
            .keyboardShortcut("2")
            .disabled(!canPerform(.fitWidth))

            Divider()

            Button("Show or Hide Annotations") {
                paperCommandContext?.perform(.toggleAnnotations)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!canPerform(.toggleAnnotations))
        }
        CommandMenu("Accessibility") {
            Picker("Appearance", selection: accessibilityPreferences.appearanceModeSelection) {
                ForEach(CanopyAppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }

            Divider()

            Toggle("Increase Contrast", isOn: accessibilityPreferences.increasedContrastSelection)
            Toggle(
                "Differentiate Without Color",
                isOn: accessibilityPreferences.differentiateWithoutColorSelection
            )

            Divider()

            Button("Reset to System Defaults") {
                accessibilityPreferences.reset()
            }
            .disabled(accessibilityPreferences.usesSystemDefaults)
        }
    }

    private func canPerform(_ command: PaperCommand) -> Bool {
        paperCommandContext?.canPerform(command) == true
    }
}
