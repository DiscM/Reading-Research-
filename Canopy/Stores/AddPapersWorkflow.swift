import AppKit
import CanopyCore
import Foundation
import Observation

enum AddBatchStorageChoice: String, CaseIterable, Identifiable {
    case referenced
    case managedCopy

    var id: Self { self }
    var title: String { self == .referenced ? "Reference Originals" : "Keep Copies in Canopy" }
    var detail: String {
        self == .referenced
            ? "Use the PDFs from their current locations."
            : "Copy the PDFs into Canopy's managed library."
    }
}

enum PotentialDuplicateDecision: String {
    case addAsSeparate
    case keepExisting
}

struct AddBatchSummaryItem: Identifiable {
    enum Kind { case duplicate, skipped, failure }
    enum Action {
        case repair(UUID, PreflightCandidate)
        case relocate(UUID, PreflightCandidate)
        case openExisting(UUID)
        case reveal(String)

        var title: String {
            switch self {
            case .repair: "Repair Existing Paper"
            case .relocate: "Use New Location"
            case .openExisting: "Open Existing Paper"
            case .reveal: "Reveal Current Source"
            }
        }
    }
    let id = UUID()
    let kind: Kind
    let filename: String
    var message: String
    let path: String?
    var actions: [Action] = []
}

@Observable
@MainActor
final class AddPapersWorkflow {
    var pendingURLs: [URL] = []
    var storageChoice: AddBatchStorageChoice = .referenced
    var isStorageChoicePresented = false
    var isProgressPresented = false
    var isPotentialReviewPresented = false
    var isSummaryPresented = false
    var progressFraction = 0.0
    var progressPhase = "Checking Papers"
    var progressFilename = ""
    var progressCount = ""
    var potentialDuplicates: [PotentialDuplicate] = []
    var potentialDecisions: [UUID: PotentialDuplicateDecision] = [:]
    var summaryItems: [AddBatchSummaryItem] = []

    private var preflightResult: AddBatchPreflightResult?
    private var securityScopedURLs: [URL] = []

    var totalFileSize: Int64 {
        pendingURLs.reduce(0) { total, url in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let value = attributes[.size] as? NSNumber else { return total }
            return total + value.int64Value
        }
    }

    var allPotentialDecisionsMade: Bool {
        potentialDuplicates.allSatisfy { potentialDecisions[$0.candidate.id] != nil }
    }

    func prepare(urls: [URL]) {
        let pdfs = urls.filter { $0.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame }
        guard !pdfs.isEmpty else { return }
        pendingURLs = Array(NSOrderedSet(array: pdfs).array.compactMap { $0 as? URL })
        storageChoice = .referenced
        isStorageChoicePresented = true
    }

    func start(repository: LibraryRepository) {
        isStorageChoicePresented = false
        isProgressPresented = true
        progressPhase = "Checking Papers"
        progressFraction = 0
        summaryItems = []

        let urls = pendingURLs
        securityScopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        let existing: [PaperIdentitySnapshot]
        do {
            existing = try repository.paperIdentitySnapshots()
        } catch {
            finishWithWorkflowFailure(error)
            return
        }

        Task {
            let workflow = self
            let result = await Task.detached(priority: .userInitiated) {
                AddBatchPreflight(analyzer: PDFDocumentAnalyzer()).run(
                    urls: urls,
                    existingPapers: existing,
                    progress: { update in
                        Task { @MainActor in
                            workflow.progressFraction = update.fractionCompleted * 0.8
                            workflow.progressFilename = update.filename
                            workflow.progressCount = "Processing \(update.fileIndex) of \(update.fileCount)"
                        }
                    }
                )
            }.value
            preflightResult = result
            potentialDuplicates = result.potentialDuplicates
            potentialDecisions = [:]
            if result.potentialDuplicates.isEmpty {
                await commitApprovedCandidates(repository: repository)
            } else {
                isProgressPresented = false
                isPotentialReviewPresented = true
            }
        }
    }

    func chooseAllPotentialDuplicates(addAsSeparate: Bool) {
        for duplicate in potentialDuplicates {
            potentialDecisions[duplicate.candidate.id] = addAsSeparate ? .addAsSeparate : .keepExisting
        }
    }

    func finishPotentialReview(repository: LibraryRepository) {
        guard allPotentialDecisionsMade else { return }
        isPotentialReviewPresented = false
        Task { await commitApprovedCandidates(repository: repository) }
    }

    func cancelPotentialReview() {
        isPotentialReviewPresented = false
        reset()
    }

    func copiedSummaryReport() -> String {
        summaryItems.map { item in
            let path = item.path.map(abbreviatedPath) ?? ""
            return [item.filename, item.message, path].filter { !$0.isEmpty }.joined(separator: " — ")
        }.joined(separator: "\n")
    }

