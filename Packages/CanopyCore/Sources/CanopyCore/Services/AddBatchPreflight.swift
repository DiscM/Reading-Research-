import Foundation

public struct ParsedAuthorCredit: Equatable, Sendable {
    public let displayName: String
    public let familyName: String
    public let provenance: MetadataProvenance

    public init(displayName: String, familyName: String, provenance: MetadataProvenance) {
        self.displayName = displayName
        self.familyName = familyName
        self.provenance = provenance
    }
}

public struct ParsedPaperMetadata: Equatable, Sendable {
    public let title: String
    public let titleProvenance: MetadataProvenance
    public let authors: [ParsedAuthorCredit]
    public let publicationYear: Int?
    public let publicationYearProvenance: MetadataProvenance?
    public let doi: String?
    public let doiProvenance: MetadataProvenance?
    public let arxivID: String?
    public let arxivIDProvenance: MetadataProvenance?
    public let pageCount: Int
    public let hasSelectableText: Bool

    public init(
        title: String,
        titleProvenance: MetadataProvenance,
        authors: [ParsedAuthorCredit] = [],
        publicationYear: Int? = nil,
        publicationYearProvenance: MetadataProvenance? = nil,
        doi: String? = nil,
        doiProvenance: MetadataProvenance? = nil,
        arxivID: String? = nil,
        arxivIDProvenance: MetadataProvenance? = nil,
        pageCount: Int = 0,
        hasSelectableText: Bool = false
    ) {
        self.title = title
        self.titleProvenance = titleProvenance
        self.authors = authors
        self.publicationYear = publicationYear
        self.publicationYearProvenance = publicationYearProvenance
        self.doi = doi
        self.doiProvenance = doiProvenance
        self.arxivID = arxivID
        self.arxivIDProvenance = arxivIDProvenance
        self.pageCount = pageCount
        self.hasSelectableText = hasSelectableText
    }
}

public protocol DocumentAnalyzing: Sendable {
    func analyze(_ url: URL) throws -> ParsedPaperMetadata
}

public enum AddBatchPreflightInputError: LocalizedError, Equatable, Sendable {
    case missing
    case inaccessible

    public var errorDescription: String? {
        switch self {
        case .missing: "The selected PDF could not be found."
        case .inaccessible: "The selected PDF could not be accessed."
        }
    }
}

public struct PaperIdentitySnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fingerprint: Data
    public let title: String
    public let authorFamilyNames: [String]
    public let publicationYear: Int?
    public let doi: String?
    public let arxivID: String?
    public let sourceState: PaperSourceState
    public let rememberedLocation: String?
    public let storageMode: PaperStorageMode
    public let sourceFilename: String
    public let sourceFileSize: Int64
    public let pageCount: Int
    public let authorDisplayNames: [String]

    public init(
        id: UUID,
        fingerprint: Data,
        title: String,
        authorFamilyNames: [String],
        publicationYear: Int?,
        doi: String?,
        arxivID: String?,
        sourceState: PaperSourceState,
        rememberedLocation: String?,
        storageMode: PaperStorageMode = .referenced,
        sourceFilename: String = "",
        sourceFileSize: Int64 = 0,
        pageCount: Int = 0,
        authorDisplayNames: [String] = []
    ) {
        self.id = id
        self.fingerprint = fingerprint
        self.title = title
        self.authorFamilyNames = authorFamilyNames
        self.publicationYear = publicationYear
        self.doi = doi
        self.arxivID = arxivID
        self.sourceState = sourceState
        self.rememberedLocation = rememberedLocation
        self.storageMode = storageMode
        self.sourceFilename = sourceFilename
        self.sourceFileSize = sourceFileSize
        self.pageCount = pageCount
        self.authorDisplayNames = authorDisplayNames
    }
}

public struct PreflightCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let fingerprint: Data
    public let fileSize: Int64
    public let modificationDate: Date?
    public let metadata: ParsedPaperMetadata

    public init(
        id: UUID = UUID(),
        url: URL,
        fingerprint: Data,
        fileSize: Int64,
        modificationDate: Date?,
        metadata: ParsedPaperMetadata
    ) {
        self.id = id
        self.url = url
        self.fingerprint = fingerprint
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.metadata = metadata
    }
}

