import AppKit
import CanopyCore
import Observation
import SwiftData
import SwiftUI

@main
struct CanopyApp: App {
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

    var body: some Scene {
        Window("Canopy", id: "library") {
            CanopyContentRoot(
                appearanceMode: accessibilityPreferences.appearanceMode,
                accessibilityOverrides: accessibilityPreferences.overrides
            )
        }
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
    @State private var startup = CanopyStartupController()

    var body: some View {
        Group {
            switch startup.phase {
            case .opening:
                ProgressView("Opening Canopy’s library…")
            case let .ready(container):
                ContentView(
                    managedCopyReconciliationWarning: startup.managedCopyReconciliationWarning,
                    isRetryingManagedCopyReconciliation: startup.isRetryingManagedCopyReconciliation,
                    onRetryManagedCopyReconciliation: startup.retryManagedCopyReconciliation
                )
                .modelContainer(container)
            case let .failed(errorMessage):
                CanopyLibraryRecoveryView(
                    errorMessage: errorMessage,
                    onRetry: startup.retryOpeningLibrary,
                    onRevealLibraryData: startup.revealLibraryData,
                    onQuit: startup.quit
                )
            }
        }
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

@Observable
@MainActor
private final class CanopyStartupController {
    enum Phase {
        case opening
        case ready(ModelContainer)
        case failed(String)
    }

    private(set) var phase: Phase = .opening
    private(set) var managedCopyReconciliationWarning: String?
    private(set) var isRetryingManagedCopyReconciliation = false
    private let storeURL: URL
    private let usesInMemoryStore: Bool
    private let isUITestMode: Bool

    init() {
        #if DEBUG
        if let testLibrary = CanopyUITestLibraryConfiguration.current {
            storeURL = testLibrary.storeURL
            usesInMemoryStore = testLibrary.cleansBeforeOpening
            isUITestMode = true
            if testLibrary.resetsBeforeOpening || testLibrary.cleansBeforeOpening {
                try? FileManager.default.removeItem(at: testLibrary.directoryURL)
            }
        } else if CanopyUITestLibraryConfiguration.isRequested {
            storeURL = CanopyUITestLibraryConfiguration.invalidConfigurationStoreURL
            usesInMemoryStore = true
            isUITestMode = true
            phase = .failed("UI-test mode requires a valid UUID library identifier.")
            return
        } else {
            storeURL = CanopyModelContainer.defaultStoreURL
            usesInMemoryStore = false
            isUITestMode = false
        }
        #else
        storeURL = CanopyModelContainer.defaultStoreURL
        usesInMemoryStore = false
        isUITestMode = false
        #endif
        openLibrary()
    }

    func retryOpeningLibrary() {
        guard case .failed = phase else { return }
        phase = .opening
        Task { @MainActor in
            await Task.yield()
            openLibrary()
        }
    }

    func retryManagedCopyReconciliation() {
        guard case let .ready(container) = phase,
              !isRetryingManagedCopyReconciliation else {
            return
        }
        isRetryingManagedCopyReconciliation = true
        Task { @MainActor in
            await Task.yield()
            reconcileManagedCopies(in: container)
            isRetryingManagedCopyReconciliation = false
        }
    }

    func revealLibraryData() {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([storeURL])
        } else {
            NSWorkspace.shared.open(storeURL.deletingLastPathComponent())
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func openLibrary() {
        do {
            let container = try CanopyModelContainer.make(
                inMemory: usesInMemoryStore,
                storeURL: storeURL
            )
            reconcileManagedCopies(in: container)
            phase = .ready(container)
        } catch {
            managedCopyReconciliationWarning = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func reconcileManagedCopies(in container: ModelContainer) {
        guard !isUITestMode else {
            managedCopyReconciliationWarning = nil
            return
        }
        do {
            try LibraryRepository(container: container).reconcileManagedPaperRecovery()
            managedCopyReconciliationWarning = nil
        } catch {
            managedCopyReconciliationWarning = error.localizedDescription
        }
    }
}

private struct CanopyLibraryRecoveryView: View {
    let errorMessage: String
    let onRetry: @MainActor () -> Void
    let onRevealLibraryData: @MainActor () -> Void
    let onQuit: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Canopy Couldn’t Open the Library")
                    .font(.title2.weight(.semibold))

                Text("Your library data has not been changed. Retry after resolving the problem, reveal the data in Finder for troubleshooting, or quit Canopy.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 520)

            HStack(spacing: 12) {
                Button("Quit", action: onQuit)
                Button("Reveal Library Data", action: onRevealLibraryData)
                Button("Retry", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(48)
    }
}

private struct CanopyCommands: Commands {
    @FocusedValue(\.addPapersCommandAction) private var addPapersCommandAction
    @FocusedValue(\.paperInfoCommandAction) private var paperInfoCommandAction
    @FocusedValue(\.paperCommandContext) private var paperCommandContext
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Papers…") {
                addPapersCommandAction?.perform()
            }
            .keyboardShortcut("o")
            .disabled(addPapersCommandAction == nil)

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
            Button("Area Annotation…") {
                paperCommandContext?.perform(.startAreaAnnotation)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!canPerform(.startAreaAnnotation))

            Divider()

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
