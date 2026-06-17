import AppKit
import Foundation

enum ReadingStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case unread = "Unread"
    case skimmed = "Skimmed"
    case reading = "Reading"
    case read = "Read"
    case cited = "Cited"
    case rejected = "Rejected"
    case archived = "Archived"

    var id: String { rawValue }
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
}

struct Paper: Identifiable, Equatable, Sendable {
    var id = UUID()
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

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}

extension Paper: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, authors, year, abstract, filePath, importedAt, status
        case tags, sections, notes, aiSummary, allText, allTextPageOffsets
        case doi, arxivId, publicationNumber, venue, enrichmentFailed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
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
    }
}

extension Array where Element == Paper {
    func filtered(searchText: String, debouncedSearch: String, status: ReadingStatus?) -> [Paper] {
        var result = self
        if let status {
            result = result.filter { $0.status == status }
        }
        let s = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            result = result.filter { p in
                p.title.localizedCaseInsensitiveContains(s)
                || p.authors.localizedCaseInsensitiveContains(s)
                || p.tags.joined(separator: " ").localizedCaseInsensitiveContains(s)
                || p.notes.contains { $0.body.localizedCaseInsensitiveContains(s) || $0.quote.localizedCaseInsensitiveContains(s) }
                || p.allText.localizedCaseInsensitiveContains(debouncedSearch)
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
