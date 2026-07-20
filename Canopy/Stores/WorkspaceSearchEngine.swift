import CanopyCore
import Foundation

struct WorkspaceSearchAnnotation: Identifiable, Equatable, Sendable {
    let id: UUID
    let pageIndex: Int
    let note: String
    let selectedQuotation: String?

    init(
        id: UUID,
        pageIndex: Int,
        note: String,
        selectedQuotation: String?
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.note = note
        self.selectedQuotation = selectedQuotation
    }

    init(annotation: Annotation) {
        self.init(
            id: annotation.id,
            pageIndex: annotation.pageIndex,
            note: annotation.note,
            selectedQuotation: annotation.selectedText
        )
    }
}

struct WorkspaceSearchDocument: Identifiable, Sendable {
    let id: UUID
    let fingerprint: Data
    let title: String
    let collectionNames: [String]
    let creatorNames: [String]
    let kind: DocumentKind
    let documentDate: DocumentDate?
    let documentNote: String
    let annotations: [WorkspaceSearchAnnotation]

    init(
        id: UUID,
        fingerprint: Data,
        title: String,
        collectionNames: [String],
        creatorNames: [String],
        kind: DocumentKind,
        documentDate: DocumentDate?,
        documentNote: String,
        annotations: [WorkspaceSearchAnnotation]
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.collectionNames = collectionNames
        self.creatorNames = creatorNames
        self.kind = kind
        self.documentDate = documentDate
        self.documentNote = documentNote
        self.annotations = annotations
    }

