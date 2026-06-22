import Foundation
import NaturalLanguage

enum CitationFormatError: LocalizedError {
    case unsupported
    case noRecords

    var errorDescription: String? {
        switch self {
        case .unsupported: "Use BibTeX or RIS citation data."
        case .noRecords: "No complete citation records were found."
        }
    }
}

private let bibTeXEntryRegex = try! NSRegularExpression(pattern: #"(?s)@(\w+)\s*\{\s*([^,]+),(.+?)(?=\n\s*\}\s*(?:\n|$))"#)
private let bibFieldRegex = try! NSRegularExpression(pattern: #"(?is)(\w+)\s*=\s*(?:\{((?:[^{}]|\{[^{}]*\})*)\}|\"([^\"]*)\")\s*,?"#)
let doiPattern = #"10\.\d{4,}/[^\s,;()\[\]{}]+"#
let yearPattern = #"(?:19|20)\d{2}"#
let referenceMarkerPattern = #"^\s*(?:\[\d{1,4}\]|\d{1,4}[\.\)])\s+"#
let referenceLineCleanPattern = #"^\s*(?:\[\d{1,4}\]|\d{1,4}[\.\)])\s+"#
private let referenceHeadingPattern = #"(?im)^\s*(?:references|bibliography|works cited)\s*$"#
private let referenceNoiseTerms = [
    "addendum", "appendix", "all rights reserved", "copyright", "continued on",
    "footer", "footnote", "supplementary material", "page intentionally left blank"
]

extension String {
    var normalizedDOI: String {
        lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CitationService {
    static func parse(_ text: String) throws -> [CitationRecord] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CitationFormatError.noRecords }
        if trimmed.contains("@") && trimmed.contains("{") {
            let records = parseBibTeX(trimmed)
            guard !records.isEmpty else { throw CitationFormatError.noRecords }
            return records
        }
        if trimmed.contains("TY  -") || trimmed.contains("ER  -") {
            let records = parseRIS(trimmed)
            guard !records.isEmpty else { throw CitationFormatError.noRecords }
            return records
        }
        throw CitationFormatError.unsupported
    }

    static func deduplicated(_ records: [CitationRecord]) -> [CitationRecord] {
        var result: [CitationRecord] = []
        var indices: [String: Int] = [:]
        for record in records where !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let index = indices[record.fingerprint] {
                result[index] = merged(result[index], record)
            } else {
                indices[record.fingerprint] = result.count
                result.append(record)
            }
        }
        return result
    }

    static func merged(_ lhs: CitationRecord, _ rhs: CitationRecord) -> CitationRecord {
        var result = lhs
        if result.title.isEmpty { result.title = rhs.title }
        if result.authors.isEmpty { result.authors = rhs.authors }
        if result.year.isEmpty { result.year = rhs.year }
        if result.venue.isEmpty { result.venue = rhs.venue }
        if result.doi.isEmpty { result.doi = rhs.doi }
        if result.arxivID.isEmpty { result.arxivID = rhs.arxivID }
        if result.abstract.isEmpty { result.abstract = rhs.abstract }
        if result.citationKey.isEmpty { result.citationKey = rhs.citationKey }
        return result
    }

    static func bibTeX(for records: [CitationRecord]) -> String {
        records.map { record in
            let key = record.citationKey.isEmpty ? citationKey(for: record) : record.citationKey
            var fields = ["  title = {\(record.title)}"]
            if !record.authors.isEmpty { fields.append("  author = {\(record.authors)}") }
            if !record.year.isEmpty { fields.append("  year = {\(record.year)}") }
            if !record.venue.isEmpty { fields.append("  journal = {\(record.venue)}") }
            if !record.doi.isEmpty { fields.append("  doi = {\(record.doi)}") }
            return "@article{\(key),\n\(fields.joined(separator: ",\n"))\n}"
        }.joined(separator: "\n\n")
    }

    static func ris(for records: [CitationRecord]) -> String {
        records.map { record in
            var lines = ["TY  - JOUR", "TI  - \(record.title)"]
            for author in splitAuthors(record.authors) { lines.append("AU  - \(author)") }
            if !record.year.isEmpty { lines.append("PY  - \(record.year)") }
            if !record.venue.isEmpty { lines.append("JO  - \(record.venue)") }
            if !record.doi.isEmpty { lines.append("DO  - \(record.doi)") }
            lines.append("ER  -")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func citationKey(for record: CitationRecord) -> String {
        let surname = splitAuthors(record.authors).first?
            .split(separator: ",").first.map(String.init)?
            .split(separator: " ").last.map(String.init) ?? "source"
        let titleWord = record.title.split(whereSeparator: { !$0.isLetter }).first.map(String.init) ?? "work"
        return (surname + record.year + titleWord).lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func record(for paper: Paper) -> CitationRecord {
        var record = CitationRecord(
            title: paper.title,
            authors: paper.authors,
            year: paper.year,
            venue: paper.venue,
            doi: paper.doi,
            arxivID: paper.arxivId,
            abstract: paper.abstract,
            source: .manual
        )
        record.citationKey = citationKey(for: record)
        return record
    }

    private static func parseBibTeX(_ text: String) -> [CitationRecord] {
        let ns = text as NSString
        return bibTeXEntryRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            guard match.numberOfRanges == 4 else { return nil }
            let key = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = ns.substring(with: match.range(at: 3))
            let fields = bibFields(body)
            guard let title = fields["title"], !title.isEmpty else { return nil }
            return CitationRecord(
                title: title,
                authors: fields["author"] ?? "",
                year: fields["year"] ?? "",
                venue: fields["journal"] ?? fields["booktitle"] ?? "",
                doi: fields["doi"] ?? "",
                abstract: fields["abstract"] ?? "",
                citationKey: key,
                source: .bibtex
            )
        }
    }

    private static func bibFields(_ body: String) -> [String: String] {
        let ns = body as NSString
        var fields: [String: String] = [:]
        for match in bibFieldRegex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            fields[name] = ns.substring(with: valueRange)
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fields
    }

    private static func parseRIS(_ text: String) -> [CitationRecord] {
        let blocks = text.components(separatedBy: "ER  -")
        return blocks.compactMap { block in
            var values: [String: [String]] = [:]
            for line in block.components(separatedBy: .newlines) where line.count >= 6 {
                let key = String(line.prefix(2))
                guard line.dropFirst(2).hasPrefix("  -") else { continue }
                let value = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                values[key, default: []].append(value)
            }
            guard let title = (values["TI"] ?? values["T1"])?.first, !title.isEmpty else { return nil }
            return CitationRecord(
                title: title,
                authors: (values["AU"] ?? []).joined(separator: "; "),
                year: values["PY"]?.first ?? values["Y1"]?.first ?? "",
                venue: values["JO"]?.first ?? values["JF"]?.first ?? "",
                doi: values["DO"]?.first ?? "",
                abstract: values["AB"]?.first ?? "",
                source: .ris
            )
        }
    }

    private static func splitAuthors(_ authors: String) -> [String] {
        if authors.contains(" and ") { return authors.components(separatedBy: " and ") }
        return authors.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

enum SemanticSearchService {
    private static let minimumResultScore = 0.16
    private static let minimumSemanticScore = 0.28
    private static let maximumResultsPerPaper = 3
    private static let searchStopWords: Set<String> = [
        "about", "after", "also", "and", "are", "based", "been", "before", "being", "between",
        "can", "could", "did", "does", "from", "have", "how", "into", "its", "may", "might",
        "more", "most", "not", "our", "should", "than", "that", "the", "their", "then", "there",
        "these", "they", "this", "those", "through", "using", "was", "were", "what", "when",
        "where", "which", "while", "who", "why", "will", "with", "would", "your",
    ]

    static func search(query: String, papers: [Paper], limit: Int = 12) -> [SemanticSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return [] }
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let queryVector = embedding?.vector(for: normalized)

        var results: [SemanticSearchResult] = []
        for paper in papers {
            var paperResults: [SemanticSearchResult] = []
            for chunk in chunks(for: paper) {
                let lexical = lexicalScore(query: normalized, text: chunk.text)
                let semantic: Double
                if let queryVector, let vector = embedding?.vector(for: chunk.text) {
                    semantic = cosine(queryVector, vector)
                } else {
                    semantic = lexical
                }
                let metadataBoost = paper.title.localizedCaseInsensitiveContains(normalized) ? 0.2 : 0
                let score = max(0, semantic) * 0.60 + lexical * 0.40 + metadataBoost
                let hasMeaningfulOverlap = lexicalMatchCount(query: normalized, text: chunk.text) > 0
                let passesRelevanceGate = hasMeaningfulOverlap || semantic >= minimumSemanticScore
                if passesRelevanceGate, score >= minimumResultScore {
                    paperResults.append(SemanticSearchResult(
                        paperID: paper.id,
                        paperTitle: paper.title,
                        page: chunk.page,
                        text: chunk.text,
                        score: score
                    ))
                }
            }
            results.append(contentsOf: paperResults.sorted { $0.score > $1.score }.prefix(maximumResultsPerPaper))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func groundedAnswer(question: String, results: [SemanticSearchResult]) -> String {
        guard !results.isEmpty else {
            return "No relevant passages were found in the local library. Try a broader question or add more documents."
        }
        let evidence = results.prefix(5).map { result in
            let page = result.page.map { ", p. \($0)" } ?? ""
            return "- \(bestSentence(in: result.text, for: question)) ([\(result.paperTitle)\(page)])"
        }
        return (["Based only on passages in your local library:", ""] + evidence + ["", "Open a cited result to verify it in context."])
            .joined(separator: "\n")
    }

    private static func chunks(for paper: Paper) -> [(text: String, page: Int?)] {
        var chunks: [(String, Int?)] = []
        if !paper.abstract.isEmpty { chunks.append((paper.abstract, 1)) }
        for section in paper.sections where section.kind != .references && !section.text.isEmpty {
            chunks.append((String(section.text.prefix(1_500)), section.page))
        }
        if chunks.count < 2 {
            let pages = pageTextsForSearch(for: paper)
            chunks.append(contentsOf: pages.enumerated().compactMap { index, text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? nil : (String(clean.prefix(1_500)), index + 1)
            })
        }
        chunks.append(contentsOf: paper.notes.map { ("\($0.quote) \($0.body)", $0.page) })
        return chunks
    }

    private static func pageTextsForSearch(for paper: Paper) -> [String] {
        let text = searchableFullText(for: paper)
        let offsets = paper.allTextPageOffsets.filter { $0 < text.count }
        guard !offsets.isEmpty else { return [String(text.prefix(3_000))] }
        var idx = text.startIndex
        return offsets.enumerated().map { index, start in
            let end = index + 1 < offsets.count ? offsets[index + 1] : text.count
            guard start < end, start < text.count else { return "" }
            let lower = index == 0 ? text.index(text.startIndex, offsetBy: start) : text.index(idx, offsetBy: start - offsets[index - 1])
            let upper = text.index(lower, offsetBy: min(end, text.count) - start)
            idx = upper
            return String(text[lower..<upper])
        }
    }

    private static func searchableFullText(for paper: Paper) -> String {
        let text = paper.allText
        let headingPattern = #"(?im)^\s*(?:\d+[.\s]+)?(?:references|bibliography|works cited)\s*$"#
        if let heading = text.range(of: headingPattern, options: .regularExpression) {
            return String(text[..<heading.lowerBound])
        }

        if let references = paper.sections.first(where: { $0.kind == .references }),
           !references.text.isEmpty {
            let marker = String(references.text.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
            if marker.count >= 20,
               let range = text.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) {
                return String(text[..<range.lowerBound])
            }
        }
        return text
    }

    private static func lexicalScore(query: String, text: String) -> Double {
        let queryTokens = Set(tokens(query))
        guard !queryTokens.isEmpty else { return 0 }
        let textTokens = Set(tokens(text))
        return Double(queryTokens.intersection(textTokens).count) / Double(queryTokens.count)
    }

    private static func lexicalMatchCount(query: String, text: String) -> Int {
        Set(tokens(query)).intersection(Set(tokens(text))).count
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap { token in
            var value = String(token)
            guard value.count > 2, !searchStopWords.contains(value) else { return nil }
            for suffix in ["ing", "ed", "es", "s"] where value.count > suffix.count + 3 && value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                break
            }
            return value
        }
    }

    private static func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot = 0.0, left = 0.0, right = 0.0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            left += lhs[index] * lhs[index]
            right += rhs[index] * rhs[index]
        }
        guard left > 0, right > 0 else { return 0 }
        return dot / (sqrt(left) * sqrt(right))
    }

    private static func bestSentence(in text: String, for query: String) -> String {
        let candidates = text.split(whereSeparator: { ".!?\n".contains($0) }).map(String.init)
        return candidates.max { lexicalScore(query: query, text: $0) < lexicalScore(query: query, text: $1) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? String(text.prefix(280))
    }
}

enum EvidenceService {
    static let defaultColumnNames = ["Research question", "Method", "Sample or dataset", "Key finding", "Limitations"]

    static func makeTable(name: String, papers: [Paper]) -> EvidenceTable {
        let columns = defaultColumnNames.map { EvidenceColumn(name: $0) }
        let rows = papers.map { makeRow(for: $0, columns: columns) }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return EvidenceTable(name: cleanName.isEmpty ? "Evidence Review" : cleanName, columns: columns, rows: rows)
    }

    static func makeRow(for paper: Paper, columns: [EvidenceColumn]) -> EvidenceRow {
        EvidenceRow(paperID: paper.id, cells: columns.map { column in
            let suggestion = suggestedValue(column.name, paper: paper)
            return EvidenceCell(columnID: column.id, value: suggestion, quote: suggestion)
        })
    }

    static func populateEmptyCells(in table: inout EvidenceTable, papers: [Paper]) {
        for rowIndex in table.rows.indices {
            guard let paper = papers.first(where: { $0.id == table.rows[rowIndex].paperID }) else { continue }
            for cellIndex in table.rows[rowIndex].cells.indices {
                guard let column = table.columns.first(where: {
                    $0.id == table.rows[rowIndex].cells[cellIndex].columnID
                }) else { continue }
                if table.rows[rowIndex].cells[cellIndex].value.isEmpty {
                    table.rows[rowIndex].cells[cellIndex].value = suggestedValue(column.name, paper: paper)
                }
                if table.rows[rowIndex].cells[cellIndex].quote.isEmpty {
                    table.rows[rowIndex].cells[cellIndex].quote = table.rows[rowIndex].cells[cellIndex].value
                }
            }
        }
        table.updatedAt = Date()
    }

    static func csv(for table: EvidenceTable, papers: [Paper]) -> String {
        let header = ["Source", "Authors", "Year"] + table.columns.map(\.name)
        let rows = table.rows.map { row -> [String] in
            let source = papers.first(where: { $0.id == row.paperID })
            let values = table.columns.map { column in
                row.cells.first(where: { $0.columnID == column.id })?.value ?? ""
            }
            return [source?.title ?? "Missing source", source?.authors ?? "", source?.year ?? ""] + values
        }
        return ([header] + rows).map { fields in
            fields.map { value in
                "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    static func markdown(for table: EvidenceTable, papers: [Paper]) -> String {
        let header = ["Source", "Authors", "Year"] + table.columns.map(\.name)
        let rows = table.rows.map { row -> [String] in
            let source = papers.first(where: { $0.id == row.paperID })
            let values = table.columns.map { column in
                row.cells.first(where: { $0.columnID == column.id })?.value ?? ""
            }
            return [source?.title ?? "Missing source", source?.authors ?? "", source?.year ?? ""] + values
        }
        let markdownRows = ([header] + [Array(repeating: "---", count: header.count)] + rows)
            .map { fields in
                "| " + fields.map(markdownTableCell).joined(separator: " | ") + " |"
            }
        return (["# \(table.name)", ""] + markdownRows).joined(separator: "\n") + "\n"
    }

    private static func markdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "<br>")
    }

    static func outline(workspace: SynthesisWorkspace, papers: [Paper], table: EvidenceTable?) -> String {
        let selected = papers.filter { workspace.paperIDs.contains($0.id) }
        var lines = ["# \(workspace.name)", "", "## Scope", "", "Synthesis of \(selected.count) selected sources.", ""]
        for heading in ["Themes and claims", "Methods and evidence", "Points of agreement", "Conflicts and limitations", "Open questions"] {
            lines += ["## \(heading)", ""]
            if heading == "Methods and evidence", let table {
                for row in table.rows {
                    guard let paper = selected.first(where: { $0.id == row.paperID }) else { continue }
                    let values = row.cells.compactMap { cell -> String? in
                        guard !cell.value.isEmpty,
                              let column = table.columns.first(where: { $0.id == cell.columnID }) else { return nil }
                        return "**\(column.name):** \(cell.value)"
                    }
                    lines.append("- \(paper.title): \(values.joined(separator: "; "))")
                }
            } else {
                lines.append("- Add evidence-backed synthesis here.")
            }
            lines.append("")
        }
        lines += ["## Sources", ""]
        for paper in selected {
            let citation = CitationService.record(for: paper)
            lines.append("- [@\(citation.citationKey)] \(paper.authors). \(paper.title). \(paper.year).")
        }
        return lines.joined(separator: "\n")
    }

    static func suggestedValue(_ column: String, paper: Paper) -> String {
        switch column {
        case "Research question": return paper.abstract.isEmpty ? "" : firstSentence(paper.abstract)
        case "Method": return sectionText(.method, paper: paper)
        case "Sample or dataset": return bestSentence(containing: ["sample", "dataset", "participants", "subjects"], in: paper.allText)
        case "Key finding": return sectionText(.results, paper: paper)
        case "Limitations": return bestSentence(containing: ["limitation", "limited", "future work"], in: paper.allText)
        default: return ""
        }
    }

    private static func sectionText(_ kind: SectionKind, paper: Paper) -> String {
        guard let text = paper.sections.first(where: { $0.kind == kind })?.text else { return "" }
        return firstSentence(text)
    }

    private static func bestSentence(containing terms: [String], in text: String) -> String {
        let sentences = text.split(whereSeparator: { ".!?\n".contains($0) }).map(String.init)
        return sentences.first { sentence in terms.contains { sentence.localizedCaseInsensitiveContains($0) } }
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(420)) } ?? ""
    }

    private static func firstSentence(_ text: String) -> String {
        String((text.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(420))
    }
}

enum CitationGraphService {
    static func edges(for papers: [Paper]) -> [CitationEdge] {
        let doiToPaper = papers.reduce(into: [String: Paper.ID]()) { result, paper in
            let doi = paper.doi.normalizedDOI
            if !doi.isEmpty { result[doi] = result[doi] ?? paper.id }
        }
        let fingerprintToPaper = papers.reduce(into: [String: Paper.ID]()) { result, paper in
            let fingerprint = CitationService.record(for: paper).fingerprint
            result[fingerprint] = result[fingerprint] ?? paper.id
        }
        return papers.flatMap { paper in
            extractReferences(from: paper).map { reference in
                let resolvedPaperID = doiToPaper[reference.doi.normalizedDOI]
                    ?? fingerprintToPaper[reference.fingerprint]
                return CitationEdge(
                    sourcePaperID: paper.id,
                    targetFingerprint: reference.fingerprint,
                    targetTitle: reference.title,
                    targetAuthors: reference.authors,
                    targetYear: reference.year,
                    targetVenue: reference.venue,
                    targetDOI: reference.doi,
                    targetPaperID: resolvedPaperID
                )
            }
        }
    }

    static func extractReferences(from paper: Paper) -> [CitationRecord] {
        let referenceText = paper.sections.first(where: { $0.kind == .references })?.text
            ?? inferredReferenceBlock(from: paper.allText)
        guard !referenceText.isEmpty else { return [] }
        return CitationService.deduplicated(referenceBlocks(in: referenceText).compactMap { reference in
            guard !isReferenceNoise(reference) else { return nil }
            let doi = MetadataService.extractDOI(from: reference) ?? ""
            return parsedReference(reference, doi: doi)
        })
    }

    /// PDF text extraction commonly wraps one bibliography entry over several lines. Build the
    /// complete entry before parsing so a first-line author fragment is never mistaken for a title.
    private static func referenceBlocks(in text: String) -> [String] {
        var blocks: [String] = []
        var current: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.range(of: referenceMarkerPattern, options: .regularExpression) != nil {
                if let current { blocks.append(current) }
                current = line
                continue
            }

            guard let existing = current, isReferenceContinuation(line) else { continue }
            current = joiningWrappedReferenceLine(existing, line)
        }

        if let current { blocks.append(current) }
        return blocks
    }

    private static func isReferenceContinuation(_ line: String) -> Bool {
        if line.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return false }
        if line.range(of: referenceHeadingPattern, options: .regularExpression) != nil { return false }
        if referenceNoiseTerms.contains(where: { line.localizedCaseInsensitiveContains($0) }) { return false }
        return line.count > 1
    }

    private static func joiningWrappedReferenceLine(_ existing: String, _ continuation: String) -> String {
        guard existing.hasSuffix("-") else { return existing + " " + continuation }

        // A DOI's terminal hyphen is meaningful, while a prose line-break hyphen is not.
        let tail = existing.suffix(120).lowercased()
        if tail.contains("doi.org/") || tail.contains("doi:") {
            return existing + continuation
        }
        return String(existing.dropLast()) + continuation
    }

    private static func inferredReferenceBlock(from text: String) -> String {
        let tail = String(text.suffix(min(30_000, text.count)))
        guard let heading = tail.range(of: referenceHeadingPattern, options: .regularExpression) else { return "" }
        return String(tail[heading.upperBound...])
    }

    private static func isReferenceNoise(_ line: String) -> Bool {
        let cleaned = line.replacingOccurrences(of: referenceLineCleanPattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = cleaned.lowercased()
        guard !cleaned.hasPrefix("&"), !cleaned.hasPrefix("©") else { return true }
        return referenceNoiseTerms.contains { lowercased.contains($0) }
    }

    private static func parsedReference(_ line: String, doi: String) -> CitationRecord? {
        let cleaned = line.replacingOccurrences(of: referenceLineCleanPattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.hasPrefix("&"), !cleaned.hasPrefix("©") else { return nil }
        let parts = cleaned.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let year = cleaned.range(of: yearPattern, options: .regularExpression).map { String(cleaned[$0]) } ?? ""
        guard !year.isEmpty || !doi.isEmpty, parts.count >= 2 else { return nil }
        let yearIndex = parts.firstIndex { part in !year.isEmpty && part.contains(year) }
        var titleIndex = yearIndex == 1 && parts.count > 2 ? 2 : min(1, max(0, parts.count - 1))
        while titleIndex < parts.count - 1 && isAuthorContinuation(parts[titleIndex]) {
            titleIndex += 1
        }
        let title = String((parts.indices.contains(titleIndex) ? parts[titleIndex] : cleaned).prefix(300))
        let authors = titleIndex > 0 ? parts[..<titleIndex].filter { !$0.contains(year) }.joined(separator: ". ") : ""
        let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let authorWords = authors.split(whereSeparator: { !$0.isLetter })
        let lowercasedAuthors = authors.lowercased()
        guard title.count >= 10,
              titleWords.count >= 2,
              authorWords.count >= 2,
              !authors.hasPrefix("&"),
              !authors.hasPrefix("©"),
              !referenceNoiseTerms.contains(where: { lowercasedAuthors.contains($0) }) else { return nil }
        let venueIndex = titleIndex + 1
        let venue = parts.indices.contains(venueIndex) ? String(parts[venueIndex].prefix(200)) : ""
        return CitationRecord(
            title: title,
            authors: authors,
            year: year,
            venue: venue,
            doi: doi,
            source: .extractedReference
        )
    }

    private static func isAuthorContinuation(_ part: String) -> Bool {
        let candidate = part.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.range(of: #"^(?:&|and)\s+"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return candidate.range(
            of: #"^[\p{L}'’\-]+,\s*(?:[\p{L}]\.?\s*){1,4}$"#,
            options: .regularExpression
        ) != nil
    }

}

enum DiscoveryService {
    static func search(query: String, rows: Int = 20) async throws -> [DiscoveryPaper] {
        try await crossRefSearch(query: query, parameter: "query.bibliographic", rows: rows)
    }

    static func search(author: String, rows: Int = 20) async throws -> [DiscoveryPaper] {
        try await crossRefSearch(query: author, parameter: "query.author", rows: rows)
    }

    private static func crossRefSearch(query: String, parameter: String, rows: Int) async throws -> [DiscoveryPaper] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: parameter, value: clean),
            URLQueryItem(name: "rows", value: String(min(50, max(1, rows)))),
            URLQueryItem(name: "select", value: "DOI,title,author,published,container-title,abstract,is-referenced-by-count"),
            URLQueryItem(name: "mailto", value: "research-paper-reader@localhost"),
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decodeCrossRefResults(data)
    }

    static func recommendations(for paper: Paper, rows: Int = 20) async throws -> [DiscoveryPaper] {
        let context = [paper.title, String(paper.abstract.prefix(280))]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        let results = try await search(query: context, rows: rows + 5)
        let localFingerprint = CitationService.record(for: paper).fingerprint
        return Array(results.filter { result in
            discoveryFingerprint(result) != localFingerprint
                && result.doi.normalizedDOI != paper.doi.normalizedDOI
        }.prefix(rows))
    }

    static func recommendations(for paper: DiscoveryPaper, rows: Int = 20) async throws -> [DiscoveryPaper] {
        let results = try await search(query: paper.title, rows: rows + 5)
        return Array(results.filter { $0.id != paper.id }.prefix(rows))
    }

    static func discoveryFingerprint(_ paper: DiscoveryPaper) -> String {
        CitationRecord(title: paper.title, year: paper.year, doi: paper.doi).fingerprint
    }

    static func decodeCrossRefResults(_ data: Data) throws -> [DiscoveryPaper] {
        let envelope = try JSONDecoder().decode(CrossRefEnvelope.self, from: data)
        return envelope.message.items.compactMap { item in
            guard let title = item.title?.first, !title.isEmpty else { return nil }
            let authors = (item.author ?? []).map { author in
                [author.given, author.family].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: ", ")
            let year = item.published?.dateParts.first?.first.map(String.init) ?? ""
            let abstract = (item.abstract ?? "")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return DiscoveryPaper(
                title: title,
                authors: authors,
                year: year,
                venue: item.containerTitle?.first ?? "",
                doi: item.doi ?? "",
                abstract: abstract,
                citedByCount: item.citedByCount ?? 0
            )
        }
    }

    static func refresh(_ alert: ResearchAlert) async throws -> ResearchAlert {
        var updated = alert
        guard alert.isEnabled else { return updated }
        let results: [DiscoveryPaper]
        switch alert.kind {
        case .query:
            results = try await search(query: alert.query, rows: 15)
        case .author:
            results = try await search(author: alert.query, rows: 15)
        case .citations:
            results = try await citingWorks(doi: alert.query, rows: 15)
        }
        updated.matches = results
        updated.lastChecked = Date()
        return updated
    }

    static func citingWorks(doi: String, rows: Int = 20) async throws -> [DiscoveryPaper] {
        let normalized = doi.normalizedDOI
        guard !normalized.isEmpty else { return [] }
        let encodedDOI = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? normalized
        var lookupComponents = URLComponents(string: "https://api.openalex.org/works/https://doi.org/\(encodedDOI)")!
        lookupComponents.queryItems = openAlexIdentityQueryItems()
        guard let lookupURL = lookupComponents.url else { return [] }
        let (lookupData, lookupResponse) = try await URLSession.shared.data(from: lookupURL)
        guard let lookupHTTP = lookupResponse as? HTTPURLResponse, 200..<300 ~= lookupHTTP.statusCode else {
            throw URLError(.resourceUnavailable)
        }
        let work = try JSONDecoder().decode(OpenAlexWork.self, from: lookupData)
        let shortID = work.id.components(separatedBy: "/").last ?? work.id
        var components = URLComponents(string: "https://api.openalex.org/works")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "cites:\(shortID)"),
            URLQueryItem(name: "per-page", value: String(min(50, max(1, rows)))),
        ] + openAlexIdentityQueryItems()
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try decodeOpenAlexResults(data)
    }

    static func decodeOpenAlexResults(_ data: Data) throws -> [DiscoveryPaper] {
        try JSONDecoder().decode(OpenAlexResult.self, from: data).results.map(\.discoveryPaper)
    }

    private static func openAlexIdentityQueryItems() -> [URLQueryItem] {
        let apiKey = UserDefaults.standard.string(forKey: "openAlexAPIKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !apiKey.isEmpty { return [URLQueryItem(name: "api_key", value: apiKey)] }
        return [URLQueryItem(name: "mailto", value: "research-paper-reader@localhost")]
    }

    private struct CrossRefEnvelope: Decodable {
        var message: Message
        struct Message: Decodable { var items: [Item] }
    }

    private struct Item: Decodable {
        var doi: String?
        var title: [String]?
        var author: [Author]?
        var published: Published?
        var containerTitle: [String]?
        var abstract: String?
        var citedByCount: Int?

        enum CodingKeys: String, CodingKey {
            case doi = "DOI"
            case title, author, published, abstract
            case containerTitle = "container-title"
            case citedByCount = "is-referenced-by-count"
        }
    }

    private struct Author: Decodable { var given: String?; var family: String? }
    private struct Published: Decodable {
        var dateParts: [[Int]]
        enum CodingKeys: String, CodingKey { case dateParts = "date-parts" }
    }

    private struct OpenAlexResult: Decodable { var results: [OpenAlexWork] }
    private struct OpenAlexWork: Decodable {
        var id: String
        var title: String
        var doi: String?
        var publicationYear: Int?
        var citedByCount: Int?
        var authorships: [Authorship]?
        var primaryLocation: Location?

        enum CodingKeys: String, CodingKey {
            case id, title, doi, authorships
            case publicationYear = "publication_year"
            case citedByCount = "cited_by_count"
            case primaryLocation = "primary_location"
        }

        var discoveryPaper: DiscoveryPaper {
            DiscoveryPaper(
                title: title,
                authors: (authorships ?? []).compactMap { $0.author?.displayName }.joined(separator: ", "),
                year: publicationYear.map(String.init) ?? "",
                venue: primaryLocation?.source?.displayName ?? "",
                doi: doi?.normalizedDOI ?? "",
                citedByCount: citedByCount ?? 0
            )
        }
    }
    private struct Authorship: Decodable { var author: OpenAlexAuthor? }
    private struct OpenAlexAuthor: Decodable {
        var displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
    private struct Location: Decodable { var source: OpenAlexSource? }
    private struct OpenAlexSource: Decodable {
        var displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
}

enum DiscoveryLinkService {
    static func onlineURL(for paper: DiscoveryPaper) -> URL? {
        let doi = paper.doi.normalizedDOI
        if !doi.isEmpty {
            return URL(string: "https://doi.org/\(doi)")
        }

        let title = paper.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var components = URLComponents(string: "https://search.crossref.org/search/works")
        components?.queryItems = [
            URLQueryItem(name: "q", value: title),
            URLQueryItem(name: "from_ui", value: "yes"),
        ]
        return components?.url
    }
}
