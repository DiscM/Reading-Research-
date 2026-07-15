import Foundation

public struct PaperSourceAvailabilityRequest: Sendable, Equatable {
    public let paperID: UUID
    public let storageMode: PaperStorageMode
    public let bookmarkData: Data?
    public let managedRelativePath: String?
    public let sourceFileSize: Int64
    public let sourceModificationDate: Date?
    public let sourceState: PaperSourceState

    public init(
        paperID: UUID,
        storageMode: PaperStorageMode,
        bookmarkData: Data?,
        managedRelativePath: String?,
        sourceFileSize: Int64,
        sourceModificationDate: Date?,
        sourceState: PaperSourceState = .available
    ) {
        self.paperID = paperID
        self.storageMode = storageMode
        self.bookmarkData = bookmarkData
        self.managedRelativePath = managedRelativePath
        self.sourceFileSize = sourceFileSize
        self.sourceModificationDate = sourceModificationDate
        self.sourceState = sourceState
    }
}

public struct PaperSourceAvailabilityResult: Sendable, Equatable {
    public let request: PaperSourceAvailabilityRequest
    public let status: PaperSourceState
    public let attributesChanged: Bool

    public var paperID: UUID { request.paperID }

    public init(
        request: PaperSourceAvailabilityRequest,
        status: PaperSourceState,
        attributesChanged: Bool
    ) {
        self.request = request
        self.status = status
        self.attributesChanged = attributesChanged
    }
}

public struct PaperSourceAvailabilityChecker: Sendable {
    public init() {}

    public func check(
        _ requests: [PaperSourceAvailabilityRequest],
        managedStore: ManagedPaperStore? = nil
    ) -> [PaperSourceAvailabilityResult] {
        requests.map { check($0, managedStore: managedStore) }
    }

    public func check(
        _ request: PaperSourceAvailabilityRequest,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) -> PaperSourceAvailabilityResult {
        let resolvedURL: URL
        let scopedURL: URL?

        switch request.storageMode {
        case .referenced:
            guard let bookmarkData = request.bookmarkData else {
                return result(for: request, status: .brokenReference)
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
                return result(for: request, status: .sourceUnavailable)
            }
            guard resolvedURL.startAccessingSecurityScopedResource() else {
                return result(for: request, status: .sourceUnavailable)
            }
            scopedURL = resolvedURL
        case .managedCopy:
            guard let relativePath = request.managedRelativePath,
                  !relativePath.isEmpty,
                  relativePath != ".",
                  relativePath != "..",
                  URL(fileURLWithPath: relativePath).lastPathComponent == relativePath,
                  let managedStore = suppliedManagedStore ?? (try? ManagedPaperStore.applicationSupport()) else {
                return result(for: request, status: .libraryCopyMissing)
            }
            resolvedURL = managedStore.rootURL.appendingPathComponent(relativePath)
            scopedURL = nil
        }
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return result(
                for: request,
                status: request.storageMode == .managedCopy ? .libraryCopyMissing : .brokenReference
            )
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: resolvedURL.path)
        } catch {
            return result(for: request, status: .sourceUnavailable)
        }
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        return PaperSourceAvailabilityResult(
            request: request,
            status: .available,
            attributesChanged: fileSize != request.sourceFileSize
                || modificationDate != request.sourceModificationDate
        )
    }

    private func result(
        for request: PaperSourceAvailabilityRequest,
        status: PaperSourceState
    ) -> PaperSourceAvailabilityResult {
        PaperSourceAvailabilityResult(
            request: request,
            status: status,
            attributesChanged: false
        )
    }
}
