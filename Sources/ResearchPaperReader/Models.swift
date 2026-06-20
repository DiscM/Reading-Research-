import AppKit
import Foundation
import SwiftUI

enum DocumentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case researchPaper = "Research Paper"
    case lectureSlides = "Lecture Slides"
    case studyNotes = "Study Notes"
    case bookChapter = "Book or Chapter"
    case generalPDF = "General PDF"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .researchPaper: "doc.text.magnifyingglass"
        case .lectureSlides: "rectangle.on.rectangle.angled"
        case .studyNotes: "note.text"
        case .bookChapter: "book.closed"
        case .generalPDF: "doc.richtext"
        }
    }

    var summaryFocus: String {
        switch self {
        case .researchPaper:
            "the central contribution, method, evidence, and limitations"
        case .lectureSlides:
            "the learning objectives, key concepts, definitions, examples, and takeaways"
        case .studyNotes:
            "the main topics, definitions, formulas, open questions, and study priorities"
        case .bookChapter:
            "the thesis, major arguments, concepts, supporting evidence, and conclusions"
        case .generalPDF:
            "the document's purpose, main ideas, important facts, and action items"
        }
    }
}

enum ReadingStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case unread = "Unread"
    case skimmed = "Skimmed"
    case reading = "Reading"
    case read = "Read"
    case cited = "Cited"
    case rejected = "Rejected"
    case archived = "Archived"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .unread:    .gray
        case .skimmed:   .blue
        case .reading:   .green
        case .read:      .indigo
        case .cited:     .purple
        case .rejected:  .red
        case .archived:  .secondary
        }
    }
}

enum HighlightKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case highlight = "Highlight"
    case claim = "Claim"
    case evidence = "Evidence"
    case method = "Method"
    case limitation = "Limitation"
    case question = "Question"
    case definition = "Definition"

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .highlight:   .systemYellow
        case .claim:       .systemOrange
        case .evidence:    .systemGreen
        case .method:      .systemBlue
        case .limitation:  .systemRed
        case .question:    .systemPurple
        case .definition:  .systemGray
        }
    }
}

struct PaperSection: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: SectionKind
    var title: String
    var text: String
    var order: Int
    var page: Int?
}

enum SectionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case abstract = "Abstract"
    case introduction = "Introduction"
    case relatedWork = "Related Work"
    case background = "Background"
    case method = "Method"
    case experiment = "Experiments"
    case results = "Results"
    case discussion = "Discussion"
    case conclusion = "Conclusion"
    case references = "References"
    case appendix = "Appendix"
    case other = "Other"

    var id: String { rawValue }
}

struct PaperNote: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: HighlightKind
    var quote: String
    var body: String
    var page: Int?
    var createdAt = Date()
    
    var isAreaNote: Bool = false
    var rectX: Double? = nil
    var rectY: Double? = nil
    var rectWidth: Double? = nil
    var rectHeight: Double? = nil
    var imageFileName: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, quote, body, page, createdAt
        case isAreaNote, rectX, rectY, rectWidth, rectHeight, imageFileName
    }

    init(
        id: UUID = UUID(),
        kind: HighlightKind,
        quote: String,
        body: String,
        page: Int?,
        createdAt: Date = Date(),
        isAreaNote: Bool = false,
        rectX: Double? = nil,
        rectY: Double? = nil,
        rectWidth: Double? = nil,
        rectHeight: Double? = nil,
        imageFileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.quote = quote
        self.body = body
        self.page = page
        self.createdAt = createdAt
        self.isAreaNote = isAreaNote
        self.rectX = rectX
        self.rectY = rectY
        self.rectWidth = rectWidth
        self.rectHeight = rectHeight
        self.imageFileName = imageFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(HighlightKind.self, forKey: .kind) ?? .highlight
        quote = try container.decodeIfPresent(String.self, forKey: .quote) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        page = try container.decodeIfPresent(Int.self, forKey: .page)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isAreaNote = try container.decodeIfPresent(Bool.self, forKey: .isAreaNote) ?? false
        rectX = try container.decodeIfPresent(Double.self, forKey: .rectX)
        rectY = try container.decodeIfPresent(Double.self, forKey: .rectY)
        rectWidth = try container.decodeIfPresent(Double.self, forKey: .rectWidth)
        rectHeight = try container.decodeIfPresent(Double.self, forKey: .rectHeight)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
    }
}

struct Paper: Identifiable, Equatable, Sendable {
    var id = UUID()
    var documentKind: DocumentKind = .researchPaper
    var title: String
    var authors: String
    var year: String
    var abstract: String
    var filePath: String
    var importedAt = Date()
    var status: ReadingStatus = .unread
    var tags: [String] = []
    var sections: [PaperSection] = []
    var notes: [PaperNote] = []
    var aiSummary: String?
    var allText: String = ""
    var allTextPageOffsets: [Int] = []
    var doi: String = ""
    var arxivId: String = ""
    var publicationNumber: String = ""
    var venue: String = ""
    var enrichmentFailed: Bool = false
    var lastReadPage: Int?
    var lastReadAt: Date?

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var pageCount: Int {
        allTextPageOffsets.count
    }

