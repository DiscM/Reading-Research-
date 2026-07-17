import Foundation

public enum PaperFileAccessError: LocalizedError {
    case cannotCreateBookmark
    case cannotAccessSource
    case contentIdentityMismatch

    public var errorDescription: String? {
        switch self {
        case .cannotCreateBookmark: "Canopy could not retain permission to access this PDF."
        case .cannotAccessSource: "Canopy could not access the selected PDF."
        case .contentIdentityMismatch: "The selected PDF does not match the Paper's original content."
        }
    }
}

public struct SecurityScopedBookmarkService: Sendable {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        } catch {
            throw PaperFileAccessError.cannotCreateBookmark
        }
    }
}

public struct ManagedPaperStore: Sendable {
    public let rootURL: URL

    private var recoveryRootURL: URL {
        rootURL.appendingPathComponent(".RemovalRecovery", isDirectory: true)
    }

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public static func applicationSupport() throws -> ManagedPaperStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return ManagedPaperStore(rootURL: support.appendingPathComponent("Canopy/Papers", isDirectory: true))
    }

    public func copy(_ sourceURL: URL, paperID: UUID = UUID()) throws -> String {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let filename = "\(paperID.uuidString).pdf"
        let destination = rootURL.appendingPathComponent(filename)
        let temporary = rootURL.appendingPathComponent(".\(filename).partial")
        try? FileManager.default.removeItem(at: temporary)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporary)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return filename
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    public func copyVerified(
        _ sourceURL: URL,
        paperID: UUID = UUID(),
        expectedFingerprint: Data
    ) throws -> String {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let filename = "\(paperID.uuidString).pdf"
        let destination = rootURL.appendingPathComponent(filename)
        let temporary = rootURL.appendingPathComponent(".\(filename).partial")
        try? FileManager.default.removeItem(at: temporary)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PaperFileAccessError.cannotAccessSource
        }
        try publishVerifiedCopy(
            from: sourceURL,
            temporary: temporary,
            destination: destination,
            expectedFingerprint: expectedFingerprint
        )
        return filename
    }

    public func restoreMissingCopy(
        from sourceURL: URL,
        relativePath: String,
        expectedFingerprint: Data
    ) throws -> URL {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let destination = try managedURL(relativePath: relativePath)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw PaperFileAccessError.cannotAccessSource
        }
        let temporary = rootURL.appendingPathComponent(".\(UUID().uuidString).restore.partial")
        try publishVerifiedCopy(
            from: sourceURL,
            temporary: temporary,
            destination: destination,
            expectedFingerprint: expectedFingerprint
        )
        return destination
    }

    private func publishVerifiedCopy(
        from sourceURL: URL,
        temporary: URL,
        destination: URL,
        expectedFingerprint: Data
    ) throws {
        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporary)
            guard try DocumentFingerprint.sha256(of: temporary) == expectedFingerprint else {
                throw PaperFileAccessError.contentIdentityMismatch
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch let error as PaperFileAccessError {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw PaperFileAccessError.cannotAccessSource
        }
    }

    public func remove(relativePath: String) throws {
        let url = try managedURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    public func stageForRecovery(relativePath: String, paperID: UUID) throws -> Bool {
        let sourceURL = try managedURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return false }

        try FileManager.default.createDirectory(at: recoveryRootURL, withIntermediateDirectories: true)
        let recoveryURL = recoveryURL(paperID: paperID)
        guard !FileManager.default.fileExists(atPath: recoveryURL.path) else {
            throw PaperFileAccessError.cannotAccessSource
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: recoveryURL)
            return true
        } catch {
            throw PaperFileAccessError.cannotAccessSource
        }
    }

    public func restoreFromRecovery(relativePath: String, paperID: UUID) throws {
        let recoveryURL = recoveryURL(paperID: paperID)
        let destinationURL = try managedURL(relativePath: relativePath)
        guard FileManager.default.fileExists(atPath: recoveryURL.path),
              !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw PaperFileAccessError.cannotAccessSource
        }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: recoveryURL, to: destinationURL)
            try removeRecoveryDirectoryIfEmpty()
        } catch {
            throw PaperFileAccessError.cannotAccessSource
        }
    }

    public func discardRecovery(paperID: UUID) throws {
        let recoveryURL = recoveryURL(paperID: paperID)
        guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: recoveryURL)
            try removeRecoveryDirectoryIfEmpty()
        } catch {
            throw PaperFileAccessError.cannotAccessSource
        }
    }

    public func reconcileRecovery(managedRelativePathsByPaperID: [UUID: String]) throws {
        guard FileManager.default.fileExists(atPath: recoveryRootURL.path) else { return }
        let recoveryURLs = try FileManager.default.contentsOfDirectory(
            at: recoveryRootURL,
            includingPropertiesForKeys: nil
        )
        for recoveryURL in recoveryURLs {
            let paperID = UUID(uuidString: recoveryURL.deletingPathExtension().lastPathComponent)
            guard let paperID, let relativePath = managedRelativePathsByPaperID[paperID] else {
                try FileManager.default.removeItem(at: recoveryURL)
                continue
            }

            let liveURL = try managedURL(relativePath: relativePath)
            if FileManager.default.fileExists(atPath: liveURL.path) {
                try FileManager.default.removeItem(at: recoveryURL)
            } else {
                try restoreFromRecovery(relativePath: relativePath, paperID: paperID)
            }
        }
        try removeRecoveryDirectoryIfEmpty()
    }

    private func recoveryURL(paperID: UUID) -> URL {
        recoveryRootURL.appendingPathComponent("\(paperID.uuidString).pdf")
    }

    private func managedURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              relativePath != ".",
              relativePath != "..",
              URL(fileURLWithPath: relativePath).lastPathComponent == relativePath else {
            throw PaperFileAccessError.cannotAccessSource
        }
        return rootURL.appendingPathComponent(relativePath)
    }

    private func removeRecoveryDirectoryIfEmpty() throws {
        guard FileManager.default.fileExists(atPath: recoveryRootURL.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: recoveryRootURL,
            includingPropertiesForKeys: nil
        )
        if contents.isEmpty {
            try FileManager.default.removeItem(at: recoveryRootURL)
        }
    }
}