    func performSummaryAction(_ action: AddBatchSummaryItem.Action, itemID: UUID, repository: LibraryRepository) {
        do {
            switch action {
            case let .repair(paperID, candidate), let .relocate(paperID, candidate):
                let bookmark = try SecurityScopedBookmarkService().makeBookmark(for: candidate.url)
                try repository.repairReference(
                    paperID: paperID,
                    fingerprint: candidate.fingerprint,
                    bookmarkData: bookmark,
                    rememberedLocation: candidate.url.path
                )
                if let index = summaryItems.firstIndex(where: { $0.id == itemID }) {
                    summaryItems[index].message = "Source location updated"
                    summaryItems[index].actions = [.openExisting(paperID), .reveal(candidate.url.path)]
                }
            case let .openExisting(paperID):
                NotificationCenter.default.post(name: .openPaperRequested, object: paperID)
                isSummaryPresented = false
                reset()
            case let .reveal(path):
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        } catch {
            if let index = summaryItems.firstIndex(where: { $0.id == itemID }) {
                summaryItems[index].message = error.localizedDescription
            }
        }
    }

    func reset() {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        securityScopedURLs = []
        pendingURLs = []
        preflightResult = nil
        potentialDuplicates = []
        potentialDecisions = [:]
        progressFraction = 0
        progressFilename = ""
        progressCount = ""
    }

    private func commitApprovedCandidates(repository: LibraryRepository) async {
        guard let result = preflightResult else { return }
        progressPhase = "Adding Papers"
        var candidates = result.ready
        candidates.append(contentsOf: result.potentialDuplicates.compactMap {
            potentialDecisions[$0.candidate.id] == .addAsSeparate ? $0.candidate : nil
        })

        appendPreflightExceptions(result)
        let bookmarkService = SecurityScopedBookmarkService()
        let managedStore = try? ManagedPaperStore.applicationSupport()

        for (index, candidate) in candidates.enumerated() {
            progressFilename = candidate.url.lastPathComponent
            progressCount = "Adding \(index + 1) of \(candidates.count)"
            var copiedRelativePath: String?
            do {
                let source: ApprovedPaperSource
                switch storageChoice {
                case .referenced:
                    let bookmark = try bookmarkService.makeBookmark(for: candidate.url)
                    source = .referenced(bookmarkData: bookmark, rememberedLocation: candidate.url.path)
                case .managedCopy:
                    guard let managedStore else { throw PaperFileAccessError.cannotAccessSource }
                    let relativePath = try await Task.detached(priority: .userInitiated) {
                        try managedStore.copy(candidate.url)
                    }.value
                    copiedRelativePath = relativePath
                    source = .managedCopy(relativePath: relativePath)
                }
                try repository.add(candidate, source: source)
            } catch {
                if let copiedRelativePath, let managedStore {
                    try? managedStore.remove(relativePath: copiedRelativePath)
                }
                summaryItems.append(AddBatchSummaryItem(
                    kind: .failure,
                    filename: candidate.url.lastPathComponent,
                    message: error.localizedDescription,
                    path: candidate.url.path
                ))
            }
            progressFraction = 0.8 + (Double(index + 1) / Double(max(candidates.count, 1)) * 0.2)
        }
        appendWithinBatchExactDuplicates(result, repository: repository)

        isProgressPresented = false
        if summaryItems.isEmpty {
            reset()
        } else {
            isSummaryPresented = true
        }
    }

    private func appendPreflightExceptions(_ result: AddBatchPreflightResult) {
        for duplicate in result.exactDuplicates {
            var actions: [AddBatchSummaryItem.Action] = [.openExisting(duplicate.existingPaper.id)]
            if let currentPath = duplicate.existingPaper.rememberedLocation {
                actions.append(.reveal(currentPath))
            }
            if duplicate.existingPaper.storageMode == .referenced {
                if duplicate.existingPaper.sourceState == .brokenReference {
                    actions.insert(.repair(duplicate.existingPaper.id, duplicate.candidate), at: 0)
                } else {
                    actions.insert(.relocate(duplicate.existingPaper.id, duplicate.candidate), at: 0)
                }
            }
            summaryItems.append(AddBatchSummaryItem(
                kind: .duplicate,
                filename: duplicate.candidate.url.lastPathComponent,
                message: "Exact duplicate of \(duplicate.existingPaper.title)",
                path: duplicate.candidate.url.path,
                actions: actions
            ))
        }
        for duplicate in result.potentialDuplicates where potentialDecisions[duplicate.candidate.id] == .keepExisting {
            summaryItems.append(AddBatchSummaryItem(
                kind: .skipped,
                filename: duplicate.candidate.url.lastPathComponent,
                message: "Kept existing Paper",
                path: duplicate.candidate.url.path
            ))
        }
        for failure in result.failures {
            summaryItems.append(AddBatchSummaryItem(
                kind: .failure,
                filename: failure.url.lastPathComponent,
                message: failure.message,
                path: failure.url.path
            ))
        }
    }

    private func appendWithinBatchExactDuplicates(_ result: AddBatchPreflightResult, repository: LibraryRepository) {
        let snapshots = (try? repository.paperIdentitySnapshots()) ?? []
        for duplicate in result.withinBatchExactDuplicates {
            let retainedPaper = snapshots.first { $0.fingerprint == duplicate.retained.fingerprint }
            let actions: [AddBatchSummaryItem.Action]
            if storageChoice == .referenced, let retainedPaper {
                actions = [.relocate(retainedPaper.id, duplicate.duplicate), .openExisting(retainedPaper.id)]
            } else {
                actions = retainedPaper.map { [.openExisting($0.id)] } ?? []
            }
            summaryItems.append(AddBatchSummaryItem(
                kind: .duplicate,
                filename: duplicate.duplicate.url.lastPathComponent,
                message: "Exact duplicate of \(duplicate.retained.url.lastPathComponent)",
                path: duplicate.duplicate.url.path,
                actions: actions
            ))
        }
    }

    private func finishWithWorkflowFailure(_ error: Error) {
        isProgressPresented = false
        summaryItems = [AddBatchSummaryItem(kind: .failure, filename: "Add Papers", message: error.localizedDescription, path: nil)]
        isSummaryPresented = true
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
