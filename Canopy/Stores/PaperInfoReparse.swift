import CanopyCore
import Foundation

enum PaperInfoMetadataField: CaseIterable, Hashable, Identifiable {
    case title
    case authorCredits
    case publicationYear
    case doi
    case arxivID

    var id: Self { self }
}

struct PaperInfoReparseAuthorCredit: Equatable, Identifiable {
    let id: UUID
    let displayName: String
    let familyName: String
    let provenance: MetadataProvenance
}

struct PaperInfoReparseMetadata: Equatable {
    let title: String
    let titleProvenance: MetadataProvenance
    let authorCredits: [PaperInfoReparseAuthorCredit]
    let publicationYear: Int?
    let publicationYearProvenance: MetadataProvenance?
    let doi: String?
    let doiProvenance: MetadataProvenance?
    let arxivID: String?
    let arxivIDProvenance: MetadataProvenance?

    init(
        parsed: ParsedPaperMetadata,
        makeID: () -> UUID = UUID.init
    ) {
        title = MetadataValidator.usableTitle(parsed.title)
            ?? PaperInfoMetadataNormalization.title(parsed.title)
        titleProvenance = parsed.titleProvenance
        authorCredits = parsed.authors.map { author in
            PaperInfoReparseAuthorCredit(
                id: makeID(),
                displayName: PaperInfoMetadataNormalization.trimmed(author.displayName),
                familyName: PaperInfoMetadataNormalization.trimmed(author.familyName),
                provenance: author.provenance
            )
        }
        publicationYear = parsed.publicationYear
        publicationYearProvenance = parsed.publicationYearProvenance
        doi = MetadataValidator.normalizedDOI(parsed.doi)
        doiProvenance = doi == nil ? nil : parsed.doiProvenance
        arxivID = MetadataValidator.normalizedArxivID(parsed.arxivID)
        arxivIDProvenance = arxivID == nil ? nil : parsed.arxivIDProvenance
    }
}

enum PaperInfoReparseDecision: Equatable {
    case keepCurrent
    case useFound
}

struct PaperInfoReparseProposal: Equatable {
    let metadata: PaperInfoReparseMetadata
    let current: PaperInfoDraft
    let fields: [PaperInfoMetadataField]
    let acceptedMetadataAtStart: [PaperInfoMetadataField: PaperInfoReparseMetadata]
    let currentProvenance: [PaperInfoMetadataField: MetadataProvenance]
    let currentAuthorProvenance: [UUID: MetadataProvenance]
    var decisions: [PaperInfoMetadataField: PaperInfoReparseDecision] = [:]

    var remainingFields: [PaperInfoMetadataField] {
        fields.filter { decisions[$0] == nil }
    }

    init(
        parsed: ParsedPaperMetadata,
        current: PaperInfoDraft,
        acceptedMetadataAtStart: [PaperInfoMetadataField: PaperInfoReparseMetadata],
        currentProvenance: [PaperInfoMetadataField: MetadataProvenance],
        currentAuthorProvenance: [UUID: MetadataProvenance]
    ) {
        let metadata = PaperInfoReparseMetadata(parsed: parsed)
        self.metadata = metadata
        self.current = current
        self.acceptedMetadataAtStart = acceptedMetadataAtStart
        self.currentProvenance = currentProvenance
        self.currentAuthorProvenance = currentAuthorProvenance
        fields = PaperInfoMetadataField.allCases.filter { field in
            switch field {
            case .title:
                MetadataValidator.usableTitle(metadata.title) != nil
                    && PaperInfoMetadataNormalization.title(metadata.title)
                        != PaperInfoMetadataNormalization.title(current.title)
            case .authorCredits:
                !metadata.authorCredits.isEmpty
                    && metadata.authorCredits.allSatisfy(PaperInfoMetadataNormalization.validAuthor)
                    && PaperInfoMetadataNormalization.authors(metadata.authorCredits)
                        != PaperInfoMetadataNormalization.authors(current.authorCredits)
            case .publicationYear:
                metadata.publicationYearProvenance != nil
                    && metadata.publicationYear != nil
                    && MetadataValidator.validPublicationYear(metadata.publicationYear)
                    && metadata.publicationYear.map(String.init)
                        != PaperInfoMetadataNormalization.trimmed(current.publicationYearText)
            case .doi:
                metadata.doiProvenance != nil
                    && metadata.doi != nil
                    && metadata.doi != MetadataValidator.normalizedDOI(current.doi)
            case .arxivID:
                metadata.arxivIDProvenance != nil
                    && metadata.arxivID != nil
                    && metadata.arxivID != MetadataValidator.normalizedArxivID(current.arxivID)
            }
        }
    }

    func decision(for field: PaperInfoMetadataField) -> PaperInfoReparseDecision? {
        decisions[field]
    }
}

enum PaperInfoReparseState: Equatable {
    case idle
    case loading(requestID: UUID)
    case reviewing(PaperInfoReparseProposal)
}

enum PaperInfoMetadataNormalization {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func title(_ value: String) -> String {
        trimmed(value)
    }

    static func author(_ author: PaperInfoAuthorCreditDraft) -> [String] {
        normalizedAuthor(displayName: author.displayName, familyName: author.familyName)
    }

    static func author(_ author: AuthorCreditSnapshot) -> [String] {
        normalizedAuthor(displayName: author.displayName, familyName: author.familyName)
    }

    static func author(_ author: PaperInfoReparseAuthorCredit) -> [String] {
        normalizedAuthor(displayName: author.displayName, familyName: author.familyName)
    }

    static func authors(_ authors: [PaperInfoAuthorCreditDraft]) -> [[String]] {
        authors.map(author)
    }

    static func authors(_ authors: [PaperInfoReparseAuthorCredit]) -> [[String]] {
        authors.map(author)
    }

    static func validAuthor(_ author: PaperInfoReparseAuthorCredit) -> Bool {
        let values = self.author(author)
        return values.allSatisfy { !$0.isEmpty }
    }

    private static func normalizedAuthor(displayName: String, familyName: String) -> [String] {
        [trimmed(displayName), trimmed(familyName)]
    }
}
