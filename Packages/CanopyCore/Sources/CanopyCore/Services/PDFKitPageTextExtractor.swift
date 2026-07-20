import Foundation
import PDFKit

public actor PDFKitPageTextExtractor {
    private let document: PDFDocument
    public let pageCount: Int

    public init(url: URL) throws {
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url) else {
            throw PDFPageTextExtractionError.unreadable
        }
        guard !document.isLocked else {
            throw PDFPageTextExtractionError.encrypted
        }
        self.document = document
        pageCount = document.pageCount
    }

    public func extractPage(at pageIndex: Int) throws -> PDFPageText {
        try Task.checkCancellation()
        guard (0..<pageCount).contains(pageIndex),
              let page = document.page(at: pageIndex) else {
            throw PDFPageTextExtractionError.invalidPageIndex(
                pageIndex: pageIndex,
                pageCount: pageCount
            )
        }
        let text = page.string ?? ""
        try Task.checkCancellation()
        return PDFPageText(pageIndex: pageIndex, text: text)
    }
}