public struct ExactDuplicate: Equatable, Sendable {
    public let candidate: PreflightCandidate
    public let existingPaper: PaperIdentitySnapshot
}

public struct PotentialDuplicateMatch: Identifiable, Equatable, Sendable {
    public var id: UUID { existingPaper.id }
    public let existingPaper: PaperIdentitySnapshot
    public let triggerReasons: [String]

    public init(existingPaper: PaperIdentitySnapshot, triggerReasons: [String]) {
        self.existingPaper = existingPaper
        self.triggerReasons = triggerReasons
    }
}

public struct PotentialDuplicate: Identifiable, Equatable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: PreflightCandidate
    public let matches: [PotentialDuplicateMatch]

    public init(candidate: PreflightCandidate, matches: [PotentialDuplicateMatch]) {
        self.candidate = candidate
        self.matches = matches
    }
}

public struct WithinBatchExactDuplicate: Equatable, Sendable {
    public let retained: PreflightCandidate
    public let duplicate: PreflightCandidate
}

public struct PreflightFailure: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let message: String

    public init(id: UUID = UUID(), url: URL, message: String) {
        self.id = id
        self.url = url
        self.message = message
    }
}

public struct AddBatchPreflightResult: Sendable {
    public var ready: [PreflightCandidate] = []
    public var exactDuplicates: [ExactDuplicate] = []
    public var withinBatchExactDuplicates: [WithinBatchExactDuplicate] = []
    public var potentialDuplicates: [PotentialDuplicate] = []
    public var failures: [PreflightFailure] = []
}

public struct AddBatchPreflightProgress: Sendable {
    public let fractionCompleted: Double
    public let fileIndex: Int
    public let fileCount: Int
    public let filename: String

    public init(fractionCompleted: Double, fileIndex: Int, fileCount: Int, filename: String) {
        self.fractionCompleted = fractionCompleted
        self.fileIndex = fileIndex
        self.fileCount = fileCount
        self.filename = filename
    }
}

public struct AddBatchPreflight<Analyzer: DocumentAnalyzing>: Sendable {
    private let analyzer: Analyzer

    public init(analyzer: Analyzer) {
        self.analyzer = analyzer
    }

