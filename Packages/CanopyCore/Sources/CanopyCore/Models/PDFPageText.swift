import Foundation

public struct PDFPageText: Equatable, Sendable {
    public let pageIndex: Int
    public let text: String

    public var pageNumber: Int { pageIndex + 1 }

    public init(pageIndex: Int, text: String) {
        self.pageIndex = pageIndex
        self.text = text
    }
}

public enum PDFPageTextExtractionError: Error, Equatable, LocalizedError, Sendable {
    case unreadable
    case encrypted
    case invalidPageIndex(pageIndex: Int, pageCount: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            "The Source PDF could not be opened for text indexing."
        case .encrypted:
            "Password-protected PDFs cannot be indexed."
        case let .invalidPageIndex(pageIndex, pageCount):
            "Page index \(pageIndex) is outside the PDF's 0..<\(pageCount) page range."
        }
    }
}
