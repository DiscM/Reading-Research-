import CanopyCore
import Foundation
import Observation

enum PaperInfoDraftError: LocalizedError, Equatable {
    case invalidPublicationYear

    var errorDescription: String? {
        switch self {
        case .invalidPublicationYear:
            "Publication year must be a four-digit year from 1000 through next year."
        }
    }
}

struct PaperInfoDraft: Equatable {
    var title: String
    var publicationYearText: String
    var doi: String
    var arxivID: String
    var authorCredits: [PaperInfoAuthorCreditDraft]

    init(
        title: String = "",
        publicationYearText: String = "",
        doi: String = "",
        arxivID: String = "",
        authorCredits: [PaperInfoAuthorCreditDraft] = []
    ) {
        self.title = title
        self.publicationYearText = publicationYearText
        self.doi = doi
        self.arxivID = arxivID
        self.authorCredits = authorCredits
    }

    init(snapshot: PaperInfoSnapshot) {
        self.init(
            title: snapshot.title,
            publicationYearText: snapshot.publicationYear.map(String.init) ?? "",
            doi: snapshot.doi ?? "",
            arxivID: snapshot.arxivID ?? "",
            authorCredits: snapshot.authorCredits.map(PaperInfoAuthorCreditDraft.init)
        )
    }

    func makeUpdate(now: Date = .now) throws -> PaperInfoUpdate {
        let yearText = publicationYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        let publicationYear: Int?
        if yearText.isEmpty {
            publicationYear = nil
        } else {
            guard yearText.count == 4,
                  let parsedYear = Int(yearText),
                  MetadataValidator.validPublicationYear(parsedYear, now: now) else {
                throw PaperInfoDraftError.invalidPublicationYear
            }
            publicationYear = parsedYear
        }

        return PaperInfoUpdate(
            title: title,
            publicationYear: publicationYear,
            doi: optionalNonempty(doi),
            arxivID: optionalNonempty(arxivID),
            authorCredits: authorCredits.map {
                AuthorCreditUpdate(
                    id: $0.id,
                    displayName: $0.displayName,
                    familyName: $0.familyName
                )
            }
        )
    }

    mutating func updateAuthorDisplayName(id: UUID, displayName: String) {
        guard let index = authorCredits.firstIndex(where: { $0.id == id }) else { return }
        let previousDisplayName = authorCredits[index].displayName
        let previousDerivedFamilyName = MetadataValidator.inferredFamilyName(previousDisplayName)
        let followsDerivedFamilyName = authorCredits[index].familyName
            .trimmingCharacters(in: .whitespacesAndNewlines) == previousDerivedFamilyName
        authorCredits[index].displayName = displayName
        if followsDerivedFamilyName {
            authorCredits[index].familyName = MetadataValidator.inferredFamilyName(displayName)
        }
    }

    mutating func updateAuthorFamilyName(id: UUID, familyName: String) {
        guard let index = authorCredits.firstIndex(where: { $0.id == id }) else { return }
        authorCredits[index].familyName = familyName
    }

    mutating func addAuthorCredit(id: UUID = UUID()) {
        authorCredits.append(PaperInfoAuthorCreditDraft(id: id, displayName: "", familyName: ""))
    }

    mutating func removeAuthorCredit(id: UUID) {
        authorCredits.removeAll { $0.id == id }
    }

    mutating func moveAuthorCredit(id: UUID, toInsertionIndex insertionIndex: Int) {
        guard let sourceIndex = authorCredits.firstIndex(where: { $0.id == id }) else { return }
        let author = authorCredits.remove(at: sourceIndex)
        let adjustedIndex = sourceIndex < insertionIndex ? insertionIndex - 1 : insertionIndex
        authorCredits.insert(author, at: min(max(adjustedIndex, 0), authorCredits.count))
    }

