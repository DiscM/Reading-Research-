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

    private let fileManager = FileManager.default
    private let appDirectory: URL
    private let papersDirectory: URL
    private let databaseURL: URL
    private var isLoading = false
    private var saveTask: Task<Void, Never>?

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        appDirectory = base.appendingPathComponent("ResearchPaperReader", isDirectory: true)
        papersDirectory = appDirectory.appendingPathComponent("Papers", isDirectory: true)
        databaseURL = appDirectory.appendingPathComponent("library.json")

        do {
            try fileManager.createDirectory(at: papersDirectory, withIntermediateDirectories: true)
            load()
        } catch {
            lastError = error.localizedDescription
        }
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
                self?.importPDFs(panel.urls)
            }
        }
    }

    func importPDFs(_ urls: [URL]) {
        for sourceURL in urls {
            do {
                let destinationURL = uniqueDestinationURL(for: sourceURL)
                try fileManager.copyItem(at: sourceURL, to: destinationURL)

                let metadata = extractMetadata(from: destinationURL)
                let allText = extractAllText(from: destinationURL)
                let sections = LocalPaperAI.sections(from: allText)
                let paper = Paper(
                    title: metadata.title,
                    authors: metadata.authors,
                    year: metadata.year,
                    abstract: metadata.abstract,
                    filePath: destinationURL.path,
                    sections: sections,
                    allText: allText
                )
                papers.insert(paper, at: 0)
            } catch {
                lastError = "Could not import \(sourceURL.lastPathComponent): \(error.localizedDescription)"
            }
        }
        flushSave()
    }

    func delete(_ paper: Paper) {
        papers.removeAll { $0.id == paper.id }
        try? fileManager.removeItem(at: paper.fileURL)
        flushSave()
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

    func addNote(to paper: Paper, kind: HighlightKind, quote: String, body: String, page: Int?) {
        guard let index = papers.firstIndex(where: { $0.id == paper.id }) else { return }
        let note = PaperNote(kind: kind, quote: quote, body: body, page: page)
        papers[index].notes.insert(note, at: 0)
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
            lastError = error.localizedDescription
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        var candidate = papersDirectory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = papersDirectory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    private func extractAllText(from url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var parts: [String] = []
        for i in 0..<document.pageCount {
            parts.append(document.page(at: i)?.string ?? "")
        }
        return parts.joined(separator: "\n")
    }

    private func extractMetadata(from url: URL) -> (title: String, authors: String, year: String, abstract: String) {
        let document = PDFDocument(url: url)
        let attributes = document?.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent

        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String) ?? "Unknown authors"
        let text = document?.page(at: 0)?.string ?? ""
        let abstract = LocalPaperAI.abstractCandidate(from: text)

        return (title, author, "", abstract)
    }

    private func markdown(for paper: Paper) -> String {
        var lines: [String] = [
            "# \(paper.title)",
            "",
            "- Authors: \(paper.authors)",
            "- Year: \(paper.year.isEmpty ? "Unknown" : paper.year)",
            "- Status: \(paper.status.rawValue)",
            ""
        ]

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

private extension JSONEncoder {
    static var researchPaperReader: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
