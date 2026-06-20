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
let referenceMarkerPattern = #"(?:\[\d+\]|^\d+[\.\)])"#
let referenceLineCleanPattern = #"^\s*(?:\[\d+\]|\d+[\.\)])\s*"#

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
    static func search(query: String, papers: [Paper], limit: Int = 12) -> [SemanticSearchResult] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return [] }
        let embedding = NLEmbedding.sentenceEmbedding(for: .english)
        let queryVector = embedding?.vector(for: normalized)

        var results: [SemanticSearchResult] = []
        for paper in papers {
            for chunk in chunks(for: paper) {
                let lexical = lexicalScore(query: normalized, text: chunk.text)
                let semantic: Double
                if let queryVector, let vector = embedding?.vector(for: chunk.text) {
                    semantic = cosine(queryVector, vector)
                } else {
                    semantic = lexical
                }
                let metadataBoost = paper.title.localizedCaseInsensitiveContains(normalized) ? 0.2 : 0
                let score = max(0, semantic) * 0.72 + lexical * 0.28 + metadataBoost
                if score > 0.08 {
                    results.append(SemanticSearchResult(
                        paperID: paper.id,
                        paperTitle: paper.title,
                        page: chunk.page,
                        text: chunk.text,
                        score: score
                    ))
                }
            }
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
        for section in paper.sections where !section.text.isEmpty {
            chunks.append((String(section.text.prefix(1_500)), section.page))
        }
        if chunks.count < 2 {
            let pages = pageTexts(for: paper)
            chunks.append(contentsOf: pages.enumerated().compactMap { index, text in
                let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? nil : (String(clean.prefix(1_500)), index + 1)
            })
        }
        chunks.append(contentsOf: paper.notes.map { ("\($0.quote) \($0.body)", $0.page) })
        return chunks
    }

    private static func pageTexts(for paper: Paper) -> [String] {
        let text = paper.allText
        let offsets = paper.allTextPageOffsets
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

    private static func lexicalScore(query: String, text: String) -> Double {
        let queryTokens = Set(tokens(query))
        guard !queryTokens.isEmpty else { return 0 }
        let textTokens = Set(tokens(text))
        return Double(queryTokens.intersection(textTokens).count) / Double(queryTokens.count)
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { token in
            var value = String(token)
            for suffix in ["ing", "ed", "es", "s"] where value.count > suffix.count + 3 && value.hasSuffix(suffix) {
                value.removeLast(suffix.count)
                break
            }
            return value
        }.filter { $0.count > 2 }
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
        let rows = papers.map { paper in
            EvidenceRow(paperID: paper.id, cells: columns.map { column in
                EvidenceCell(columnID: column.id, value: suggestedValue(column.name, paper: paper))
            })
        }
        return EvidenceTable(name: name, columns: columns, rows: rows)
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

    private static func suggestedValue(_ column: String, paper: Paper) -> String {
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
        let doiToPaper = Dictionary(uniqueKeysWithValues: papers.compactMap { paper in
            let doi = paper.doi.normalizedDOI
            return doi.isEmpty ? nil : (doi, paper.id)
        })
        return papers.flatMap { paper in
            extractReferences(from: paper).map { reference in
                CitationEdge(
                    sourcePaperID: paper.id,
                    targetFingerprint: reference.fingerprint,
                    targetTitle: reference.title,
                    targetDOI: reference.doi,
                    targetPaperID: doiToPaper[reference.doi.normalizedDOI]
                )
            }
        }
    }

    static func extractReferences(from paper: Paper) -> [CitationRecord] {
        let referenceText = paper.sections.first(where: { $0.kind == .references })?.text
            ?? String(paper.allText.suffix(min(20_000, paper.allText.count)))
        let lines = referenceText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 25 }
        return CitationService.deduplicated(lines.compactMap { line in
            guard line.range(of: referenceMarkerPattern, options: .regularExpression) != nil else { return nil }
            let doi = MetadataService.extractDOI(from: line) ?? ""
            let year = line.range(of: yearPattern, options: .regularExpression).map { String(line[$0]) } ?? ""
            let title = guessedTitle(from: line)
            guard title.count > 5 else { return nil }
            return CitationRecord(title: title, year: year, doi: doi, source: .extractedReference)
        })
    }

    private static func guessedTitle(from line: String) -> String {
        let cleaned = line.replacingOccurrences(of: referenceLineCleanPattern, with: "", options: .regularExpression)
        let parts = cleaned.components(separatedBy: ". ")
        if parts.count >= 2 { return String(parts[1].prefix(300)) }
        return String(cleaned.prefix(300))
    }

}

enum DiscoveryService {
    static func search(query: String, rows: Int = 20) async throws -> [DiscoveryPaper] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: clean),
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
            results = try await search(query: "author:\(alert.query)", rows: 15)
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
        let lookupURL = URL(string: "https://api.openalex.org/works/https://doi.org/\(encodedDOI)")!
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
            URLQueryItem(name: "mailto", value: "research-paper-reader@localhost"),
        ]
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