    mutating func moveAuthorCredit(id: UUID, by offset: Int) {
        guard let sourceIndex = authorCredits.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = min(max(sourceIndex + offset, 0), authorCredits.count - 1)
        guard destinationIndex != sourceIndex else { return }
        let authorCredit = authorCredits.remove(at: sourceIndex)
        authorCredits.insert(authorCredit, at: destinationIndex)
    }

    private func optionalNonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PaperInfoAuthorCreditDraft: Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var familyName: String

    init(id: UUID, displayName: String, familyName: String) {
        self.id = id
        self.displayName = displayName
        self.familyName = familyName
    }

    init(snapshot: AuthorCreditSnapshot) {
        self.init(
            id: snapshot.id,
            displayName: snapshot.displayName,
            familyName: snapshot.familyName
        )
    }
}

struct PaperInfoReadOnlyDetails: Equatable {
    let documentKind: DocumentKind
    let sourceStatus: String
    let storage: String
    let sourceFilename: String
    let sourceLocation: String
    let storageMode: PaperStorageMode
    let sourceState: PaperSourceState

    init(paper: Paper) {
        documentKind = paper.kind
        storageMode = paper.storageMode
        sourceState = paper.sourceState
        sourceStatus = switch paper.sourceState {
        case .available: "Available"
        case .sourceUnavailable: "Source Unavailable"
        case .brokenReference: "Source Missing"
        case .sourceChanged: "Source Changed"
        case .libraryCopyMissing: "Library Copy Missing"
        }
        switch paper.storageMode {
        case .referenced:
            storage = "Referenced"
            sourceLocation = paper.rememberedLocation ?? "Location unavailable"
        case .managedCopy:
            storage = "Managed by Canopy"
            sourceLocation = "Canopy Application Support"
        }
        sourceFilename = paper.sourceFilename
    }
}

@Observable
@MainActor
final class PaperInfoWorkflow {
    private(set) var paperID: UUID?
    private(set) var originalSnapshot: PaperInfoSnapshot?
    private(set) var readOnlyDetails: PaperInfoReadOnlyDetails?
    var draft = PaperInfoDraft()
    var isPresented = false
    var errorMessage: String?
    private(set) var reparseState: PaperInfoReparseState = .idle
    private(set) var reparseMessage: String?
    var reparseErrorMessage: String?

    private var acceptedReparsedMetadata: [PaperInfoMetadataField: PaperInfoReparseMetadata] = [:]
    @ObservationIgnored private var activeReparseAnalysis: (
        requestID: UUID,
        task: Task<ParsedPaperMetadata, Error>
    )?

    var hasChanges: Bool {
        guard let originalSnapshot else { return false }
        return draft != PaperInfoDraft(snapshot: originalSnapshot)
    }

    var documentKind: DocumentKind {
        readOnlyDetails?.documentKind ?? .generalDocument
    }

    var showsResearchMetadata: Bool {
        documentKind == .researchPaper
    }

    var reparseProposal: PaperInfoReparseProposal? {
        guard case let .reviewing(proposal) = reparseState else { return nil }
        return proposal
    }

    var isReparsing: Bool {
        guard case .loading = reparseState else { return false }
        return true
    }

    var hasActiveReparse: Bool {
        guard case .idle = reparseState else { return true }
        return false
    }

    func authorProvenance(id: UUID) -> MetadataProvenance {
        guard let author = draft.authorCredits.first(where: { $0.id == id }) else {
            return .userEntry
        }
        if let original = originalSnapshot?.authorCredits.first(where: { $0.id == id }),
           PaperInfoMetadataNormalization.author(author)
            == PaperInfoMetadataNormalization.author(original) {
            return original.provenance
        }
        if let reparsed = acceptedReparsedMetadata[.authorCredits]?.authorCredits
            .first(where: { $0.id == id }),
           PaperInfoMetadataNormalization.author(author)
            == PaperInfoMetadataNormalization.author(reparsed) {
            return reparsed.provenance
        }
        return .userEntry
    }

