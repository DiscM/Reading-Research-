import Foundation

struct PaperCollection: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var parentID: UUID?
    var paperIDs: Set<UUID> = []
    var createdAt = Date()
}

enum SmartFolderField: String, CaseIterable, Codable, Identifiable, Sendable {
    case allText = "Title, author, text, or note"
    case tag = "Tag"
    case author = "Author"
    case venue = "Venue"
    case year = "Year"
    case documentKind = "Document type"
    case status = "Reading status"

    var id: String { rawValue }
}

struct SmartFolderRule: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var field: SmartFolderField
    var value: String

    func matches(_ paper: Paper) -> Bool {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        switch field {
        case .allText:
            return [paper.title, paper.authors, paper.abstract, paper.allText,
                    paper.tags.joined(separator: " "),
                    paper.notes.map { "\($0.quote) \($0.body)" }.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        case .tag:
            return paper.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        case .author:
            return paper.authors.localizedCaseInsensitiveContains(query)
        case .venue:
            return paper.venue.localizedCaseInsensitiveContains(query)
        case .year:
            return paper.year.localizedCaseInsensitiveContains(query)
        case .documentKind:
            return paper.documentKind.rawValue.localizedCaseInsensitiveContains(query)
        case .status:
            return paper.status.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
}

struct SmartFolder: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var matchAll = true
    var rules: [SmartFolderRule] = []
    var createdAt = Date()

    func matches(_ paper: Paper) -> Bool {
        guard !rules.isEmpty else { return true }
        return matchAll
            ? rules.allSatisfy { $0.matches(paper) }
            : rules.contains { $0.matches(paper) }
    }
}

enum CitationImportSource: String, Codable, Sendable {
    case bibtex = "BibTeX"
    case ris = "RIS"
    case manual = "Manual"
    case extractedReference = "Extracted reference"
    case crossref = "CrossRef"
}

struct CitationRecord: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var authors: String = ""
    var year: String = ""
    var venue: String = ""
    var doi: String = ""
    var arxivID: String = ""
    var abstract: String = ""
    var citationKey: String = ""
    var source: CitationImportSource = .manual
    var addedAt = Date()

    var fingerprint: String {
        let normalizedTitle = title.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
        let ndoi = doi.normalizedDOI
        return ndoi.isEmpty ? "\(normalizedTitle)|\(year)" : "doi:\(ndoi)"
    }
}

struct CitationImportReport: Equatable, Sendable {
    var imported: Int
    var merged: Int
}

struct EvidenceColumn: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
}

struct EvidenceCell: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var columnID: UUID
    var value: String = ""
    var quote: String = ""
    var page: Int?
    var isVerified = false
}

struct EvidenceRow: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var paperID: UUID
    var cells: [EvidenceCell] = []
}

struct EvidenceTable: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var columns: [EvidenceColumn] = []
    var rows: [EvidenceRow] = []
    var updatedAt = Date()
}

struct SynthesisWorkspace: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var paperIDs: Set<UUID> = []
    var evidenceTableID: UUID?
    var outline: String = ""
    var draft: String = ""
    var updatedAt = Date()
}

struct SemanticSearchResult: Identifiable, Equatable, Sendable {
    var id: String { "\(paperID.uuidString)-\(page ?? 0)-\(text.hashValue)" }
    var paperID: UUID
    var paperTitle: String
    var page: Int?
    var text: String
    var score: Double
}

struct DiscoveryPaper: Identifiable, Codable, Equatable, Sendable {
    var id: String { doi.isEmpty ? "\(title)|\(year)" : doi.lowercased() }
    var title: String
    var authors: String = ""
    var year: String = ""
    var venue: String = ""
    var doi: String = ""
    var abstract: String = ""
    var citedByCount: Int = 0
}

enum ResearchAlertKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case query = "Topic query"
    case author = "Author"
    case citations = "New works citing DOI"

    var id: String { rawValue }
}

struct ResearchAlert: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var kind: ResearchAlertKind
    var query: String
    var isEnabled = true
    var lastChecked: Date?
    var matches: [DiscoveryPaper] = []
}

struct CitationEdge: Identifiable, Equatable, Sendable {
    var id: String { "\(sourcePaperID.uuidString)|\(targetFingerprint)" }
    var sourcePaperID: UUID
    var targetFingerprint: String
    var targetTitle: String
    var targetAuthors: String
    var targetYear: String
    var targetVenue: String
    var targetDOI: String
    var targetPaperID: UUID?
}

struct ResearchState: Codable, Equatable, Sendable {
    var collections: [PaperCollection] = []
    var smartFolders: [SmartFolder] = []
    var citations: [CitationRecord] = []
    var evidenceTables: [EvidenceTable] = []
    var workspaces: [SynthesisWorkspace] = []
    var alerts: [ResearchAlert] = []
    var discoveryFeedback: [String: Bool] = [:]

    enum CodingKeys: String, CodingKey {
        case collections, smartFolders, citations, evidenceTables, workspaces, alerts, discoveryFeedback
    }

    init(
        collections: [PaperCollection] = [],
        smartFolders: [SmartFolder] = [],
        citations: [CitationRecord] = [],
        evidenceTables: [EvidenceTable] = [],
        workspaces: [SynthesisWorkspace] = [],
        alerts: [ResearchAlert] = [],
        discoveryFeedback: [String: Bool] = [:]
    ) {
        self.collections = collections
        self.smartFolders = smartFolders
        self.citations = citations
        self.evidenceTables = evidenceTables
        self.workspaces = workspaces
        self.alerts = alerts
        self.discoveryFeedback = discoveryFeedback
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collections = try container.decodeIfPresent([PaperCollection].self, forKey: .collections) ?? []
        smartFolders = try container.decodeIfPresent([SmartFolder].self, forKey: .smartFolders) ?? []
        citations = try container.decodeIfPresent([CitationRecord].self, forKey: .citations) ?? []
        evidenceTables = try container.decodeIfPresent([EvidenceTable].self, forKey: .evidenceTables) ?? []
        workspaces = try container.decodeIfPresent([SynthesisWorkspace].self, forKey: .workspaces) ?? []
        alerts = try container.decodeIfPresent([ResearchAlert].self, forKey: .alerts) ?? []
        discoveryFeedback = try container.decodeIfPresent([String: Bool].self, forKey: .discoveryFeedback) ?? [:]
    }
}
