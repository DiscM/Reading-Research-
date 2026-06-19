import Foundation
import CoreML

#if canImport(FoundationModels)
import FoundationModels
#endif

enum LocalPaperAI {
    private enum Provider: String {
        case appleFoundationModels = "Apple Foundation Models"
        case coreML = "Core ML"
        case localHeuristic = "Local Heuristic"
        case mlx = "MLX"
        case openAICompatibleBYOK = "OpenAI-compatible BYOK"

        static var current: Provider {
            let stored = UserDefaults.standard.string(forKey: "aiProvider")
            return stored.flatMap(Provider.init(rawValue:)) ?? .appleFoundationModels
        }
    }

    static var statusText: String {
        switch Provider.current {
        case .appleFoundationModels:
            return foundationModelsStatusText
        case .coreML:
            return coreMLStatusText
        case .localHeuristic:
            return "Local heuristic mode - private fallback with no model accelerator."
        case .mlx:
            return "MLX provider is reserved for a future local model package. Falling back to the local heuristic."
        case .openAICompatibleBYOK:
            return "BYOK provider is reserved for explicit cloud routing. Falling back locally while cloud routing is unavailable."
        }
    }

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

    static func explainSelection(_ text: String, in paper: Paper) async -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Select text in the PDF, then ask for an explanation."
        }

        let allText = paper.allText
        guard !allText.isEmpty else { return "No extractable text was found for context." }
        let surrounding = context(around: text, in: allText)

        switch Provider.current {
        case .appleFoundationModels:
            if let response = await foundationModelResponse(
                instructions: "Explain only the selected passage using the nearby context. Do not summarize the document or the surrounding context. Return clean Markdown with short paragraphs and bullets only when useful. Do not add a title. Keep the explanation concise and grounded in the supplied text.",
                prompt: """
                Explain the selected passage from this \(paper.documentKind.rawValue.lowercased()). Do not provide a document summary. Clarify the passage's meaning, important terms, and how it relates to the nearby context.

                Selected passage:
                \(text)

                Nearby document context:
                \(surrounding)
                """
            ) {
                return response
            }
        case .coreML:
            if let response = try? coreMLTextResponse(
                modelName: "PaperExplainer",
                prompt: "\(text)\n\nContext:\n\(surrounding)"
            ) {
                return response
            }
        case .localHeuristic, .mlx, .openAICompatibleBYOK:
            break
        }

        return heuristicExplanation(for: text, allText: allText, surrounding: surrounding)
    }

    static func summary(for paper: Paper) async -> String {
        let text = String(clean(paper.allText).prefix(15_000))
        guard !text.isEmpty else {
            return "No extractable text was found. This document may need OCR before AI features can summarize it."
        }

        switch Provider.current {
        case .appleFoundationModels:
            if let response = await foundationModelResponse(
                instructions: "You summarize study documents locally. Use only the provided text. Return clean Markdown with concise bullets, bold key terms when useful, and no top-level title.",
                prompt: """
                Summarize this \(paper.documentKind.rawValue.lowercased()). Include \(paper.documentKind.summaryFocus) when present.

                Title: \(paper.title)
                Creator or author: \(paper.authors)

                Document text:
                \(text)
                """
            ) {
                return response
            }
        case .coreML:
            if let response = try? coreMLTextResponse(modelName: "PaperSummarizer", prompt: text) {
                return response
            }
        case .localHeuristic, .mlx, .openAICompatibleBYOK:
            break
        }

        return heuristicSummary(for: paper, text: text)
    }

    static func extraction(for paper: Paper, kind: HighlightKind) async -> String {
        let text = String(clean(paper.allText).prefix(30_000))
        guard !text.isEmpty else {
            return "No extractable text was found for this document yet."
        }

        switch Provider.current {
        case .appleFoundationModels:
            if let response = await foundationModelResponse(
                instructions: "You extract useful passages from study documents using only supplied text. Return clean Markdown with no more than five bullets and no top-level title.",
                prompt: """
                Extract \(kind.rawValue.lowercased()) passages or claims from this \(paper.documentKind.rawValue.lowercased()). Quote or closely paraphrase only what appears in the text.

                Document text:
                \(text)
                """
            ) {
                return response
            }
        case .coreML:
            if let response = try? coreMLTextResponse(
                modelName: "PaperExtractor",
                prompt: "Extract \(kind.rawValue.lowercased()):\n\(text)"
            ) {
                return response
            }
        case .localHeuristic, .mlx, .openAICompatibleBYOK:
            break
        }

        return heuristicExtraction(from: text, kind: kind)
    }

    private static func heuristicExplanation(for text: String, allText: String, surrounding: String) -> String {
        let sentences = sentenceCandidates(from: surrounding).filter { $0.localizedCaseInsensitiveContains(text.prefix(40)) }
        var lines: [String] = ["**Nearby context**\n"]
        if sentences.isEmpty {
            let excerpt = surrounding.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("> \(excerpt)")
        } else {
            for s in sentences {
                lines.append("> \(s)")
            }
        }

        lines.append("")
        lines.append("*This is a local heuristic context extraction. A configured language model can provide a richer explanation.*")

        return lines.joined(separator: "\n")
    }

    private static func heuristicSummary(for paper: Paper, text: String) -> String {
        let abstract = abstractCandidate(from: text)
        let sentences = sentenceCandidates(from: abstract.isEmpty ? text : abstract)
        let topSentences = sentences.prefix(4)

        var lines = ["**On-device summary**"]
        for sentence in topSentences {
            lines.append("- \(sentence)")
        }

        if let methodHint = firstSection(named: "method", in: text) {
            lines.append("- Method signal: \(String(methodHint.prefix(260)))")
        }

        lines.append("")
        lines.append("*Generated from on-device \(paper.documentKind.rawValue.lowercased()) text extraction.*")
        return lines.joined(separator: "\n")
    }

    private static func heuristicExtraction(from text: String, kind: HighlightKind) -> String {
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

    private static func context(around text: String, in allText: String) -> String {
        guard let range = allText.range(of: text, options: .caseInsensitive) else {
            return String(clean(allText).prefix(1_200))
        }
        let startOffset = max(0, allText.distance(from: allText.startIndex, to: range.lowerBound) - 700)
        let endOffset = min(allText.count, allText.distance(from: allText.startIndex, to: range.upperBound) + 700)
        let start = allText.index(allText.startIndex, offsetBy: startOffset)
        let end = allText.index(allText.startIndex, offsetBy: endOffset)
        return String(allText[start..<end])
    }

    private static var foundationModelsStatusText: String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Foundation Models - on-device Apple Intelligence model available."
            case .unavailable(let reason):
                return "Apple Foundation Models unavailable (\(String(describing: reason))). Falling back locally."
            }
        }
        #endif

        return "Apple Foundation Models require macOS 26+. Falling back locally."
    }

    private static var coreMLStatusText: String {
        let hasModel = ["PaperSummarizer", "PaperExtractor", "PaperExplainer"].contains { coreMLModelURL(named: $0) != nil }

        if hasModel {
            return "Core ML local mode - configured for all Apple compute units, including Neural Engine when the model supports it."
        }

        return "Core ML local mode - no compiled text model found yet; falling back to the local heuristic."
    }

    private static func foundationModelResponse(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }

            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return """
                \(response.content)

                ---

                *Generated locally with Apple Foundation Models.*
                """
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    private static func coreMLTextResponse(modelName: String, prompt: String) throws -> String? {
        guard let modelURL = coreMLModelURL(named: modelName) else { return nil }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let description = model.modelDescription

        guard let inputName = description.inputDescriptionsByName.first(where: { $0.value.type == .string })?.key,
              let outputName = description.outputDescriptionsByName.first(where: { $0.value.type == .string })?.key else {
            return nil
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(string: prompt)
        ])
        let output = try model.prediction(from: input)

        guard let text = output.featureValue(for: outputName)?.stringValue,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return """
        \(text)

        ---

        *Generated locally with Core ML using all available Apple compute units.*
        """
    }

    private static func coreMLModelURL(named modelName: String) -> URL? {
        if let bundled = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            return bundled
        }

        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let modelsDirectory = support
            .appendingPathComponent("ResearchPaperReader", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        return modelsDirectory.appendingPathComponent("\(modelName).mlmodelc", isDirectory: true)
            .existingDirectory
    }

    private static let numberedRegex = try! NSRegularExpression(pattern: #"^(?:\d+(?:\.\d+)*|[A-Z]|[IVX]+)\.?\s+"#)

    static func sections(from text: String, pageOffsets: [Int] = []) -> [PaperSection] {
        let lines = text.components(separatedBy: "\n")
        var lineOffsets: [Int] = []
        var running = 0
        for line in lines {
            lineOffsets.append(running)
            running += line.count + 1
        }

        let known: [(SectionKind, [String])] = [
            (.abstract,     ["abstract"]),
            (.introduction, ["introduction"]),
            (.relatedWork,  ["related work", "related literature", "background"]),
            (.method,       ["method", "approach", "model", "algorithm", "architecture", "framework", "system design", "proposed method", "methodology"]),
            (.experiment,   ["experiment", "evaluation", "dataset", "empirical", "setup", "experimental setup"]),
            (.results,      ["results", "findings", "outcome"]),
            (.discussion,   ["discussion"]),
            (.conclusion,   ["conclusion", "future work", "summary", "concluding remarks"]),
            (.references,   ["references", "bibliography"]),
            (.appendix,     ["appendix"]),
        ]

        var matched: [(index: Int, kind: SectionKind, title: String)] = []

        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.count < 120 else { continue }

            let nsLine = line as NSString
            let nsr = NSRange(location: 0, length: nsLine.length)
            let hasNumber = numberedRegex.firstMatch(in: line, options: [.anchored], range: nsr) != nil
            let stripped = hasNumber ? numberedRegex.stringByReplacingMatches(in: line, options: [], range: nsr, withTemplate: "") : line

            for (kind, keywords) in known {
                let checkLine = hasNumber ? stripped : line
                guard keywords.contains(where: { checkLine.localizedCaseInsensitiveContains($0) }) else { continue }
                guard !matched.contains(where: { $0.kind == kind }) else { break }
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

            let page: Int? = {
                guard match.index < lineOffsets.count else { return nil }
                let charOffset = lineOffsets[match.index]
                for p in (0..<pageOffsets.count).reversed() {
                    if pageOffsets[p] <= charOffset { return p + 1 }
                }
                return nil
            }()

            sections.append(PaperSection(kind: match.kind, title: match.title, text: body, order: j, page: page))
        }
        return sections
    }

    private static func firstSection(named name: String, in text: String) -> String? {
        guard let range = text.range(of: name, options: [.caseInsensitive]) else { return nil }
        let remainder = text[range.lowerBound...]
        return String(remainder.prefix(700)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sentenceCandidates(from text: String) -> [String] {
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

private extension URL {
    var existingDirectory: URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return self
    }
}
