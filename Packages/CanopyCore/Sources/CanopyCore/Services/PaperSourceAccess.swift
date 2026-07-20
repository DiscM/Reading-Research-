import Foundation

public enum PaperSourceAccessError: Error, Equatable {
    case sourceUnavailable
    case sourceMissing
    case sourceChanged
    case libraryCopyMissing
}

public struct DocumentSourceAccessSnapshot: Sendable {
    public let fingerprint: Data
    public let storageMode: DocumentStorageMode
    public let sourceState: DocumentSourceState
    public let bookmarkData: Data?
    public let managedRelativePath: String?
    public let sourceFileSize: Int64
    public let sourceModificationDate: Date?

    public init(document: Document) {
        fingerprint = document.fingerprint
        storageMode = document.storageMode
        sourceState = document.sourceState
        bookmarkData = document.bookmarkData
        managedRelativePath = document.managedRelativePath
        sourceFileSize = document.sourceFileSize
        sourceModificationDate = document.sourceModificationDate
    }
}

public final class PaperSourceAccess: @unchecked Sendable {
    public let url: URL
    public let verifiedFileSize: Int64
    public let verifiedModificationDate: Date?
    public let attributesChanged: Bool
    private let securityScopedURL: URL?

    public convenience init(
        paper: Paper,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws {
        try self.init(
            snapshot: DocumentSourceAccessSnapshot(document: paper),
            managedStore: suppliedManagedStore
        )
    }

    public init(
        snapshot: DocumentSourceAccessSnapshot,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws {
        switch snapshot.sourceState {
        case .available, .sourceUnavailable:
            break
        case .brokenReference:
            throw PaperSourceAccessError.sourceMissing
        case .sourceChanged:
            throw PaperSourceAccessError.sourceChanged
        case .libraryCopyMissing:
            throw PaperSourceAccessError.libraryCopyMissing
        }

        let resolvedURL: URL
        let scopedURL: URL?
        switch snapshot.storageMode {
        case .referenced:
            guard let bookmarkData = snapshot.bookmarkData else {
                throw PaperSourceAccessError.sourceMissing
            }
            var bookmarkIsStale = false
            do {
                resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &bookmarkIsStale
                )
            } catch {
                throw PaperSourceAccessError.sourceUnavailable
            }
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                throw PaperSourceAccessError.sourceUnavailable
            }
            scopedURL = resolvedURL
        case .managedCopy:
            guard let relativePath = snapshot.managedRelativePath,
                  let managedStore = suppliedManagedStore ?? (try? ManagedPaperStore.applicationSupport()) else {
                throw PaperSourceAccessError.libraryCopyMissing
            }
            resolvedURL = managedStore.rootURL.appendingPathComponent(relativePath)
            scopedURL = nil
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            scopedURL?.stopAccessingSecurityScopedResource()
            throw snapshot.storageMode == .managedCopy
                ? PaperSourceAccessError.libraryCopyMissing
                : PaperSourceAccessError.sourceMissing
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: resolvedURL.path)
        } catch {
            scopedURL?.stopAccessingSecurityScopedResource()
            throw PaperSourceAccessError.sourceUnavailable
        }
        let currentFileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let currentModificationDate = attributes[.modificationDate] as? Date
        let attributesChanged = currentFileSize != snapshot.sourceFileSize
            || currentModificationDate != snapshot.sourceModificationDate

        if attributesChanged {
            let fingerprint: Data
            do {
                fingerprint = try DocumentFingerprint.sha256(of: resolvedURL)
            } catch {
                scopedURL?.stopAccessingSecurityScopedResource()
                throw PaperSourceAccessError.sourceUnavailable
            }
            guard fingerprint == snapshot.fingerprint else {
                scopedURL?.stopAccessingSecurityScopedResource()
                throw PaperSourceAccessError.sourceChanged
            }
        }

        url = resolvedURL
        securityScopedURL = scopedURL
        verifiedFileSize = currentFileSize
        verifiedModificationDate = currentModificationDate
        self.attributesChanged = attributesChanged
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
}
