import Foundation

public enum PaperFileAccessError: LocalizedError {
    case cannotCreateBookmark
    case cannotAccessSource

    public var errorDescription: String? {
        switch self {
        case .cannotCreateBookmark: "Canopy could not retain permission to access this PDF."
        case .cannotAccessSource: "Canopy could not access the selected PDF."
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

    public func remove(relativePath: String) throws {
        let url = rootURL.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