    init(document: Document) {
        var seenCollectionIDs: Set<UUID> = []
        let collections = document.collections.filter {
            seenCollectionIDs.insert($0.id).inserted
        }
        var seenCreatorIDs: Set<UUID> = []
        let creatorCredits = document.creatorCredits.filter {
            seenCreatorIDs.insert($0.id).inserted
        }
        var seenAnnotationIDs: Set<UUID> = []
        let annotations = document.annotations.filter {
            seenAnnotationIDs.insert($0.id).inserted
        }
        self.init(
            id: document.id,
            fingerprint: document.fingerprint,
            title: document.title,
            collectionNames: collections
                .sorted(by: Self.collectionPrecedes)
                .map(\.name),
            creatorNames: creatorCredits
                .sorted { lhs, rhs in
                    if lhs.position != rhs.position { return lhs.position < rhs.position }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map(\.displayName),
            kind: document.kind,
            documentDate: document.documentDate,
            documentNote: document.documentNote,
            annotations: annotations
                .sorted { lhs, rhs in
                    if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .map(WorkspaceSearchAnnotation.init(annotation:))
        )
    }

    private static func collectionPrecedes(_ lhs: Collection, _ rhs: Collection) -> Bool {
        let lhsName = lhs.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let rhsName = rhs.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct WorkspaceSearchScope: Equatable, Sendable {
    let allowedDocumentIDs: Set<UUID>?
    let allowedFingerprints: Set<Data>?

    static let all = WorkspaceSearchScope(
        allowedDocumentIDs: nil,
        allowedFingerprints: nil
    )

    init(
        allowedDocumentIDs: Set<UUID>? = nil,
        allowedFingerprints: Set<Data>? = nil
    ) {
        self.allowedDocumentIDs = allowedDocumentIDs
        self.allowedFingerprints = allowedFingerprints
    }

    fileprivate func allows(_ document: WorkspaceSearchDocument) -> Bool {
        if let allowedDocumentIDs, !allowedDocumentIDs.contains(document.id) { return false }
        if let allowedFingerprints, !allowedFingerprints.contains(document.fingerprint) { return false }
        return true
    }
}

enum WorkspaceSearchHitSource: Int, Equatable, Sendable {
    case title
    case collection
    case creator
    case documentKind
    case documentDate
    case documentNote
    case annotationNote
    case annotationQuotation
    case pdfBody

    fileprivate var rank: Int {
        switch self {
        case .title: 0
        case .collection, .creator, .documentKind, .documentDate: 1
        case .documentNote, .annotationNote: 2
        case .annotationQuotation: 3
        case .pdfBody: 4
        }
    }
}

struct WorkspaceSearchChildHit: Equatable, Sendable {
    let source: WorkspaceSearchHitSource
    let snippet: String
    let pageIndex: Int?
    let annotationID: UUID?
    let relevanceScore: Double?

    var pageNumber: Int? { pageIndex.map { $0 + 1 } }
}

struct WorkspaceSearchDocumentGroup: Identifiable, Equatable, Sendable {
    let documentID: UUID
    let fingerprint: Data
    let title: String
    let childHits: [WorkspaceSearchChildHit]

    var id: UUID { documentID }
    var initialChildHits: [WorkspaceSearchChildHit] { Array(childHits.prefix(3)) }
    var additionalMatchCount: Int { max(0, childHits.count - initialChildHits.count) }
}

enum WorkspaceSearchEngine {
    static func search(
        query: String,
        documents: [WorkspaceSearchDocument],
        pdfTextHits: [PDFTextSearchHit],
        scope: WorkspaceSearchScope
    ) -> [WorkspaceSearchDocumentGroup] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = Self.searchTokens(trimmedQuery)
        guard !queryTokens.isEmpty else { return [] }

        let pdfHitsByFingerprint = Dictionary(grouping: pdfTextHits, by: { $0.key.fingerprint })
        return documents.filter(scope.allows).compactMap { document in
            var childHits: [WorkspaceSearchChildHit] = []
            if Self.matches(document.title, queryTokens: queryTokens) {
                childHits.append(.init(
                    source: .title,
                    snippet: document.title,
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            for collectionName in document.collectionNames
                where Self.matches(collectionName, queryTokens: queryTokens) {
                childHits.append(.init(
                    source: .collection,
                    snippet: collectionName,
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            for creatorName in document.creatorNames
                where Self.matches(creatorName, queryTokens: queryTokens) {
                childHits.append(.init(
                    source: .creator,
                    snippet: creatorName,
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            if Self.matches(document.kind.displayName, queryTokens: queryTokens) {
                childHits.append(.init(
                    source: .documentKind,
                    snippet: document.kind.displayName,
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            if let documentDate = document.documentDate,
               Self.dateSearchValues(documentDate).contains(where: {
                   Self.matches($0, queryTokens: queryTokens)
               }) {
                childHits.append(.init(
                    source: .documentDate,
                    snippet: Self.dateDisplayText(documentDate),
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            if Self.matches(document.documentNote, queryTokens: queryTokens) {
                childHits.append(.init(
                    source: .documentNote,
                    snippet: Self.snippet(from: document.documentNote, queryTokens: queryTokens),
                    pageIndex: nil,
                    annotationID: nil,
                    relevanceScore: nil
                ))
            }
            for annotation in document.annotations {
                if Self.matches(annotation.note, queryTokens: queryTokens) {
                    childHits.append(.init(
                        source: .annotationNote,
                        snippet: Self.snippet(from: annotation.note, queryTokens: queryTokens),
                        pageIndex: annotation.pageIndex,
                        annotationID: annotation.id,
                        relevanceScore: nil
                    ))
                }
                if let quotation = annotation.selectedQuotation,
                   Self.matches(quotation, queryTokens: queryTokens) {
                    childHits.append(.init(
                        source: .annotationQuotation,
                        snippet: Self.snippet(from: quotation, queryTokens: queryTokens),
                        pageIndex: annotation.pageIndex,
                        annotationID: annotation.id,
                        relevanceScore: nil
                    ))
                }
            }
            for pdfHit in pdfHitsByFingerprint[document.fingerprint] ?? [] {
                childHits.append(.init(
                    source: .pdfBody,
                    snippet: pdfHit.snippet,
                    pageIndex: pdfHit.pageIndex,
                    annotationID: nil,
                    relevanceScore: pdfHit.relevanceScore
                ))
            }
            guard !childHits.isEmpty else { return nil }
            childHits.sort(by: Self.childHitPrecedes)
            return WorkspaceSearchDocumentGroup(
                documentID: document.id,
                fingerprint: document.fingerprint,
                title: document.title,
                childHits: childHits
            )
        }
        .sorted(by: Self.groupPrecedes)
    }

    private static func searchTokens(_ query: String) -> [String] {
        stableSearchText(query)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func matches(_ text: String, queryTokens: [String]) -> Bool {
        let searchableText = stableSearchText(text)
        return queryTokens.allSatisfy(searchableText.contains)
    }

    private static func stableSearchText(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func snippet(from text: String, queryTokens: [String]) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let maximumBodyLength = 154
        guard normalized.count > maximumBodyLength,
              let firstToken = queryTokens.first,
              let match = normalized.range(
                  of: firstToken,
                  options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
              ) else {
            return normalized
        }

        let matchOffset = normalized.distance(from: normalized.startIndex, to: match.lowerBound)
        var startOffset = max(0, matchOffset - 50)
        let endOffset = min(normalized.count, startOffset + maximumBodyLength)
        if endOffset == normalized.count {
            startOffset = max(0, endOffset - maximumBodyLength)
        }
        let start = normalized.index(normalized.startIndex, offsetBy: startOffset)
        let end = normalized.index(normalized.startIndex, offsetBy: endOffset)
        let prefix = startOffset > 0 ? "…" : ""
        let suffix = endOffset < normalized.count ? "…" : ""
        return prefix + normalized[start..<end] + suffix
    }

    private static func dateSearchValues(_ date: DocumentDate) -> [String] {
        var values = [String(date.year)]
        guard let month = date.month else { return values }
        let monthName = monthNames[month - 1]
        values.append("\(monthName) \(date.year)")
        values.append(String(format: "%04d-%02d", date.year, month))
        if let day = date.day {
            values.append("\(monthName) \(day), \(date.year)")
            values.append(String(format: "%04d-%02d-%02d", date.year, month, day))
        }
        return values
    }

    private static func dateDisplayText(_ date: DocumentDate) -> String {
        guard let month = date.month else { return String(date.year) }
        let monthName = monthNames[month - 1]
        guard let day = date.day else { return "\(monthName) \(date.year)" }
        return "\(monthName) \(day), \(date.year)"
    }

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    private static func childHitPrecedes(
        _ lhs: WorkspaceSearchChildHit,
        _ rhs: WorkspaceSearchChildHit
    ) -> Bool {
        if lhs.source.rank != rhs.source.rank { return lhs.source.rank < rhs.source.rank }
        if lhs.source.rawValue != rhs.source.rawValue { return lhs.source.rawValue < rhs.source.rawValue }
        if lhs.relevanceScore != rhs.relevanceScore {
            return (lhs.relevanceScore ?? 0) < (rhs.relevanceScore ?? 0)
        }
        if lhs.pageIndex != rhs.pageIndex {
            return (lhs.pageIndex ?? -1) < (rhs.pageIndex ?? -1)
        }
        if lhs.snippet != rhs.snippet {
            return stableTextPrecedes(lhs.snippet, rhs.snippet)
        }
        return (lhs.annotationID?.uuidString ?? "") < (rhs.annotationID?.uuidString ?? "")
    }

    private static func groupPrecedes(
        _ lhs: WorkspaceSearchDocumentGroup,
        _ rhs: WorkspaceSearchDocumentGroup
    ) -> Bool {
        let lhsRank = lhs.childHits.first?.source.rank ?? Int.max
        let rhsRank = rhs.childHits.first?.source.rank ?? Int.max
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if let lhsScore = lhs.childHits.first?.relevanceScore,
           let rhsScore = rhs.childHits.first?.relevanceScore,
           lhsScore != rhsScore {
            return lhsScore < rhsScore
        }
        if lhs.title != rhs.title { return stableTextPrecedes(lhs.title, rhs.title) }
        return lhs.documentID.uuidString < rhs.documentID.uuidString
    }

    private static func stableTextPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let normalizedLHS = stableSearchText(lhs)
        let normalizedRHS = stableSearchText(rhs)
        if normalizedLHS != normalizedRHS { return normalizedLHS < normalizedRHS }
        return lhs < rhs
    }
}
