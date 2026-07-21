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
        .defaultSize(width: 1404, height: 800)
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
    @AppStorage("workspace.navigationPresented") private var navigationPresented = true
    @AppStorage("workspace.documentListPresented") private var documentListPresented = true
    @AppStorage("workspace.inspectorPresented") private var inspectorPresented = true
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
                    indexDatabaseURL: startup.indexDatabaseURL,
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
        .frame(minWidth: minimumWindowWidth, minHeight: 600)
        .environment(\.canopyAccessibilityOverrides, accessibilityOverrides)
        .contrast(appContrastAmount)
        .preferredColorScheme(appearanceMode.preferredColorScheme)
    }

    private var appContrastAmount: Double {
        accessibilityOverrides.interfaceContrastAmount(
            systemIncreasedContrast: systemColorSchemeContrast == .increased
        )
    }

    private var minimumWindowWidth: CGFloat {
        WorkspaceLayoutMetrics.minimumWindowWidth(
            navigationPresented: navigationPresented,
            documentListPresented: documentListPresented,
            inspectorPresented: inspectorPresented
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

    var indexDatabaseURL: URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("PDFTextIndex.sqlite")
    }

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
    @FocusedValue(\.addDocumentsCommandAction) private var addDocumentsCommandAction
    @FocusedValue(\.documentInfoCommandAction) private var documentInfoCommandAction
    @FocusedValue(\.documentCommandContext) private var documentCommandContext
    @FocusedValue(\.workspaceCommandContext) private var workspaceCommandContext
    private var accessibilityPreferences = CanopyAccessibilityPreferences()

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Documents…") {
                addDocumentsCommandAction?.perform()
            }
            .keyboardShortcut("o")
            .disabled(addDocumentsCommandAction == nil)
        }
        CommandGroup(after: .textEditing) {
            Button(canPerform(.focusFind) ? "Find in Document…" : "Find in Workspace…") {
                if canPerform(.focusFind) {
                    documentCommandContext?.perform(.focusFind)
                } else {
                    workspaceCommandContext?.perform(.focusContextualSearch)
                }
            }
            .keyboardShortcut("f")
            .disabled(!canPerform(.focusFind) && workspaceCommandContext == nil)
        }
        CommandGroup(after: .sidebar) {
            Button("Show or Hide Navigation") {
                workspaceCommandContext?.perform(.toggleNavigationSidebar)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(workspaceCommandContext == nil)

            Button("Show or Hide Document List") {
                workspaceCommandContext?.perform(.toggleDocumentList)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(workspaceCommandContext == nil)

            Button("Show or Hide Inspector") {
                workspaceCommandContext?.perform(.toggleInspector)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(workspaceCommandContext == nil)

            Button("Show Overview Inspector") {
                workspaceCommandContext?.perform(.showOverview)
            }
            .disabled(workspaceCommandContext == nil)

            Button("Show Annotations Inspector") {
                workspaceCommandContext?.perform(.showAnnotations)
            }
            .disabled(workspaceCommandContext == nil)

            Divider()

            Button("Search Workspace") {
                workspaceCommandContext?.perform(.focusSearch)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(workspaceCommandContext == nil)
        }
        CommandMenu("Document") {
            Button("Get Info…") {
                documentInfoCommandAction?.perform()
            }
            .keyboardShortcut("i")
            .disabled(documentInfoCommandAction == nil)

            Divider()

            Button("Area Annotation…") {
                documentCommandContext?.perform(.startAreaAnnotation)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!canPerform(.startAreaAnnotation))

            Divider()

            Button("Find Next") {
                documentCommandContext?.perform(.nextFindMatch)
            }
            .keyboardShortcut("g")
            .disabled(!canPerform(.nextFindMatch))

            Button("Find Previous") {
                documentCommandContext?.perform(.previousFindMatch)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(!canPerform(.previousFindMatch))

            Divider()

            Button("Zoom In") {
                documentCommandContext?.perform(.zoomIn)
            }
            .keyboardShortcut("+")
            .disabled(!canPerform(.zoomIn))

            Button("Zoom Out") {
                documentCommandContext?.perform(.zoomOut)
            }
            .keyboardShortcut("-")
            .disabled(!canPerform(.zoomOut))

            Button("Actual Size") {
                documentCommandContext?.perform(.actualSize)
            }
            .keyboardShortcut("0")
            .disabled(!canPerform(.actualSize))

            Button("Fit Width") {
                documentCommandContext?.perform(.fitWidth)
            }
            .keyboardShortcut("2")
            .disabled(!canPerform(.fitWidth))

            Divider()

            Button("Show or Hide Annotations") {
                documentCommandContext?.perform(.toggleInspector)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!canPerform(.toggleInspector))
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

    private func canPerform(_ command: DocumentCommand) -> Bool {
        documentCommandContext?.canPerform(command) == true
    }
}