    public func run(
        urls: [URL],
        existingPapers: [PaperIdentitySnapshot],
        progress: (@Sendable (AddBatchPreflightProgress) -> Void)? = nil
    ) throws -> AddBatchPreflightResult {
        try Task.checkCancellation()
        var result = AddBatchPreflightResult()
        var processedCandidates: [PreflightCandidate] = []
        let fileSizes = urls.map { url in
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value).flatMap { $0 } ?? 0
        }
        let totalBytes = max(fileSizes.reduce(0, +), 1)
        var completedBytes: Int64 = 0
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            do {
                let bytesBeforeCurrentFile = completedBytes
                let candidate = try makeCandidate(url: url) { bytesRead in
                    let hashedBytes = bytesBeforeCurrentFile + Int64(bytesRead)
                    progress?(AddBatchPreflightProgress(
                        fractionCompleted: min(Double(hashedBytes) / Double(totalBytes) * 0.9, 0.9),
                        fileIndex: index + 1,
                        fileCount: urls.count,
                        filename: url.lastPathComponent
                    ))
                }
                completedBytes += candidate.fileSize
                if let existingPaper = existingPapers.first(where: { $0.fingerprint == candidate.fingerprint }) {
                    result.exactDuplicates.append(ExactDuplicate(candidate: candidate, existingPaper: existingPaper))
                } else if let retained = processedCandidates.first(where: { $0.fingerprint == candidate.fingerprint }) {
                    result.withinBatchExactDuplicates.append(WithinBatchExactDuplicate(retained: retained, duplicate: candidate))
                } else {
                    let comparisonPapers = existingPapers + processedCandidates.map(identitySnapshot)
                    let matches = comparisonPapers.compactMap { paper -> PotentialDuplicateMatch? in
                        let reasons = duplicateReasons(candidate: candidate, paper: paper)
                        guard !reasons.isEmpty else { return nil }
                        return PotentialDuplicateMatch(
                            existingPaper: paper,
                            triggerReasons: Array(Set(reasons)).sorted()
                        )
                    }
                    processedCandidates.append(candidate)
                    if matches.isEmpty {
                        result.ready.append(candidate)
                    } else {
                        result.potentialDuplicates.append(PotentialDuplicate(
                            candidate: candidate,
                            matches: matches
                        ))
                    }
                }
                let analysisFraction = Double(index + 1) / Double(max(urls.count, 1)) * 0.1
                progress?(AddBatchPreflightProgress(
                    fractionCompleted: min(Double(completedBytes) / Double(totalBytes) * 0.9 + analysisFraction, 1),
                    fileIndex: index + 1,
                    fileCount: urls.count,
                    filename: url.lastPathComponent
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                result.failures.append(PreflightFailure(url: url, message: error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        return result
    }

    private func makeCandidate(url: URL, progress: ((Int) -> Void)? = nil) throws -> PreflightCandidate {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw AddBatchPreflightInputError.missing
        }
        guard !isDirectory.boolValue, FileManager.default.isReadableFile(atPath: url.path) else {
            throw AddBatchPreflightInputError.inaccessible
        }
        let attributes: [FileAttributeKey: Any]
        let fingerprint: Data
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fingerprint = try DocumentFingerprint.sha256(of: url, didReadBytes: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                throw AddBatchPreflightInputError.missing
            }
            throw AddBatchPreflightInputError.inaccessible
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        return try PreflightCandidate(
            url: url,
            fingerprint: fingerprint,
            fileSize: size,
            modificationDate: modificationDate,
            metadata: analyzer.analyze(url)
        )
    }

    private func duplicateReasons(candidate: PreflightCandidate, paper: PaperIdentitySnapshot) -> [String] {
        var reasons: [String] = []
        if let candidateDOI = normalizedDOI(candidate.metadata.doi),
           let paperDOI = normalizedDOI(paper.doi),
           candidateDOI == paperDOI {
            reasons.append("Matching DOI")
        }
        if let candidateArxiv = baseArxivID(candidate.metadata.arxivID),
           let paperArxiv = baseArxivID(paper.arxivID),
           candidateArxiv == paperArxiv {
            reasons.append("Matching arXiv ID")
        }

        let titlesMatch = normalizedTitle(candidate.metadata.title) == normalizedTitle(paper.title)
        if titlesMatch {
            let candidateFamilies = Set(candidate.metadata.authors.map { normalizedName($0.familyName) })
            let paperFamilies = Set(paper.authorFamilyNames.map(normalizedName))
            if !candidateFamilies.isEmpty, !candidateFamilies.isDisjoint(with: paperFamilies) {
                reasons.append("Matching title and author")
            }
            if let candidateYear = candidate.metadata.publicationYear,
               candidateYear == paper.publicationYear {
                reasons.append("Matching title and year")
            }
        }
        return reasons
    }

    private func identitySnapshot(_ candidate: PreflightCandidate) -> PaperIdentitySnapshot {
        PaperIdentitySnapshot(
            id: candidate.id,
            fingerprint: candidate.fingerprint,
            title: candidate.metadata.title,
            authorFamilyNames: candidate.metadata.authors.map(\.familyName),
            publicationYear: candidate.metadata.publicationYear,
            doi: candidate.metadata.doi,
            arxivID: candidate.metadata.arxivID,
            sourceState: .available,
            rememberedLocation: candidate.url.path,
            sourceFilename: candidate.url.lastPathComponent,
            sourceFileSize: candidate.fileSize,
            pageCount: candidate.metadata.pageCount,
            authorDisplayNames: candidate.metadata.authors.map(\.displayName)
        )
    }

    private func normalizedDOI(_ value: String?) -> String? {
        MetadataValidator.normalizedDOI(value)
    }

    private func baseArxivID(_ value: String?) -> String? {
        MetadataValidator.normalizedArxivID(value)?
            .replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
    }

    private func normalizedTitle(_ value: String) -> String {
        let flattened = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
        return flattened.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    private func normalizedName(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
