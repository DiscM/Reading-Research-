import Foundation

public enum PaperSourceAccessError: Error {
    case sourceUnavailable
    case sourceMissing
    case sourceChanged
    case libraryCopyMissing
}

public final class PaperSourceAccess {
    public let url: URL
    private let securityScopedURL: URL?

    public init(paper: Paper) throws {
        switch paper.sourceState {
        case .available:
            break
        case .sourceUnavailable:
            throw PaperSourceAccessError.sourceUnavailable
        case .brokenReference:
            throw PaperSourceAccessError.sourceMissing
        case .sourceChanged:
            throw PaperSourceAccessError.sourceChanged
        case .libraryCopyMissing:
            throw PaperSourceAccessError.libraryCopyMissing
        }

        switch paper.storageMode {
        case .referenced:
            guard let bookmarkData = paper.bookmarkData else {
                throw PaperSourceAccessError.sourceMissing
            }
            var bookmarkIsStale = false
            let resolvedURL: URL
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
            url = resolvedURL
            securityScopedURL = resolvedURL
        case .managedCopy:
            guard let relativePath = paper.managedRelativePath,
                  let managedStore = try? ManagedPaperStore.applicationSupport() else {
                throw PaperSourceAccessError.libraryCopyMissing
            }
            url = managedStore.rootURL.appendingPathComponent(relativePath)
            securityScopedURL = nil
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            throw paper.storageMode == .managedCopy
                ? PaperSourceAccessError.libraryCopyMissing
                : PaperSourceAccessError.sourceMissing
        }
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }
}