    var canResumeReading: Bool {
        guard let lastReadPage else { return false }
        return lastReadPage > 1
    }

    var readingProgress: Double? {
        guard let lastReadPage, pageCount > 0 else { return nil }
        return min(1, max(0, Double(lastReadPage) / Double(pageCount)))
    }

    mutating func recordReadingProgress(page: Int, at date: Date = Date()) {
        guard page > 0 else { return }
        lastReadPage = page
        lastReadAt = date

        if page > 1, status == .unread || status == .skimmed {
            status = .reading
        }
    }
}

extension Paper: Codable {
    enum CodingKeys: String, CodingKey {
        case id, documentKind, title, authors, year, abstract, filePath, importedAt, status
        case tags, sections, notes, aiSummary, allText, allTextPageOffsets
        case doi, arxivId, publicationNumber, venue, enrichmentFailed, lastReadPage, lastReadAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        documentKind = try c.decodeIfPresent(DocumentKind.self, forKey: .documentKind) ?? .researchPaper
        title = try c.decode(String.self, forKey: .title)
        authors = try c.decode(String.self, forKey: .authors)
        year = try c.decodeIfPresent(String.self, forKey: .year) ?? ""
        abstract = try c.decodeIfPresent(String.self, forKey: .abstract) ?? ""
        filePath = try c.decode(String.self, forKey: .filePath)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        status = try c.decodeIfPresent(ReadingStatus.self, forKey: .status) ?? .unread
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        sections = try c.decodeIfPresent([PaperSection].self, forKey: .sections) ?? []
        notes = try c.decodeIfPresent([PaperNote].self, forKey: .notes) ?? []
        aiSummary = try c.decodeIfPresent(String.self, forKey: .aiSummary)
        allText = try c.decodeIfPresent(String.self, forKey: .allText) ?? ""
        allTextPageOffsets = try c.decodeIfPresent([Int].self, forKey: .allTextPageOffsets) ?? []
        doi = try c.decodeIfPresent(String.self, forKey: .doi) ?? ""
        arxivId = try c.decodeIfPresent(String.self, forKey: .arxivId) ?? ""
        publicationNumber = try c.decodeIfPresent(String.self, forKey: .publicationNumber) ?? ""
        venue = try c.decodeIfPresent(String.self, forKey: .venue) ?? ""
        enrichmentFailed = try c.decodeIfPresent(Bool.self, forKey: .enrichmentFailed) ?? false
        lastReadPage = try c.decodeIfPresent(Int.self, forKey: .lastReadPage)
        lastReadAt = try c.decodeIfPresent(Date.self, forKey: .lastReadAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(documentKind, forKey: .documentKind)
        try c.encode(title, forKey: .title)
        try c.encode(authors, forKey: .authors)
        try c.encode(year, forKey: .year)
        try c.encode(abstract, forKey: .abstract)
        try c.encode(filePath, forKey: .filePath)
        try c.encode(importedAt, forKey: .importedAt)
        try c.encode(status, forKey: .status)
        try c.encode(tags, forKey: .tags)
        try c.encode(sections, forKey: .sections)
        try c.encode(notes, forKey: .notes)
        try c.encodeIfPresent(aiSummary, forKey: .aiSummary)
        try c.encode(allText, forKey: .allText)
        try c.encode(allTextPageOffsets, forKey: .allTextPageOffsets)
        try c.encode(doi, forKey: .doi)
        try c.encode(arxivId, forKey: .arxivId)
        try c.encode(publicationNumber, forKey: .publicationNumber)
        try c.encode(venue, forKey: .venue)
        try c.encode(enrichmentFailed, forKey: .enrichmentFailed)
        try c.encodeIfPresent(lastReadPage, forKey: .lastReadPage)
        try c.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
    }
}

extension Array where Element == Paper {
    func filtered(searchText: String, debouncedSearch: String, status: ReadingStatus?) -> [Paper] {
        var result = self
        if let status {
            result = result.filter { $0.status == status }
        }
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullTextQuery = debouncedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            result = result.filter { p in
                p.title.localizedCaseInsensitiveContains(s)
                || p.authors.localizedCaseInsensitiveContains(s)
                || p.documentKind.rawValue.localizedCaseInsensitiveContains(s)
                || p.tags.joined(separator: " ").localizedCaseInsensitiveContains(s)
                || p.notes.contains { $0.body.localizedCaseInsensitiveContains(s) || $0.quote.localizedCaseInsensitiveContains(s) }
                || (!fullTextQuery.isEmpty && p.allText.localizedCaseInsensitiveContains(fullTextQuery))
            }
        }
        return result
    }

    func sorted(by order: SortOrder) -> [Paper] {
        switch order {
        case .recent: return sorted { $0.importedAt > $1.importedAt }
        case .title:  return sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author: return sorted { $0.authors.localizedCaseInsensitiveCompare($1.authors) == .orderedAscending }
        case .year:   return sorted { $0.year > $1.year }
        }
    }
}
