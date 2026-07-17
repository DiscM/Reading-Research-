import Foundation

public struct VerifiedPaperFile: Equatable, Sendable {
    public let url: URL
    public let fileSize: Int64
    public let modificationDate: Date?

    public init(url: URL, fileSize: Int64, modificationDate: Date?) {
        self.url = url
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

public final class PreparedPaperFileTransfer: @unchecked Sendable {
    private enum State: Equatable {
        case prepared
        case published
        case finished
    }

    public let destinationURL: URL
    private let temporaryURL: URL
    private let backupURL: URL
    private var state = State.prepared

    fileprivate init(temporaryURL: URL, destinationURL: URL, backupURL: URL) {
        self.temporaryURL = temporaryURL
        self.destinationURL = destinationURL
        self.backupURL = backupURL
    }

    deinit {
        try? rollback()
    }

    public func publish() throws -> VerifiedPaperFile {
        guard state == .prepared else {
            throw PaperFileAccessError.cannotAccessSource
        }
        let fileManager = FileManager.default
        let hadDestination = fileManager.fileExists(atPath: destinationURL.path)

        do {
            if hadDestination {
                try fileManager.moveItem(at: destinationURL, to: backupURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            state = .published
            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            return VerifiedPaperFile(
                url: destinationURL,
                fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date
            )
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            if hadDestination, fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw PaperFileAccessError.cannotAccessSource
        }
    }

    public func commit() {
        guard state != .finished else { return }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: temporaryURL)
        try? fileManager.removeItem(at: backupURL)
        state = .finished
    }

    public func rollback() throws {
        guard state != .finished else { return }
        let fileManager = FileManager.default
        switch state {
        case .prepared:
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try fileManager.removeItem(at: temporaryURL)
            }
        case .published:
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: backupURL, to: destinationURL)
            }
        case .finished:
            break
        }
        state = .finished
    }
}

public struct PaperFileTransfer: Sendable {
    public init() {}

    public func prepareVerifiedCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedFingerprint: Data
    ) throws -> PreparedPaperFileTransfer {
        let fileManager = FileManager.default
        let normalizedSource = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedDestination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
        guard normalizedSource != normalizedDestination else {
            throw PaperFileAccessError.cannotAccessSource
        }
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let temporary = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).conversion.partial")
        let backup = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).conversion.backup")

        do {
            try fileManager.copyItem(at: sourceURL, to: temporary)
            guard try DocumentFingerprint.sha256(of: temporary) == expectedFingerprint else {
                throw PaperFileAccessError.contentIdentityMismatch
            }
            return PreparedPaperFileTransfer(
                temporaryURL: temporary,
                destinationURL: destinationURL,
                backupURL: backup
            )
        } catch let error as PaperFileAccessError {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw PaperFileAccessError.cannotAccessSource
        }
    }
}
