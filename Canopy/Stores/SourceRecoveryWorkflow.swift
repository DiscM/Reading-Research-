import CanopyCore
import Foundation
import Observation

enum SourceRecoveryAction: Hashable, Identifiable {
    case retry
    case locateSource
    case locateOriginal
    case addChangedAsSeparate
    case restoreLibraryCopy
    case removeFromLibrary

    var id: Self { self }

    var title: String {
        switch self {
        case .retry: "Retry"
        case .locateSource: "Locate Source…"
        case .locateOriginal: "Locate Original…"
        case .addChangedAsSeparate: "Add Changed File as Separate Document…"
        case .restoreLibraryCopy: "Restore Library Copy…"
        case .removeFromLibrary: "Remove from Library…"
        }
    }

    var systemImage: String {
        switch self {
        case .retry: "arrow.clockwise"
        case .locateSource: "link.badge.plus"
        case .locateOriginal: "folder.badge.questionmark"
        case .addChangedAsSeparate: "doc.badge.plus"
        case .restoreLibraryCopy: "arrow.down.doc"
        case .removeFromLibrary: "trash"
        }
    }

    static func actions(for state: PaperSourceState) -> [SourceRecoveryAction] {
        SourceStatePresentation(state).actions
    }
}

enum SourceStateSeverity {
    case neutral
    case warning
    case critical
}

struct SourceStatePresentation {
    let label: String?
    let systemImage: String?
    let severity: SourceStateSeverity
    let actions: [SourceRecoveryAction]

    init(_ state: PaperSourceState) {
        switch state {
        case .available:
            label = nil
            systemImage = nil
            severity = .neutral
            actions = []
        case .sourceUnavailable:
            label = "Source Unavailable"
            systemImage = "externaldrive.badge.exclamationmark"
            severity = .neutral
            actions = [.retry, .locateSource]
        case .brokenReference:
            label = "Source Missing"
            systemImage = "link.badge.plus"
            severity = .warning
            actions = [.locateSource, .removeFromLibrary]
        case .sourceChanged:
            label = "Source Changed"
            systemImage = "exclamationmark.triangle"
            severity = .warning
            actions = [.locateOriginal, .addChangedAsSeparate, .removeFromLibrary]
        case .libraryCopyMissing:
            label = "Library Copy Missing"
            systemImage = "doc.badge.ellipsis"
            severity = .critical
            actions = [.restoreLibraryCopy, .removeFromLibrary]
        }
    }
}

@Observable
@MainActor
final class SourceRecoveryWorkflow {
    private var request: SourceRecoveryRequest?
    var isImporterPresented = false

    func begin(for paper: Paper) {
        request = SourceRecoveryRequest(paperID: paper.id, storageMode: paper.storageMode)
        isImporterPresented = true
    }

    func cancel() {
        request = nil
        isImporterPresented = false
    }

    /// Resolves the bookmark that identified a changed referenced Source PDF.
    /// The returned URL is probed under its security scope, then handed to the
    /// ordinary Add Papers workflow, which owns access for the Add Batch itself.
    func resolveKnownChangedSourceURL(for paper: Paper) -> URL? {
        guard paper.sourceState == .sourceChanged,
              paper.storageMode == .referenced,
              let bookmarkData = paper.bookmarkData else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
            return nil
        }

        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }
        return url
    }

    func recover(
        from url: URL,
        repository: LibraryRepository,
        managedStore: ManagedPaperStore? = nil
    ) async throws -> UUID {
        guard let request else {
            throw LibraryRepositoryError.paperNotFound
        }
        cancel()
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch request.storageMode {
        case .referenced:
            let fingerprint = try await Task.detached(priority: .userInitiated) {
                try DocumentFingerprint.sha256(of: url)
            }.value
            let bookmark = try SecurityScopedBookmarkService().makeBookmark(for: url)
            try repository.repairReference(
                paperID: request.paperID,
                fingerprint: fingerprint,
                bookmarkData: bookmark,
                rememberedLocation: url.path
            )
        case .managedCopy:
            try await repository.restoreManagedCopy(
                paperID: request.paperID,
                from: url,
                managedStore: managedStore
            )
        }
        return request.paperID
    }
}

private struct SourceRecoveryRequest {
    let paperID: UUID
    let storageMode: PaperStorageMode
}
