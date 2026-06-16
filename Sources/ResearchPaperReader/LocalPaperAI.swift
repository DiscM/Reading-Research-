import Foundation

enum LocalPaperAI {
    static func abstractCandidate(from pageText: String) -> String {
        let normalized = clean(pageText)
        guard !normalized.isEmpty else { return "" }

        if let abstractRange = normalized.range(of: "abstract", options: [.caseInsensitive]) {
            let remainder = normalized[abstractRange.upperBound...]
            let stopWords = ["introduction", "keywords", "1 introduction"]
            let stopIndex = stopWords
                .compactMap { remainder.range(of: $0, options: [.caseInsensitive])?.lowerBound }
                .min()
            let abstract = stopIndex.map { String(remainder[..<$0]) } ?? String(remainder)
            return String(abstract.prefix(900)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return String(normalized.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func explainSelection(_ text: String, in paper: Paper) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Select text in the PDF, then ask for an explanation."
        }

        let allText = paper.allText
        guard !allText.isEmpty else { return "No extractable text was found for context." }

        let lower = text.lowercased()

        let surrounding: String = {
            guard let range = allText.lowercased().range(of: lower) else { return "" }
            let start = allText.index(allText.startIndex, offsetBy: max(0, allText.distance(from: allText.startIndex, to: range.lowerBound) - 300))
            let end = allText.index(range.upperBound, offsetBy: min(300, allText.distance(from: range.upperBound, to: allText.endIndex)))
            return String(allText[start..<end])
        }()

        let sentences = sentenceCandidates(from: surrounding).filter { $0.localizedCaseInsensitiveContains(text.prefix(40)) }
        var lines: [String] = ["Context around the selected passage:\n"]
        if sentences.isEmpty {
            let excerpt = surrounding.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("> \(excerpt)")
        } else {
            for s in sentences {
                lines.append("> \(s)")
            }
        }

        lines.append("")
        lines.append("This is a local heuristic context extraction. A model-router with Apple Foundation Models, Core ML, or cloud AI would provide a richer explanation.")

        return lines.joined(separator: "\n")
    }

    static func summary(for paper: Paper) -> String {
        let text = String(clean(paper.allText).prefix(15_000))
        guard !text.isEmpty else {
            return "No extractable text was found. This paper may need OCR before AI features can summarize it."
        }

        let abstract = abstractCandidate(from: text)
        let sentences = sentenceCandidates(from: abstract.isEmpty ? text : abstract)
        let topSentences = sentences.prefix(4)

        var lines = ["Local summary generated from on-device PDF text extraction:"]
        for sentence in topSentences {
            lines.append("- \(sentence)")
        }

        if let methodHint = firstSection(named: "method", in: text) {
            lines.append("- Method signal: \(String(methodHint.prefix(260)))")
        }

        lines.append("")
        lines.append("This MVP uses a local heuristic summarizer. The model-router layer is ready to be replaced with Apple Foundation Models, Core ML, MLX, Ollama, or BYOK cloud providers.")
        return lines.joined(separator: "\n")
    }

    static func extraction(for paper: Paper, kind: HighlightKind) -> String {
        let text = String(clean(paper.allText).prefix(30_000))
        guard !text.isEmpty else {
            return "No extractable text was found for this paper yet."
        }

        let keywords: [String]
        switch kind {
        case .claim:
            keywords = ["we show", "we demonstrate", "our results", "we find", "contribution"]
        case .evidence:
            keywords = ["results", "experiment", "evaluation", "significant", "baseline"]
        case .method:
            keywords = ["method", "approach", "model", "algorithm", "procedure"]
        case .limitation:
            keywords = ["limitation", "future work", "however", "threat", "constraint"]
        case .question:
            keywords = ["why", "whether", "unclear", "open question"]
        case .definition:
            keywords = ["defined as", "refers to", "we define", "definition"]
        case .highlight:
            keywords = ["abstract", "introduction", "conclusion"]
        }

        let sentences = sentenceCandidates(from: text)
        let matches = sentences.filter { sentence in
            keywords.contains { sentence.localizedCaseInsensitiveContains($0) }
        }

        let selected = Array(matches.prefix(5))
        guard !selected.isEmpty else {
            return "I could not find strong \(kind.rawValue.lowercased()) signals with the local heuristic extractor."
        }

        return selected.map { "- \($0)" }.joined(separator: "\n")
    }

    static func sections(from text: String) -> [PaperSection] {
        let lines = text.components(separatedBy: "\n")
        let known: [(SectionKind, [String])] = [
            (.abstract,    ["abstract"]),
            (.introduction, ["introduction"]),
            (.relatedWork, ["related work", "background"]),
            (.method,      ["method", "approach", "model", "algorithm", "architecture", "framework", "system design", "proposed method"]),
            (.experiment,  ["experiment", "evaluation", "dataset", "empirical", "setup"]),
            (.results,     ["results", "findings", "outcome"]),
            (.discussion,  ["discussion"]),
            (.conclusion,  ["conclusion", "future work", "summary", "concluding"]),
            (.references,  ["references", "bibliography"]),
            (.appendix,    ["appendix"]),
        ]

        var matched: [(index: Int, kind: SectionKind, title: String)] = []
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.count < 120 else { continue }

            for (kind, keywords) in known {
                guard keywords.contains(where: { line.localizedCaseInsensitiveContains($0) }) else { continue }
                guard matched.last?.kind != kind else { break }
                matched.append((i, kind, line))
                break
            }
        }

        guard !matched.isEmpty else { return [] }

        var sections: [PaperSection] = []
        for (j, match) in matched.enumerated() {
            let nextIndex = j + 1 < matched.count ? matched[j + 1].index : lines.count
            let body = lines[(match.index + 1)..<nextIndex]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(PaperSection(kind: match.kind, title: match.title, text: body, order: j))
        }
        return sections
    }

    private static func firstSection(named name: String, in text: String) -> String? {
        guard let range = text.range(of: name, options: [.caseInsensitive]) else { return nil }
        let remainder = text[range.lowerBound...]
        return String(remainder.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentenceCandidates(from text: String) -> [String] {
        clean(text)
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 45 && $0.count < 320 }
            .map { "\($0)." }
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