    func provenance(for field: PaperInfoMetadataField) -> MetadataProvenance? {
        guard let originalSnapshot else { return nil }
        switch field {
        case .title:
            return scalarProvenance(
                field: .title,
                value: PaperInfoMetadataNormalization.title(draft.title),
                originalValue: PaperInfoMetadataNormalization.title(originalSnapshot.title),
                originalProvenance: originalSnapshot.titleProvenance,
                reparsedValue: acceptedReparsedMetadata[.title]
                    .map { PaperInfoMetadataNormalization.title($0.title) },
                reparsedProvenance: acceptedReparsedMetadata[.title]?.titleProvenance
            )
        case .authorCredits:
            return nil
        case .publicationYear:
            let text = draft.publicationYearText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard let value = Int(text) else { return .userEntry }
            return optionalProvenance(
                field: .publicationYear,
                value: value,
                originalValue: originalSnapshot.publicationYear,
                originalProvenance: originalSnapshot.publicationYearProvenance,
                reparsedValue: acceptedReparsedMetadata[.publicationYear]?.publicationYear,
                reparsedProvenance: acceptedReparsedMetadata[.publicationYear]?.publicationYearProvenance
            )
        case .doi:
            return identifierProvenance(
                field: .doi,
                rawValue: draft.doi,
                normalizedValue: MetadataValidator.normalizedDOI(draft.doi),
                originalValue: MetadataValidator.normalizedDOI(originalSnapshot.doi),
                originalProvenance: originalSnapshot.doiProvenance,
                reparsedValue: MetadataValidator.normalizedDOI(acceptedReparsedMetadata[.doi]?.doi),
                reparsedProvenance: acceptedReparsedMetadata[.doi]?.doiProvenance
            )
        case .arxivID:
            return identifierProvenance(
                field: .arxivID,
                rawValue: draft.arxivID,
                normalizedValue: MetadataValidator.normalizedArxivID(draft.arxivID),
                originalValue: MetadataValidator.normalizedArxivID(originalSnapshot.arxivID),
                originalProvenance: originalSnapshot.arxivIDProvenance,
                reparsedValue: MetadataValidator.normalizedArxivID(acceptedReparsedMetadata[.arxivID]?.arxivID),
                reparsedProvenance: acceptedReparsedMetadata[.arxivID]?.arxivIDProvenance
            )
        }
    }

    func present(paperID: UUID, repository: LibraryRepository) throws {
        let snapshot = try repository.paperInfoSnapshot(paperID: paperID)
        guard let paper = try repository.paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        self.paperID = paperID
        originalSnapshot = snapshot
        readOnlyDetails = PaperInfoReadOnlyDetails(paper: paper)
        draft = PaperInfoDraft(snapshot: snapshot)
        errorMessage = nil
        resetReparse()
        isPresented = true
    }

    func reparse(
        repository: LibraryRepository,
        managedStore: ManagedPaperStore? = nil
    ) async {
        await reparse(
            repository: repository,
            analyzer: PDFDocumentAnalyzer(),
            managedStore: managedStore
        )
    }

