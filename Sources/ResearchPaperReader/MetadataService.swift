import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct MetadataService {
    static func enrich(_ paper: Paper) async -> Paper {
        var p = paper
        guard p.documentKind == .researchPaper else { return p }

        let firstPage = String(p.allText.prefix(3_000))

        if p.title.hasAuthorSwapPattern {
            if p.publicationNumber.isEmpty {
                p.publicationNumber = p.arxivId.isEmpty ? p.title : p.arxivId
            }
            p.title = ""
            p.authors = ""
        }

        if p.publicationNumber.isEmpty {
            if !p.arxivId.isEmpty { p.publicationNumber = p.arxivId }
            else if !p.doi.isEmpty { p.publicationNumber = p.doi }
        }

        let needsTitle   = p.title.isEmpty
        let needsAuthors = p.authors.isEmpty || p.authors == "Unknown authors"
        let needsYear    = p.year.isEmpty
        guard needsTitle || needsAuthors || needsYear else { return p }

        if p.doi.isEmpty, let doi = extractDOI(from: firstPage) { p.doi = doi }
        if p.arxivId.isEmpty, let arxiv = extractArxivID(from: firstPage) { p.arxivId = arxiv }

        if !p.doi.isEmpty {
            if let result = await lookupCrossRef(doi: p.doi) {
                apply(result, to: &p)
                return p
            }
        }

        if !p.arxivId.isEmpty {
            if let result = await lookupArxiv(id: p.arxivId) {
                apply(result, to: &p)
                return p
            }
        }

        if let result = await aiExtractMetadata(from: firstPage) {
            apply(result, to: &p)
            return p
        }

        p.enrichmentFailed = true
        return p
    }

    static func extractDOI(from text: String) -> String? {
        let pattern = #"10\.\d{4,}/[^\s,;()\[\]{}]+"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var doi = String(text[range])
        if doi.last == "." { doi = String(doi.dropLast()) }
        return doi.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractArxivID(from text: String) -> String? {
        let patterns = [
            #"arXiv:\s*(\d{4}\.\d{4,5})"#,
            #"arxiv\.org/(?:abs|pdf)/(\d{4}\.\d{4,5})"#,
        ]
        for p in patterns {
            if let match = text.range(of: p, options: [.regularExpression, .caseInsensitive]) {
                let cleaned = String(text[match])
                if let id = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .filter({ $0.count >= 8 }).first {
                    return id
                }
            }
        }
        return nil
    }

    private static func lookupCrossRef(doi: String) async -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        guard let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.crossref.org/works/\(encoded)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any] else { return nil }

            let title = (message["title"] as? [String])?.first ?? ""
            let authors: String = {
                guard let items = message["author"] as? [[String: String]] else { return "" }
                return items.compactMap { [$0["given"], $0["family"]].compactMap { $0 }.joined(separator: " ") }.joined(separator: ", ")
            }()
            let year: String = {
                let parts = (message["published-print"] as? [String: Any])?["date-parts"] as? [Int]
                    ?? (message["published-online"] as? [String: Any])?["date-parts"] as? [Int]
                    ?? (message["issued"] as? [String: Any])?["date-parts"] as? [Int]
                return parts?.first.map(String.init) ?? ""
            }()
            let abstract: String = {
                guard let raw = message["abstract"] as? String else { return "" }
                return raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            let venue = (message["container-title"] as? [String])?.first ?? ""

            return (title, authors, year, abstract, venue)
        } catch {
            return nil
        }
    }

    private static func lookupArxiv(id: String) async -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        guard let url = URL(string: "https://export.arxiv.org/api/query?id_list=\(id)&max_results=1") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let xml = String(data: data, encoding: .utf8) else { return nil }
            guard let entry = xml.slice(from: "<entry>", to: "</entry>") else { return nil }

            let clean: (String) -> String = { s in
                s.replacingOccurrences(of: "<![CDATA[", with: "")
                    .replacingOccurrences(of: "]]>", with: "")
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }

            let title = entry.slice(from: "<title>", to: "</title>").map(clean) ?? ""

            let authors: String = {
                var names: [String] = []
                var remainder = entry
                while let name = remainder.slice(from: "<name>", to: "</name>") {
                    names.append(clean(name))
                    if let r = remainder.range(of: "</name>")?.upperBound {
                        remainder = String(remainder[r...])
                    } else { break }
                }
                return names.joined(separator: ", ")
            }()

            let year: String = {
                guard let published = entry.slice(from: "<published>", to: "</published>") else { return "" }
                return String(clean(published).prefix(4))
            }()

            let summary = entry.slice(from: "<summary>", to: "</summary>").map(clean) ?? ""

            return (title, authors, year, summary, "arXiv")
        } catch {
            return nil
        }
    }

    private static func aiExtractMetadata(from text: String) async -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        if let result = await foundationModelExtract(from: text) {
            return result
        }
        return heuristicExtractMetadata(from: text)
    }

    private static func foundationModelExtract(from text: String) async -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            let instructions = "Extract the title, authors, publication year, and abstract from this research paper text."
            let prompt = """
            Return a JSON object with keys: title, authors (comma-separated), year, abstract, venue.

            Paper text:
            \(text.prefix(2_000))
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return parseMetadataJSON(response.content)
            } catch { return nil }
        }
        #endif
        return nil
    }

    private static func parseMetadataJSON(_ json: String) -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        let cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^```(?:json)?\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s*```$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
        return (obj["title"] ?? "", obj["authors"] ?? "", obj["year"] ?? "", obj["abstract"] ?? "", obj["venue"] ?? "")
    }

    private static func heuristicExtractMetadata(from text: String) -> (title: String, authors: String, year: String, abstract: String, venue: String)? {
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 3 else { return nil }

        let title = lines[0].trimmingCharacters(in: .whitespaces)
        let authors = lines[1].trimmingCharacters(in: .whitespaces)
        let year: String = {
            let yearPattern = #"20\d{2}|19\d{2}"#
            for line in lines.prefix(5) {
                if let r = line.range(of: yearPattern, options: .regularExpression) {
                    return String(line[r])
                }
            }
            return ""
        }()
        let abstract = LocalPaperAI.abstractCandidate(from: text)

        return (title, authors, year, abstract, "")
    }

    private static func apply(_ result: (title: String, authors: String, year: String, abstract: String, venue: String), to paper: inout Paper) {
        if !result.title.isEmpty { paper.title = result.title }
        if !result.authors.isEmpty { paper.authors = result.authors }
        if !result.year.isEmpty { paper.year = result.year }
        if !result.abstract.isEmpty { paper.abstract = result.abstract }
        if !result.venue.isEmpty { paper.venue = result.venue }
    }
}

extension String {
    var hasAuthorSwapPattern: Bool {
        starts(with: "arXiv:")
        || range(of: #"^\d[\d\-\.]+$"#, options: .regularExpression) != nil
        || range(of: #"\d{4}\.\d{4,5}"#, options: .regularExpression) != nil
    }
}

private extension String {
    func slice(from: String, to: String) -> String? {
        guard let start = range(of: from)?.upperBound,
              let end = self[start...].range(of: to)?.lowerBound else { return nil }
        return String(self[start..<end])
    }
}
