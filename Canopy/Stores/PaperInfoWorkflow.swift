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

    init(
        title: String = "",
        publicationYearText: String = "",
        doi: String = "",
        arxivID: String = ""
    ) {
        self.title = title
        self.publicationYearText = publicationYearText
        self.doi = doi
        self.arxivID = arxivID
    }

    init(snapshot: PaperInfoSnapshot) {
        self.init(
            title: snapshot.title,
            publicationYearText: snapshot.publicationYear.map(String.init) ?? "",
            doi: snapshot.doi ?? "",
            arxivID: snapshot.arxivID ?? ""
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
            arxivID: optionalNonempty(arxivID)
        )
    }

    private func optionalNonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PaperInfoReadOnlyDetails: Equatable {
    struct Author: Equatable, Identifiable {
        let id: UUID
        let position: Int
        let displayName: String
        let provenance: MetadataProvenance
    }

    let authors: [Author]
    let sourceStatus: String
    let storage: String
    let sourceFilename: String
    let sourceLocation: String

    init(paper: Paper) {
        authors = paper.authorCredits
            .sorted { $0.position < $1.position }
            .map {
                Author(
                    id: $0.id,
                    position: $0.position,
                    displayName: $0.displayName,
                    provenance: $0.provenance
                )
            }
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

    var hasChanges: Bool {
        guard let originalSnapshot else { return false }
        return draft != PaperInfoDraft(snapshot: originalSnapshot)
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
        isPresented = true
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
    }
}
