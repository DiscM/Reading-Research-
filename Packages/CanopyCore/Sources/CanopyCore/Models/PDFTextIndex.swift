import Foundation

public enum PDFTextIndexFormat {
    public static let currentVersion = 1
}

public enum PDFTextIndexError: Error, Equatable, LocalizedError, Sendable {
    case invalidFingerprintLength(Int)
    case invalidFormatVersion(Int)
    case invalidPageCount(Int)
    case invalidPageIndex(pageIndex: Int, pageCount: Int)
    case missingIndex(PDFTextIndexKey)
    case pageCountMismatch(expected: Int, actual: Int)
    case incompleteIndex(indexedPageCount: Int, totalPageCount: Int)
    case invalidSearchLimit(Int)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidFingerprintLength(length):
            "A SHA-256 fingerprint must contain 32 bytes; received \(length)."
        case let .invalidFormatVersion(version):
            "An index-format version must be positive; received \(version)."
        case let .invalidPageCount(count):
            "A PDF page count cannot be negative; received \(count)."
        case let .invalidPageIndex(pageIndex, pageCount):
            "Page index \(pageIndex) is outside the PDF's 0..<\(pageCount) page range."
        case let .missingIndex(key):
            "No PDF text index exists for fingerprint \(key.fingerprint.hexadecimalString) at format version \(key.formatVersion)."
        case let .pageCountMismatch(expected, actual):
            "The existing index expects \(expected) pages, but the source reports \(actual)."
        case let .incompleteIndex(indexedPageCount, totalPageCount):
            "Only \(indexedPageCount) of \(totalPageCount) pages have been indexed."
        case let .invalidSearchLimit(limit):
            "A search result limit must be positive; received \(limit)."
        case let .database(message):
            "The local PDF text index could not be accessed: \(message)"
        }
    }
}

public struct PDFTextIndexKey: Hashable, Sendable {
    public let fingerprint: Data
    public let formatVersion: Int

    public init(fingerprint: Data, formatVersion: Int) throws {
        guard fingerprint.count == 32 else {
            throw PDFTextIndexError.invalidFingerprintLength(fingerprint.count)
        }
        guard formatVersion > 0 else {
            throw PDFTextIndexError.invalidFormatVersion(formatVersion)
        }
        self.fingerprint = fingerprint
        self.formatVersion = formatVersion
    }
}

public enum PDFTextIndexLifecycle: String, Equatable, Sendable {
    case pending
    case indexing
    case ready
    case needsSource
    case failed
}

public struct PDFTextIndexStatus: Equatable, Sendable {
    public let key: PDFTextIndexKey
    public let lifecycle: PDFTextIndexLifecycle
    public let totalPageCount: Int
    public let indexedPageCount: Int
    public let nextPageIndex: Int?
    public let failureDescription: String?

    public var fractionCompleted: Double {
        guard totalPageCount > 0 else { return lifecycle == .ready ? 1 : 0 }
        return Double(indexedPageCount) / Double(totalPageCount)
    }

    public init(
        key: PDFTextIndexKey,
        lifecycle: PDFTextIndexLifecycle,
        totalPageCount: Int,
        indexedPageCount: Int,
        nextPageIndex: Int?,
        failureDescription: String?
    ) {
        self.key = key
        self.lifecycle = lifecycle
        self.totalPageCount = totalPageCount
        self.indexedPageCount = indexedPageCount
        self.nextPageIndex = nextPageIndex
        self.failureDescription = failureDescription
    }
}

public enum PDFTextIndexPreparationDisposition: Equatable, Sendable {
    case created
    case resumable
    case reused
}

public struct PDFTextIndexPreparation: Equatable, Sendable {
    public let disposition: PDFTextIndexPreparationDisposition
    public let status: PDFTextIndexStatus

    public init(
        disposition: PDFTextIndexPreparationDisposition,
        status: PDFTextIndexStatus
    ) {
        self.disposition = disposition
        self.status = status
    }
}

public struct PDFTextSearchHit: Equatable, Sendable {
    public let key: PDFTextIndexKey
    public let pageIndex: Int
    public let snippet: String
    public let relevanceScore: Double

    public var pageNumber: Int { pageIndex + 1 }

    public init(
        key: PDFTextIndexKey,
        pageIndex: Int,
        snippet: String,
        relevanceScore: Double
    ) {
        self.key = key
        self.pageIndex = pageIndex
        self.snippet = snippet
        self.relevanceScore = relevanceScore
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
