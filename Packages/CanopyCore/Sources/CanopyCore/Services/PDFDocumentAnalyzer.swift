import AppKit
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
        try Task.checkCancellation()
        guard let document = PDFDocument(url: url) else { throw PDFAnalysisError.unreadable }
        try Task.checkCancellation()
        guard !document.isLocked else { throw PDFAnalysisError.encrypted }

        let attributes = document.documentAttributes ?? [:]
        let pageCount = document.pageCount
        let firstPageObject = pageCount > 0 ? document.page(at: 0) : nil
        let firstPage = firstPageObject?.string ?? ""
        var hasSelectableText = containsSelectableText(firstPage)
        if !hasSelectableText, pageCount > 1 {
            for pageIndex in 1..<pageCount {
                try Task.checkCancellation()
                if containsSelectableText(document.page(at: pageIndex)?.string) {
                    hasSelectableText = true
                    break
                }
            }
        }
        try Task.checkCancellation()
        let firstPageMetadata = firstPageObject.map(inferFirstPageMetadata)
        let embeddedTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let validEmbeddedTitle = MetadataValidator.usableTitle(normalizedWhitespace(embeddedTitle))
        let inferredTitle = firstPageMetadata?.title
        let filenameTitle = cleanedFilename(url)
        let title = validEmbeddedTitle ?? inferredTitle ?? filenameTitle
        let titleProvenance: MetadataProvenance = validEmbeddedTitle != nil ? .embeddedMetadata : (inferredTitle != nil ? .firstPage : .filenameFallback)

        let embeddedAuthors = attributes[PDFDocumentAttribute.authorAttribute] as? String
        let authors = parseAuthors(embeddedAuthors, fallbackText: firstPageMetadata?.authors)
        let year = extractYear(from: firstPage)
        let doi = firstMatch(in: firstPage, pattern: #"10\.\d{4,9}/[-._;()/:A-Z0-9]+"#)?.lowercased()
        let arxiv = firstMatch(in: firstPage, pattern: #"(?:arXiv:\s*)?(?:\d{4}\.\d{4,5}|[a-z-]+/\d{7})(?:v\d+)?"#)
            .flatMap(MetadataValidator.normalizedArxivID)

        try Task.checkCancellation()
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
            pageCount: pageCount,
            hasSelectableText: hasSelectableText
        )
    }

    private func containsSelectableText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inferFirstPageMetadata(from page: PDFPage) -> FirstPageMetadata {
        let lines = firstPageLines(from: page)
        if let labeledTitle = lines.enumerated().compactMap({ index, line in
            labeledValue(
                in: line.text,
                pattern: #"^\s*(?:paper\s+)?title(?:\s*:\s*|\s*[–—]\s*|\s+-\s+)(.+?)\s*$"#
            )
                .map { (index, $0) }
        }).first {
            let labeledAuthors = lines.compactMap { line in
                labeledValue(
                    in: line.text,
                    pattern: #"^\s*(?:authors?|author\(s\))(?:\s*:\s*|\s*[–—]\s*|\s+-\s+)(.+?)\s*$"#
                )
            }.first
            return FirstPageMetadata(
                title: MetadataValidator.usableTitle(labeledTitle.1),
                authors: labeledAuthors ?? inferredAuthorText(in: lines, after: labeledTitle.0 + 1)
            )
        }

        guard let titleBlock = prominentTitleBlock(in: lines) else {
            return FirstPageMetadata(title: nil, authors: nil)
        }

        let title = titleBlock.indices
            .map { lines[$0].text }
            .joined(separator: " ")
        let authors = inferredAuthorText(in: lines, after: titleBlock.indices.upperBound)
        return FirstPageMetadata(title: MetadataValidator.usableTitle(title), authors: authors)
    }

    private func firstPageLines(from page: PDFPage) -> [FirstPageLine] {
        let pageBounds = page.bounds(for: .cropBox)
        guard let selection = page.selection(for: pageBounds) else { return [] }

        return selection.selectionsByLine().compactMap { lineSelection in
            guard let rawText = lineSelection.string else { return nil }
            let text = rawText
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !text.isEmpty else { return nil }

            var maximumFontSize: CGFloat = 0
            if let attributedString = lineSelection.attributedString {
                attributedString.enumerateAttribute(
                    .font,
                    in: NSRange(location: 0, length: attributedString.length)
                ) { value, _, _ in
                    if let font = value as? NSFont {
                        maximumFontSize = max(maximumFontSize, font.pointSize)
                    }
                }
            }
            return FirstPageLine(
                text: text,
                bounds: lineSelection.bounds(for: page),
                fontSize: maximumFontSize
            )
        }
    }

    private func prominentTitleBlock(in lines: [FirstPageLine]) -> FirstPageTitleBlock? {
        let firstSectionIndex = lines.firstIndex { isSectionBoundary($0.text) }
        let candidateEndIndex = min(
            firstSectionIndex ?? lines.endIndex,
            FirstPageParsingRules.titleCandidateLineLimit
        )
        let candidates = lines[..<candidateEndIndex].indices.filter { index in
            let line = lines[index]
            return line.fontSize > 0
                && line.bounds.height <= line.bounds.width * 2
                && (2...300).contains(line.text.count)
                && MetadataValidator.usableTitle(line.text) != nil
                && !isSectionBoundary(line.text)
        }
        guard !candidates.isEmpty else { return nil }

        let fontSizes = candidates.map { lines[$0].fontSize }.sorted()
        guard let largestFontSize = fontSizes.last else { return nil }
        let typicalFontSize = fontSizes[(fontSizes.count - 1) / 4]
        guard largestFontSize >= typicalFontSize * FirstPageParsingRules.minimumTitleFontRatio else {
            return nil
        }

        let threshold = largestFontSize * FirstPageParsingRules.titleLineFontRatio
        let highFontCandidates = candidates.filter { lines[$0].fontSize >= threshold }
        var blocks: [FirstPageTitleBlock] = []
        var blockStart: Int?
        var previousIndex: Int?

        func finishBlock() {
            guard let blockStart, let previousIndex else { return }
            blocks.append(FirstPageTitleBlock(indices: blockStart..<(previousIndex + 1)))
        }

        for index in highFontCandidates {
            if let priorIndex = previousIndex,
               let startIndex = blockStart,
               index == priorIndex + 1,
               index - startIndex < FirstPageParsingRules.maximumTitleLineCount,
               titleLinesAreAdjacent(lines[priorIndex], lines[index]) {
                previousIndex = index
            } else {
                finishBlock()
                blockStart = index
                previousIndex = index
            }
        }
        finishBlock()

        let anchoredBlocks = blocks.filter { block in
            block.indices.contains { lines[$0].fontSize >= largestFontSize - 0.1 }
        }
        let preferredBlock = anchoredBlocks.reduce(nil as FirstPageTitleBlock?) { best, candidate in
            guard let best else { return candidate }
            if candidate.indices.count != best.indices.count {
                return candidate.indices.count > best.indices.count ? candidate : best
            }
            let candidateLength = candidate.indices.reduce(0) { $0 + lines[$1].text.count }
            let bestLength = best.indices.reduce(0) { $0 + lines[$1].text.count }
            return candidateLength > bestLength ? candidate : best
        }
        guard let titleBlock = preferredBlock else { return nil }

        let title = titleBlock.indices.map { lines[$0].text }.joined(separator: " ")
        guard (2...300).contains(title.count), MetadataValidator.usableTitle(title) != nil else {
            return nil
        }
        return titleBlock
    }

    private func titleLinesAreAdjacent(_ first: FirstPageLine, _ second: FirstPageLine) -> Bool {
        let centerDistance = abs(first.bounds.midY - second.bounds.midY)
        let fontSize = max(first.fontSize, second.fontSize)
        return centerDistance <= fontSize * FirstPageParsingRules.maximumTitleLineSpacingRatio
    }

    private func cleanedFilename(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    private func parseAuthors(_ embedded: String?, fallbackText: String?) -> [ParsedAuthorCredit] {
        if let embedded, isUsableEmbeddedAuthorSource(embedded) {
            let embeddedCredits = authorCredits(from: embedded, provenance: .embeddedMetadata)
            if !embeddedCredits.isEmpty {
                return embeddedCredits
            }
        }
        guard let fallbackText else { return [] }
        return authorCredits(from: fallbackText, provenance: .firstPage)
    }

    private func authorCredits(
        from source: String,
        provenance: MetadataProvenance
    ) -> [ParsedAuthorCredit] {
        normalizedAuthorSource(source)
            .components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(splitUnambiguousCommaList)
            .filter {
                !$0.isEmpty
                    && $0.count <= FirstPageParsingRules.maximumAuthorNameLength
                    && $0.rangeOfCharacter(from: .letters) != nil
            }
            .map { name in
                ParsedAuthorCredit(
                    displayName: name,
                    familyName: MetadataValidator.inferredFamilyName(name),
                    provenance: provenance
                )
            }
    }

    private func normalizedAuthorSource(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: #"^\s*(?:authors?|author\(s\))(?:\s*:\s*|\s*[–—]\s*|\s+-\s+)"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"\s*\[[0-9Xx−–—-]{15,}\]"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[*†‡§¶∗]+"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+(?:and|&)\s+"#,
                with: ";",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    private func isUsableEmbeddedAuthorSource(_ source: String) -> Bool {
        let normalized = normalizedWhitespace(source)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty,
              normalized.count <= FirstPageParsingRules.maximumEmbeddedAuthorLength,
              normalized.rangeOfCharacter(from: .letters) != nil,
              !normalized.contains("@") else {
            return false
        }

        let lowered = normalized.lowercased()
        let rejectedValues = ["author", "authors", "unknown", "none", "n/a", "user"]
        let producerMarkers = [
            "python-docx", "microsoft word", "microsoft powerpoint", "libreoffice",
            "adobe acrobat", "acrobat pdfmaker", "quartz pdfcontext", "pdftex", "latex",
            "google docs", "google slides", "google sheets", "pdfcreator", "pdf creator",
            "chatgpt canvas", "apple pages", "canva", "overleaf"
        ]
        return !rejectedValues.contains(lowered)
            && !producerMarkers.contains { lowered.contains($0) }
            && !lowered.hasPrefix("http://")
            && !lowered.hasPrefix("https://")
    }

    private func splitUnambiguousCommaList(_ value: String) -> [String] {
        let components = value
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard components.count > 1,
              components.allSatisfy({ $0.split(whereSeparator: \Character.isWhitespace).count >= 2 }) else {
            return [value]
        }
        return components
    }

    private func normalizedWhitespace(_ value: String?) -> String? {
        value?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func labeledValue(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let searchRange = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: searchRange),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }

    private func inferredAuthorText(in lines: [FirstPageLine], after titleEndIndex: Int) -> String? {
        var authorGroups: [String] = []
        var currentGroup: [String] = []

        func finishCurrentGroup() {
            guard !currentGroup.isEmpty else { return }
            authorGroups.append(currentGroup.joined(separator: " "))
            currentGroup = []
        }

        for line in lines.dropFirst(titleEndIndex).prefix(FirstPageParsingRules.authorScanLineLimit) {
            if isSectionBoundary(line.text) {
                finishCurrentGroup()
                break
            }
            if isAuthorBlockNoise(line.text) {
                finishCurrentGroup()
                if authorGroups.isEmpty {
                    break
                }
                continue
            }

            if isLikelyAuthorLine(line.text) {
                if !currentGroup.isEmpty, !hasIncompleteAuthorName(in: currentGroup) {
                    finishCurrentGroup()
                }
                currentGroup.append(line.text)
            } else if !currentGroup.isEmpty, isAuthorLineContinuation(line.text, after: currentGroup) {
                currentGroup.append(line.text)
            } else {
                finishCurrentGroup()
                break
            }
        }
        finishCurrentGroup()
        return authorGroups.isEmpty ? nil : authorGroups.joined(separator: ";")
    }

    private func isAuthorLineContinuation(_ line: String, after currentGroup: [String]) -> Bool {
        let normalized = normalizedAuthorSource(line)
        guard normalized.count <= FirstPageParsingRules.maximumAuthorNameLength,
              normalized.rangeOfCharacter(from: .letters) != nil,
              !line.contains("@") else {
            return false
        }
        if normalized.contains(",") || normalized.contains(";") {
            let fragments = authorNameFragments(in: normalized)
            let wordCounts = fragments.map { $0.split(whereSeparator: \Character.isWhitespace).count }
            return hasIncompleteAuthorName(in: currentGroup)
                && !fragments.isEmpty
                && fragments.allSatisfy(isPlausibleNameFragment)
                && wordCounts.contains { $0 >= 2 }
        }
        let words = normalized.split(whereSeparator: \Character.isWhitespace)
        guard (1...4).contains(words.count), isPlausibleNameFragment(normalized) else { return false }
        return hasIncompleteAuthorName(in: currentGroup)
    }

    private func isLikelyAuthorLine(_ text: String) -> Bool {
        let normalized = normalizedAuthorSource(text)
        guard normalized.count <= FirstPageParsingRules.maximumAuthorLineLength,
              normalized.rangeOfCharacter(from: .letters) != nil,
              !normalized.contains(":") else {
            return false
        }

        let fragments = authorNameFragments(in: normalized)
        guard !fragments.isEmpty, fragments.allSatisfy(isPlausibleNameFragment) else {
            return false
        }

        let wordCounts = fragments.map { $0.split(whereSeparator: \Character.isWhitespace).count }
        if fragments.count > 1 {
            let completeNameCount = wordCounts.count(where: { $0 >= 2 })
            return wordCounts.allSatisfy { $0 >= 2 }
                || (fragments.count >= 3 && completeNameCount >= 2 && wordCounts.last == 1)
        }
        return (2...8).contains(wordCounts[0])
    }

    private func authorNameFragments(in value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func hasIncompleteAuthorName(in lines: [String]) -> Bool {
        let fragments = authorNameFragments(in: normalizedAuthorSource(lines.joined(separator: " ")))
        guard fragments.count >= 2, let lastFragment = fragments.last else { return false }
        return lastFragment.split(whereSeparator: \Character.isWhitespace).count == 1
    }

    private func isPlausibleNameFragment(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .decimalDigits) == nil else { return false }
        let words = value.split(whereSeparator: \Character.isWhitespace)
        guard (1...8).contains(words.count) else { return false }

        let particles: Set<String> = [
            "al", "bin", "da", "de", "del", "della", "der", "di", "du", "la", "le", "van", "von"
        ]
        var hasProperNameWord = false
        for word in words {
            let token = String(word).trimmingCharacters(
                in: CharacterSet.punctuationCharacters.union(.symbols)
            )
            guard let firstLetter = token.first(where: { $0.isLetter }) else { return false }
            if particles.contains(token.lowercased()) {
                continue
            }
            guard firstLetter.isUppercase else { return false }
            hasProperNameWord = true
        }
        return hasProperNameWord
    }

    private func isAuthorBlockNoise(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.range(
            of: #"\b(?:llc|incorporated|inc|ltd|limited|corp|corporation|company|gmbh|plc)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if lowered.range(
            of: #"\b(?:(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{4})\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        let markers = [
            "university", "department", "institute", "institution", "laboratory",
            "school of", "college of", "faculty of", "research", "deepmind",
            "polytechnic", "politecnico", "academy", "esat", "leuven",
            "proceedings", "conference", "workshop", "journal", "volume", "copyright",
            "design document", "working title", "prototype", "program", "campaign", "storytelling",
            "united states", "united kingdom", "south korea", "new zealand", "saudi arabia",
            "@", "orcid", "correspond", "©"
        ]
        return markers.contains { lowered.contains($0) }
    }

    private func isSectionBoundary(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:(?:\d+(?:\.\d+)*|[ivxlcdm]+)[.)]?\s+)?(?:abstract|summary|introduction|keywords|key\s+words)(?:\s*[:.—–-]\s*.*)?$"#
        return normalized.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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

private struct FirstPageMetadata {
    let title: String?
    let authors: String?
}

private struct FirstPageLine {
    let text: String
    let bounds: CGRect
    let fontSize: CGFloat
}

private struct FirstPageTitleBlock {
    let indices: Range<Int>
}

private enum FirstPageParsingRules {
    static let titleCandidateLineLimit = 40
    static let minimumTitleFontRatio: CGFloat = 1.15
    static let titleLineFontRatio: CGFloat = 0.85
    static let maximumTitleLineCount = 4
    static let maximumTitleLineSpacingRatio: CGFloat = 2.2
    static let authorScanLineLimit = 24
    static let maximumAuthorLineLength = 240
    static let maximumAuthorNameLength = 160
    static let maximumEmbeddedAuthorLength = 1_000
}
