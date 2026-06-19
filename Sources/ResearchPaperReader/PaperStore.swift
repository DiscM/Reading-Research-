import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PaperStore: ObservableObject {
    @Published var papers: [Paper] = [] {
        didSet {
            guard !isLoading else { return }
            scheduleSave()
        }
    }

    @Published var lastError: String?
    @Published var isImporting = false
    @Published var enrichmentCount = 0

    private let fileManager = FileManager.default
    private let appDirectory: URL
    private let papersDirectory: URL
    private let imagesDirectory: URL
    private let databaseURL: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDirectory = base.appendingPathComponent("ResearchPaperReader", isDirectory: true)
        papersDirectory = appDirectory.appendingPathComponent("Papers", isDirectory: true)
        imagesDirectory = appDirectory.appendingPathComponent("Images", isDirectory: true)
        databaseURL = appDirectory.appendingPathComponent("library.json")

        try? fileManager.createDirectory(at: papersDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    func importWithOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.importDocuments(panel.urls)
            }
        }
    }

    func importDocuments(_ urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        enrichmentCount = 0

        var reservedPaths = Set<String>()
        let jobs = urls.map { sourceURL in
            let destinationURL = uniqueDestinationURL(for: sourceURL, reserving: reservedPaths)
            reservedPaths.insert(destinationURL.path)
            return (sourceURL, destinationURL)
        }

        importTask = Task { [weak self] in
            guard let self else { return }

            for (sourceURL, destinationURL) in jobs {
                guard !Task.isCancelled else { break }

                do {
                    var paper = try await Task.detached(priority: .userInitiated) {
                        try Self.prepareDocument(sourceURL: sourceURL, destinationURL: destinationURL)
                    }.value

                    if paper.documentKind == .researchPaper {
                        paper = await MetadataService.enrich(paper)
                    }

                    papers.insert(paper, at: 0)
                    enrichmentCount += 1
                    flushSave()
                } catch {
                    try? fileManager.removeItem(at: destinationURL)
                    lastError = "Could not import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
                }
            }

            isImporting = false
            importTask = nil
        }
    }

    // Kept for source compatibility with existing drag-and-drop call sites.
    func importPDFs(_ urls: [URL]) {
        importDocuments(urls)
    }

    func delete(_ paper: Paper) {
        papers.removeAll { $0.id == paper.id }
        try? fileManager.removeItem(at: paper.fileURL)
        flushSave()
    }

    func reEnrich(_ paper: Paper) async {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let enriched = await MetadataService.enrich(papers[index])
        guard let updatedIndex = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        objectWillChange.send()
        papers[updatedIndex] = enriched
        scheduleSave()
    }

    func generateSummary(for paper: Paper) async {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let summary = await LocalPaperAI.summary(for: papers[index])
        guard let updatedIndex = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        papers[updatedIndex].aiSummary = summary
    }

    func generateExtraction(for paper: Paper, kind: HighlightKind) async -> String {
        await LocalPaperAI.extraction(for: paper, kind: kind)
    }

    func addNote(
        to paper: Paper,
        kind: HighlightKind,
        quote: String,
        body: String,
        page: Int?,
        isAreaNote: Bool = false,
        rectX: Double? = nil,
        rectY: Double? = nil,
        rectWidth: Double? = nil,
        rectHeight: Double? = nil,
        imageFileName: String? = nil
    ) {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let note = PaperNote(
            kind: kind,
            quote: quote,
            body: body,
            page: page,
            isAreaNote: isAreaNote,
            rectX: rectX,
            rectY: rectY,
            rectWidth: rectWidth,
            rectHeight: rectHeight,
            imageFileName: imageFileName
        )
        papers[index].notes.insert(note, at: 0)
    }

    func deleteNote(_ note: PaperNote, from paper: Paper) {
        guard let paperIndex = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        papers[paperIndex].notes.removeAll { $0.id == note.id }
        
        if let imageFileName = note.imageFileName {
            let fileURL = imagesDirectory.appendingPathComponent(imageFileName)
            try? fileManager.removeItem(at: fileURL)
        }
        flushSave()
    }

    func imageUrl(for fileName: String) -> URL {
        imagesDirectory.appendingPathComponent(fileName)
    }

    func saveAreaNoteImage(from page: PDFPage, rect: CGRect) -> String? {
        let imageSize = rect.size
        let scale: CGFloat = 2.0
        let targetSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        
        let image = NSImage(size: targetSize)
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        // Fill white background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.origin.x, y: -rect.origin.y)
        
        page.draw(with: .mediaBox, to: context)
        image.unlockFocus()
        
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let fileUUID = UUID()
        let fileName = "\(fileUUID.uuidString).png"
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL)
            return fileName
        } catch {
            lastError = "Could not save cropped area image: \(error.localizedDescription)"
            return nil
        }
    }

    func exportMarkdown(for paper: Paper) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(paper.title.sanitizedFileName)-notes.md"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try self?.markdown(for: paper).write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    self?.lastError = "Could not export notes: \(error.localizedDescription)"
                }
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                save()
            } catch {
                return
            }
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        save()
    }

    func save() {
        do {
            let data = try JSONEncoder.researchPaperReader.encode(papers)
            try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            try data.write(to: databaseURL, options: [.atomic])
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }

        do {
            isLoading = true
            let data = try Data(contentsOf: databaseURL)
            papers = try JSONDecoder.researchPaperReader.decode([Paper].self, from: data)
            isLoading = false
        } catch {
            isLoading = false
            lastError = "The library could not be loaded. Its data was preserved at \(databaseURL.path). \(error.localizedDescription)"
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, reserving reservedPaths: Set<String> = []) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        var candidate = papersDirectory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) || reservedPaths.contains(candidate.path) {
            candidate = papersDirectory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    private nonisolated static func prepareDocument(sourceURL: URL, destinationURL: URL) throws -> Paper {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let metadata = extractMetadata(from: destinationURL)
        let extracted = extractAllText(from: destinationURL)
        let documentKind = inferDocumentKind(
            filename: sourceURL.deletingPathExtension().lastPathComponent,
            text: extracted.text,
            doi: metadata.doi,
            arxivId: metadata.arxivId
        )
        let sections = documentKind == .researchPaper
            ? LocalPaperAI.sections(from: extracted.text, pageOffsets: extracted.offsets)
            : []
        let fallbackTitle = sourceURL.deletingPathExtension().lastPathComponent.readableDocumentTitle

        return Paper(
            documentKind: documentKind,
            title: metadata.title.isEmpty ? fallbackTitle : metadata.title,
            authors: metadata.authors,
            year: metadata.year,
            abstract: documentKind == .researchPaper ? metadata.abstract : "",
            filePath: destinationURL.path,
            sections: sections,
            allText: extracted.text,
            allTextPageOffsets: extracted.offsets,
            doi: metadata.doi,
            arxivId: metadata.arxivId,
            publicationNumber: metadata.publicationNumber,
            venue: metadata.venue
        )
    }

    private nonisolated static func extractAllText(from url: URL) -> (text: String, offsets: [Int]) {
        guard let document = PDFDocument(url: url) else { return ("", []) }
        var parts: [String] = []
        var offsets: [Int] = []
        var offset = 0
        for i in 0..<document.pageCount {
            offsets.append(offset)
            if let text = document.page(at: i)?.string {
                offset += text.count + 1
                parts.append(text)
            } else {
                offset += 1
                parts.append("")
            }
        }
        return (parts.joined(separator: "\n"), offsets)
    }

    private nonisolated static func extractMetadata(from url: URL) -> (title: String, authors: String, year: String, abstract: String, doi: String, arxivId: String, venue: String, publicationNumber: String) {
        let document = PDFDocument(url: url)
        let attributes = document?.documentAttributes ?? [:]
        let rawTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawAuthor = (attributes[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstPage = document?.page(at: 0)?.string ?? ""
        let abstract = LocalPaperAI.abstractCandidate(from: firstPage)
        let doi = MetadataService.extractDOI(from: firstPage) ?? ""
        let arxivId = MetadataService.extractArxivID(from: firstPage)
            ?? MetadataService.extractArxivID(from: rawTitle)
            ?? ""

        let titleIsID = rawTitle.hasAuthorSwapPattern
        let publicationNumber: String
        let title: String
        let author: String

        if titleIsID {
            publicationNumber = arxivId.isEmpty ? rawTitle : arxivId
            title = ""
            author = ""
        } else {
            publicationNumber = arxivId.isEmpty ? doi : arxivId
            title = rawTitle.isEmpty ? "" : rawTitle
            author = rawAuthor.isEmpty ? "" : rawAuthor
        }

        return (title, author, "", abstract, doi, arxivId, "", publicationNumber)
    }

    private nonisolated static func inferDocumentKind(filename: String, text: String, doi: String, arxivId: String) -> DocumentKind {
        let name = filename.lowercased()
        let sample = String(text.prefix(20_000)).lowercased()

        if !doi.isEmpty || !arxivId.isEmpty {
            return .researchPaper
        }

        if name.range(of: #"(?:lecture|slides?|slide[-_ ]?deck|week[-_ ]?\d+)"#, options: .regularExpression) != nil
            || sample.contains("learning objectives")
            || sample.contains("lecture slides") {
            return .lectureSlides
        }

        if name.range(of: #"(?:notes?|study[-_ ]?guide|handout|cheat[-_ ]?sheet|worksheet)"#, options: .regularExpression) != nil
            || sample.contains("study guide")
            || sample.contains("class notes")
            || sample.contains("course notes") {
            return .studyNotes
        }

        if name.range(of: #"(?:chapter|textbook|book)"#, options: .regularExpression) != nil
            || sample.range(of: #"\bchapter\s+\d+\b"#, options: .regularExpression) != nil {
            return .bookChapter
        }

        let researchSignals = [
            sample.contains("abstract"),
            sample.contains("introduction"),
            sample.contains("references"),
            sample.contains("methodology") || sample.contains("experimental results"),
        ].filter { $0 }.count

        return researchSignals >= 2 ? .researchPaper : .generalPDF
    }

    private func markdown(for paper: Paper) -> String {
        var lines: [String] = [
            "# \(paper.title)",
            "",
            "- Type: \(paper.documentKind.rawValue)",
            "- Status: \(paper.status.rawValue)",
            ""
        ]

        if !paper.authors.isEmpty { lines.insert("- Authors: \(paper.authors)", at: 3) }
        if !paper.year.isEmpty { lines.insert("- Year: \(paper.year)", at: paper.authors.isEmpty ? 3 : 4) }

        if !paper.abstract.isEmpty {
            lines.append("## Abstract")
            lines.append("")
            lines.append(paper.abstract)
            lines.append("")
        }

        if let aiSummary = paper.aiSummary {
            lines.append("## AI Summary")
            lines.append("")
            lines.append(aiSummary)
            lines.append("")
        }

        lines.append("## Notes")
        lines.append("")

        if paper.notes.isEmpty {
            lines.append("_No notes yet._")
        } else {
            for note in paper.notes {
                lines.append("### \(note.kind.rawValue)")
                if let page = note.page {
                    lines.append("")
                    lines.append("Page: \(page)")
                }
                if !note.quote.isEmpty {
                    lines.append("")
                    lines.append("> \(note.quote)")
                }
                lines.append("")
                lines.append(note.body)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private extension String {
    var sanitizedFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = components(separatedBy: invalid).joined(separator: "-")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "paper" : cleaned
    }
}

private extension String {
    var readableDocumentTitle: String {
        replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
    }
}

private extension JSONEncoder {
    static var researchPaperReader: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var researchPaperReader: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