    func reparse<Analyzer: DocumentAnalyzing>(
        repository: LibraryRepository,
        analyzer: Analyzer,
        managedStore: ManagedPaperStore? = nil
    ) async {
        guard let requestedPaperID = paperID, !hasActiveReparse else { return }
        let requestID = UUID()
        reparseState = .loading(requestID: requestID)
        reparseMessage = nil
        reparseErrorMessage = nil

        do {
            try Task.checkCancellation()
            let sourceAccess = try repository.sourceAccess(
                paperID: requestedPaperID,
                managedStore: managedStore
            )
            let sourceURL = sourceAccess.url
            let analysis = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let parsed = try analyzer.analyze(sourceURL)
                try Task.checkCancellation()
                return parsed
            }
            activeReparseAnalysis = (requestID, analysis)
            defer {
                if activeReparseAnalysis?.requestID == requestID {
                    activeReparseAnalysis = nil
                }
                withExtendedLifetime(sourceAccess) {}
            }
            let parsed = try await withTaskCancellationHandler {
                try await analysis.value
            } onCancel: {
                analysis.cancel()
            }
            try Task.checkCancellation()

            guard isCurrentReparse(requestID: requestID, paperID: requestedPaperID) else { return }
            _ = try repository.sourceAccess(
                paperID: requestedPaperID,
                managedStore: managedStore
            )
            guard isCurrentReparse(requestID: requestID, paperID: requestedPaperID) else { return }
            refreshReadOnlyDetails(repository: repository)
            reviewReparsedMetadata(metadataForCurrentDocument(parsed))
        } catch is CancellationError {
            guard isCurrentReparse(requestID: requestID, paperID: requestedPaperID) else { return }
            reparseState = .idle
        } catch {
            guard isCurrentReparse(requestID: requestID, paperID: requestedPaperID) else { return }
            refreshReadOnlyDetails(repository: repository)
            reparseState = .idle
            reparseErrorMessage = reparseErrorDescription(error)
        }
    }

    private func metadataForCurrentDocument(
        _ metadata: ParsedPaperMetadata
    ) -> ParsedPaperMetadata {
        guard !showsResearchMetadata else { return metadata }
        return ParsedPaperMetadata(
            title: metadata.title,
            titleProvenance: metadata.titleProvenance,
            authors: metadata.authors.filter { $0.provenance == .embeddedMetadata },
            publicationYear: metadata.publicationYearProvenance == .embeddedMetadata
                ? metadata.publicationYear
                : nil,
            publicationYearProvenance: metadata.publicationYearProvenance == .embeddedMetadata
                ? metadata.publicationYearProvenance
                : nil,
            pageCount: metadata.pageCount,
            hasSelectableText: metadata.hasSelectableText
        )
    }

    func reviewReparsedMetadata(_ parsed: ParsedPaperMetadata) {
        let currentProvenance = Dictionary(uniqueKeysWithValues: PaperInfoMetadataField.allCases.compactMap { field in
            provenance(for: field).map { (field, $0) }
        })
        let currentAuthorProvenance = Dictionary(uniqueKeysWithValues: draft.authorCredits.map { author in
            (author.id, authorProvenance(id: author.id))
        })
        let proposal = PaperInfoReparseProposal(
            parsed: parsed,
            current: draft,
            acceptedMetadataAtStart: acceptedReparsedMetadata,
            currentProvenance: currentProvenance,
            currentAuthorProvenance: currentAuthorProvenance
        )
        if proposal.remainingFields.isEmpty {
            reparseState = .idle
            reparseMessage = "No different usable metadata was found."
        } else {
            reparseState = .reviewing(proposal)
            reparseMessage = nil
        }
    }

    func acceptReparsed(_ field: PaperInfoMetadataField) {
        guard case var .reviewing(proposal) = reparseState,
              proposal.fields.contains(field) else { return }

        let metadata = proposal.metadata
        applyReparsed(field, metadata: metadata)
        acceptedReparsedMetadata[field] = metadata
        proposal.decisions[field] = .useFound
        reparseState = .reviewing(proposal)
    }

    func keepCurrent(_ field: PaperInfoMetadataField) {
        guard case var .reviewing(proposal) = reparseState,
              proposal.fields.contains(field) else { return }
        restoreCurrent(field, from: proposal.current)
        acceptedReparsedMetadata[field] = proposal.acceptedMetadataAtStart[field]
        proposal.decisions[field] = .keepCurrent
        reparseState = .reviewing(proposal)
    }

    func finishReparseReview() {
        guard case let .reviewing(proposal) = reparseState,
              proposal.remainingFields.isEmpty else { return }
        reparseState = .idle
        reparseMessage = proposal.decisions.values.contains(.useFound)
            ? "Metadata choices are staged. Save to keep them."
            : "Kept the current metadata."
    }

    func discardReparseResults() {
        guard case let .reviewing(proposal) = reparseState else { return }
        for field in proposal.fields {
            restoreCurrent(field, from: proposal.current)
            acceptedReparsedMetadata[field] = proposal.acceptedMetadataAtStart[field]
        }
        reparseState = .idle
        reparseMessage = "Kept the current metadata."
    }

    func makeTargetSnapshot(now: Date = .now) throws -> PaperInfoSnapshot {
        guard let paperID, let originalSnapshot else {
            throw LibraryRepositoryError.paperNotFound
        }
        let update = try draft.makeUpdate(now: now)
        let title = MetadataValidator.usableTitle(update.title) ?? update.title
        let doi = MetadataValidator.normalizedDOI(update.doi)
        let arxivID = MetadataValidator.normalizedArxivID(update.arxivID)
        let documentDate = update.publicationYear == originalSnapshot.publicationYear
            ? originalSnapshot.documentDate
            : update.publicationYear.flatMap { DocumentDate(year: $0) }
        let documentDateProvenance = optionalProvenance(
            field: .publicationYear,
            value: update.publicationYear,
            originalValue: originalSnapshot.publicationYear,
            originalProvenance: originalSnapshot.documentDateProvenance,
            reparsedValue: acceptedReparsedMetadata[.publicationYear]?.publicationYear,
            reparsedProvenance: acceptedReparsedMetadata[.publicationYear]?.publicationYearProvenance
        )

        return PaperInfoSnapshot(
            paperID: paperID,
            title: update.title,
            titleProvenance: scalarProvenance(
                field: .title,
                value: PaperInfoMetadataNormalization.title(title),
                originalValue: PaperInfoMetadataNormalization.title(originalSnapshot.title),
                originalProvenance: originalSnapshot.titleProvenance,
                reparsedValue: acceptedReparsedMetadata[.title]
                    .map { PaperInfoMetadataNormalization.title($0.title) },
                reparsedProvenance: acceptedReparsedMetadata[.title]?.titleProvenance
            ),
            documentDate: documentDate,
            documentDateProvenance: documentDateProvenance,
            doi: update.doi,
            doiProvenance: identifierProvenance(
                field: .doi,
                rawValue: draft.doi,
                normalizedValue: doi,
                originalValue: MetadataValidator.normalizedDOI(originalSnapshot.doi),
                originalProvenance: originalSnapshot.doiProvenance,
                reparsedValue: MetadataValidator.normalizedDOI(acceptedReparsedMetadata[.doi]?.doi),
                reparsedProvenance: acceptedReparsedMetadata[.doi]?.doiProvenance
            ),
            arxivID: update.arxivID,
            arxivIDProvenance: identifierProvenance(
                field: .arxivID,
                rawValue: draft.arxivID,
                normalizedValue: arxivID,
                originalValue: MetadataValidator.normalizedArxivID(originalSnapshot.arxivID),
                originalProvenance: originalSnapshot.arxivIDProvenance,
                reparsedValue: MetadataValidator.normalizedArxivID(acceptedReparsedMetadata[.arxivID]?.arxivID),
                reparsedProvenance: acceptedReparsedMetadata[.arxivID]?.arxivIDProvenance
            ),
            authorCredits: draft.authorCredits.enumerated().map { position, author in
                AuthorCreditSnapshot(
                    id: author.id,
                    position: position,
                    displayName: author.displayName,
                    familyName: author.familyName,
                    provenance: authorProvenance(id: author.id)
                )
            }
        )
    }

    func finishSaving(_ change: PaperInfoChange) {
        originalSnapshot = change.after
        draft = PaperInfoDraft(snapshot: change.after)
        dismiss()
    }

    func dismiss() {
        isPresented = false
        paperID = nil
        originalSnapshot = nil
        readOnlyDetails = nil
        draft = PaperInfoDraft()
        errorMessage = nil
        resetReparse()
    }

    private func applyReparsed(
        _ field: PaperInfoMetadataField,
        metadata: PaperInfoReparseMetadata
    ) {
        switch field {
        case .title:
            draft.title = metadata.title
        case .authorCredits:
            draft.authorCredits = metadata.authorCredits.map { author in
                PaperInfoAuthorCreditDraft(
                    id: author.id,
                    displayName: author.displayName,
                    familyName: author.familyName
                )
            }
        case .publicationYear:
            draft.publicationYearText = metadata.publicationYear.map(String.init) ?? ""
        case .doi:
            draft.doi = metadata.doi ?? ""
        case .arxivID:
            draft.arxivID = metadata.arxivID ?? ""
        }
    }

    private func restoreCurrent(_ field: PaperInfoMetadataField, from current: PaperInfoDraft) {
        switch field {
        case .title:
            draft.title = current.title
        case .authorCredits:
            draft.authorCredits = current.authorCredits
        case .publicationYear:
            draft.publicationYearText = current.publicationYearText
        case .doi:
            draft.doi = current.doi
        case .arxivID:
            draft.arxivID = current.arxivID
        }
    }

    private func scalarProvenance<Value: Equatable>(
        field: PaperInfoMetadataField,
        value: Value,
        originalValue: Value,
        originalProvenance: MetadataProvenance,
        reparsedValue: Value?,
        reparsedProvenance: MetadataProvenance?
    ) -> MetadataProvenance {
        if acceptedReparsedMetadata[field] != nil,
           value == reparsedValue,
           let reparsedProvenance {
            return reparsedProvenance
        }
        if value == originalValue { return originalProvenance }
        return .userEntry
    }

    private func optionalProvenance<Value: Equatable>(
        field: PaperInfoMetadataField,
        value: Value?,
        originalValue: Value?,
        originalProvenance: MetadataProvenance?,
        reparsedValue: Value?,
        reparsedProvenance: MetadataProvenance?
    ) -> MetadataProvenance? {
        guard let value else { return nil }
        if acceptedReparsedMetadata[field] != nil,
           value == reparsedValue,
           let reparsedProvenance {
            return reparsedProvenance
        }
        if value == originalValue { return originalProvenance }
        return .userEntry
    }

    private func identifierProvenance(
        field: PaperInfoMetadataField,
        rawValue: String,
        normalizedValue: String?,
        originalValue: String?,
        originalProvenance: MetadataProvenance?,
        reparsedValue: String?,
        reparsedProvenance: MetadataProvenance?
    ) -> MetadataProvenance? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let normalizedValue else { return .userEntry }
        return optionalProvenance(
            field: field,
            value: normalizedValue,
            originalValue: originalValue,
            originalProvenance: originalProvenance,
            reparsedValue: reparsedValue,
            reparsedProvenance: reparsedProvenance
        )
    }

    private func isCurrentReparse(requestID: UUID, paperID: UUID) -> Bool {
        guard isPresented, self.paperID == paperID,
              case .loading(requestID) = reparseState else { return false }
        return true
    }

    func refreshReadOnlyDetails(repository: LibraryRepository) {
        guard let paperID,
              let paper = try? repository.paper(id: paperID) else { return }
        readOnlyDetails = PaperInfoReadOnlyDetails(paper: paper)
    }

    private func resetReparse() {
        activeReparseAnalysis?.task.cancel()
        activeReparseAnalysis = nil
        reparseState = .idle
        reparseMessage = nil
        reparseErrorMessage = nil
        acceptedReparsedMetadata = [:]
    }

    private func reparseErrorDescription(_ error: Error) -> String {
        guard let sourceError = error as? PaperSourceAccessError else {
            return error.localizedDescription
        }
        return switch sourceError {
        case .sourceUnavailable:
            "The Source PDF is temporarily unavailable. Reconnect its location and try again."
        case .sourceMissing:
            "Locate the missing Source PDF before reparsing metadata."
        case .sourceChanged:
            "The Source PDF no longer matches this Document. Locate the original before reparsing metadata."
        case .libraryCopyMissing:
            "Restore the missing Canopy-managed Source PDF before reparsing metadata."
        }
    }
}
