import Foundation
import PDFKit

public enum PDFAnalysisError: LocalizedError {
    case unreadable
    case encrypted

    public var errorDescription: String? {
        switch self {
        case .unreadable: "The selected file is not a readable PDF."
        case .encrypted: "Password-protected PDFs are not supported in Canopy v1."
        }
    }
}

public struct PDFDocumentAnalyzer: DocumentAnalyzing {
    public init() {}

    public func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        guard let document = PDFDocument(url: url) else { throw PDFAnalysisError.unreadable }
        guard !document.isLocked else { throw PDFAnalysisError.encrypted }

        let attributes = document.documentAttributes ?? [:]
        let pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let firstPage = pageTexts.first ?? ""
        let embeddedTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let validEmbeddedTitle = MetadataValidator.usableTitle(embeddedTitle)
        let inferredTitle = firstPageTitle(from: firstPage)
        let filenameTitle = cleanedFilename(url)
        let title = validEmbeddedTitle ?? inferredTitle ?? filenameTitle
        let titleProvenance: MetadataProvenance = validEmbeddedTitle != nil ? .embeddedMetadata : (inferredTitle != nil ? .firstPage : .filenameFallback)

        let embeddedAuthors = attributes[PDFDocumentAttribute.authorAttribute] as? String
        let authors = parseAuthors(embeddedAuthors, fallbackText: firstPage)
        let year = extractYear(from: firstPage)
        let doi = firstMatch(in: firstPage, pattern: #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#)?.lowercased()
        let arxiv = firstMatch(in: firstPage, pattern: #"(?:arXiv:\s*)?(?:\d{4}\.\d{4,5}|[a-z-]+/\d{7})(?:v\d+)?"#)
            .flatMap(MetadataValidator.normalizedArxivID)

        return ParsedPaperMetadata(
            title: title,
            titleProvenance: titleProvenance,
            authors: authors,
            publicationYear: year,
            publicationYearProvenance: year == nil ? nil : .firstPage,
            doi: MetadataValidator.normalizedDOI(doi),
            doiProvenance: doi == nil ? nil : .firstPage,
            arxivID: arxiv,
            arxivIDProvenance: arxiv == nil ? nil : .firstPage,
            pageTexts: pageTexts,
            embeddedCreationDate: attributes[PDFDocumentAttribute.creationDateAttribute] as? Date,
            embeddedModificationDate: attributes[PDFDocumentAttribute.modificationDateAttribute] as? Date
        )
    }

    private func firstPageTitle(from text: String) -> String? {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                (5...300).contains(line.count) && MetadataValidator.usableTitle(line) != nil
            }
    }

    private func cleanedFilename(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private func parseAuthors(_ embedded: String?, fallbackText: String) -> [ParsedAuthorCredit] {
        let source: String
        let provenance: MetadataProvenance
        if let embedded, !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = embedded
            provenance = .embeddedMetadata
        } else {
            let lines = fallbackText.components(separatedBy: .newlines)
            source = lines.dropFirst().prefix(2).joined(separator: ";")
            provenance = .firstPage
        }
        return source
            .components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 160 && $0.rangeOfCharacter(from: .letters) != nil }
            .enumerated()
            .map { _, name in
                ParsedAuthorCredit(
                    displayName: name,
                    familyName: MetadataValidator.inferredFamilyName(name),
                    provenance: provenance
                )
            }
    }

    private func extractYear(from text: String) -> Int? {
        guard let match = firstMatch(in: text, pattern: #"\b(?:1\d{3}|20\d{2})\b"#), let year = Int(match) else { return nil }
        return MetadataValidator.validPublicationYear(year) ? year : nil
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let result = expression.firstMatch(in: text, range: range), let swiftRange = Range(result.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
