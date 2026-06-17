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

struct Paper: Identifiable, Codable, Equatable, Sendable {
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

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}
