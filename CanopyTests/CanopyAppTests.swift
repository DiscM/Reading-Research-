import CanopyCore
import Foundation
import Testing
@testable import Canopy

@Suite("Canopy app scaffold")
struct CanopyAppTests {
    @Test("baseline test target loads")
    func targetLoads() {
        #expect(Bool(true))
    }

    @Test("Paper commands disable find navigation until the reader has matches")
    func paperCommandAvailability() {
        let withoutMatches = PaperCommand.availableReaderCommands(hasFindMatches: false)
        let withMatches = PaperCommand.availableReaderCommands(hasFindMatches: true)

        #expect(withoutMatches.contains(.focusFind))
        #expect(withoutMatches.contains(.zoomIn))
        #expect(withoutMatches.contains(.toggleAnnotations))
        #expect(!withoutMatches.contains(.nextFindMatch))
        #expect(!withoutMatches.contains(.previousFindMatch))
        #expect(withMatches.contains(.nextFindMatch))
        #expect(withMatches.contains(.previousFindMatch))
    }

    @Test("highlight appearance strengthens contrast and provides non-color symbols")
    func highlightAppearancePreferences() {
        let standard = HighlightAppearancePreferences(increasedContrast: false)
        let increased = HighlightAppearancePreferences(increasedContrast: true)

        #expect(increased.overlayOpacity > standard.overlayOpacity)
        #expect(increased.inspectorFillOpacity > standard.inspectorFillOpacity)
        #expect(increased.selectedPaletteFillOpacity > standard.selectedPaletteFillOpacity)
        #expect(increased.unselectedPaletteFillOpacity > standard.unselectedPaletteFillOpacity)
        #expect(increased.swatchBorderWidth > standard.swatchBorderWidth)
        #expect(increased.selectedBorderWidth > standard.selectedBorderWidth)
        let nonColorSymbols = HighlightColor.allCases.map(\.differentiateWithoutColorSymbol)
        #expect(Set(nonColorSymbols).count == HighlightColor.allCases.count)
    }

    @MainActor
    @Test("selected and dropped PDFs converge on the shared Add Batch sheet")
    func sharedAddBatchEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = directory.appendingPathComponent("paper.pdf")
        try Data("fixture".utf8).write(to: pdf)
        let workflow = AddPapersWorkflow()

        workflow.prepare(urls: [pdf])

        #expect(workflow.pendingURLs == [pdf])
        #expect(workflow.storageChoice == .referenced)
        #expect(workflow.isStorageChoicePresented)
    }

    @Test("source recovery actions match each library source state")
    func sourceRecoveryActionsMatchState() {
        #expect(SourceRecoveryAction.actions(for: .available) == [])
        #expect(SourceRecoveryAction.actions(for: .sourceUnavailable) == [.retry])
        #expect(SourceRecoveryAction.actions(for: .brokenReference) == [.repairReference, .removeFromLibrary])
        #expect(SourceRecoveryAction.actions(for: .sourceChanged) == [
            .locateOriginal,
            .addChangedAsSeparate,
            .removeFromLibrary
        ])
        #expect(SourceRecoveryAction.actions(for: .libraryCopyMissing) == [
            .restoreLibraryCopy,
            .removeFromLibrary
        ])
    }

    @MainActor
    @Test("source recovery workflow restores a selected exact managed copy")
    func sourceRecoveryWorkflowRestoresManagedCopy() async throws {
        let selectedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: selectedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: selectedDirectory) }
        let selectedURL = selectedDirectory.appendingPathComponent("selected.pdf")
        try Data("recover-this-source".utf8).write(to: selectedURL)
        let managedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: managedDirectory) }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: selectedURL),
            title: "Recover Me",
            storageMode: .managedCopy,
            sourceState: .libraryCopyMissing,
            managedRelativePath: "managed.pdf",
            sourceFilename: "managed.pdf",
            sourceFileSize: 0
        )
        try repository.insert(paper)
        let workflow = SourceRecoveryWorkflow()
        workflow.begin(for: paper)

        let recoveredPaperID = try await workflow.recover(
            from: selectedURL,
            repository: repository,
            managedStore: ManagedPaperStore(rootURL: managedDirectory)
        )

        #expect(recoveredPaperID == paper.id)
        #expect(paper.sourceState == .available)
        #expect(FileManager.default.fileExists(
            atPath: managedDirectory.appendingPathComponent("managed.pdf").path
        ))
    }

    @MainActor
    @Test("recent Papers appear above the remaining title-sorted Library without duplication")
    func recentAndLibrarySections() {
        let olderRecent = makePaper(
            title: "Older Recent",
            dateAdded: Date(timeIntervalSince1970: 10),
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let newerRecent = makePaper(
            title: "Newer Recent",
            dateAdded: Date(timeIntervalSince1970: 20),
            lastOpenedAt: Date(timeIntervalSince1970: 200)
        )
        let zulu = makePaper(title: "Zulu", dateAdded: Date(timeIntervalSince1970: 40))
        let alpha = makePaper(title: "Alpha", dateAdded: Date(timeIntervalSince1970: 30))

        let contents = LibraryContents(
            papers: [olderRecent, zulu, newerRecent, alpha],
            searchText: "",
            sortOrder: .title
        )

        #expect(contents.recent.map(\.id) == [newerRecent.id, olderRecent.id])
        #expect(contents.library.map(\.id) == [alpha.id, zulu.id])
        #expect(Set((contents.recent + contents.library).map(\.id)).count == 4)
    }

    @MainActor
    @Test("Date Added sorting shows the newest remaining Paper first")
    func dateAddedLibrarySort() {
        let oldest = makePaper(title: "Alpha", dateAdded: Date(timeIntervalSince1970: 10))
        let newest = makePaper(title: "Zulu", dateAdded: Date(timeIntervalSince1970: 30))
        let middle = makePaper(title: "Beta", dateAdded: Date(timeIntervalSince1970: 20))

        let contents = LibraryContents(
            papers: [oldest, newest, middle],
            searchText: "",
            sortOrder: .dateAdded
        )

        #expect(contents.library.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @MainActor
    @Test("search ranks title before author or year, then note, preserving the selected sort within a tier")
    func rankedLibrarySearch() {
        let olderTitleMatch = makePaper(
            title: "2026 Overview",
            dateAdded: Date(timeIntervalSince1970: 10)
        )
        let newerTitleMatch = makePaper(
            title: "2026 Review",
            dateAdded: Date(timeIntervalSince1970: 40)
        )
        let authorMatch = makePaper(
            title: "Alpha",
            dateAdded: Date(timeIntervalSince1970: 50),
            author: "Research 2026"
        )
        let yearMatch = makePaper(
            title: "Beta",
            dateAdded: Date(timeIntervalSince1970: 45),
            publicationYear: 2026
        )
        let noteMatch = makePaper(
            title: "Gamma",
            dateAdded: Date(timeIntervalSince1970: 60),
            note: "Questions for 2026"
        )
        let noMatch = makePaper(
            title: "Delta",
            dateAdded: Date(timeIntervalSince1970: 70),
            author: "Other Author",
            publicationYear: 2025,
            note: "Nothing relevant"
        )

        let contents = LibraryContents(
            papers: [olderTitleMatch, authorMatch, noteMatch, noMatch, yearMatch, newerTitleMatch],
            searchText: "2026",
            sortOrder: .dateAdded
        )

        let resultIDs = contents.library.map(\.id)
        let expectedIDs = [
            newerTitleMatch.id,
            olderTitleMatch.id,
            authorMatch.id,
            yearMatch.id,
            noteMatch.id
        ]
        #expect(resultIDs == expectedIDs)
    }

    @MainActor
    @Test("clearing Recent History keeps every Paper in the Library")
    func clearRecentHistoryKeepsPapers() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let recent = makePaper(
            title: "Recently Opened",
            dateAdded: Date(timeIntervalSince1970: 10),
            lastOpenedAt: Date(timeIntervalSince1970: 100)
        )
        let neverOpened = makePaper(
            title: "Never Opened",
            dateAdded: Date(timeIntervalSince1970: 20)
        )
        try repository.insert(recent)
        try repository.insert(neverOpened)

        try repository.clearRecentHistory()
        let contents = LibraryContents(
            papers: [recent, neverOpened],
            searchText: "",
            sortOrder: .title
        )

        #expect(contents.recent.isEmpty)
        #expect(contents.library.map(\.id) == [neverOpened.id, recent.id])
        #expect(try repository.paper(id: recent.id) != nil)
        #expect(try repository.paper(id: neverOpened.id) != nil)
    }

    @Test("Paper Info keeps invalid year text visible and blocks it from becoming an update")
    func paperInfoDraftRejectsInvalidYear() {
        let draft = PaperInfoDraft(
            title: "A Paper",
            publicationYearText: "twenty six",
            doi: "",
            arxivID: ""
        )

        #expect(throws: PaperInfoDraftError.invalidPublicationYear) {
            _ = try draft.makeUpdate()
        }
    }

    @Test("Paper Info converts blank optional fields to nil")
    func paperInfoDraftClearsOptionalFields() throws {
        let draft = PaperInfoDraft(
            title: "A Paper",
            publicationYearText: "   ",
            doi: "  ",
            arxivID: ""
        )

        let update = try draft.makeUpdate()

        #expect(update.publicationYear == nil)
        #expect(update.doi == nil)
        #expect(update.arxivID == nil)
    }

    @Test("Paper Info stages ordered Author Credit edits and preserves family-name corrections")
    func paperInfoDraftStagesAuthorCredits() throws {
        let firstAuthorID = UUID()
        let removedAuthorID = UUID()
        let addedAuthorID = UUID()
        let snapshot = PaperInfoSnapshot(
            paperID: UUID(),
            title: "A Paper",
            titleProvenance: .firstPage,
            publicationYear: nil,
            publicationYearProvenance: nil,
            doi: nil,
            doiProvenance: nil,
            arxivID: nil,
            arxivIDProvenance: nil,
            authorCredits: [
                AuthorCreditSnapshot(
                    id: firstAuthorID,
                    position: 0,
                    displayName: "Ada Byron",
                    familyName: "Byron",
                    provenance: .firstPage
                ),
                AuthorCreditSnapshot(
                    id: removedAuthorID,
                    position: 1,
                    displayName: "Remove Me",
                    familyName: "Me",
                    provenance: .embeddedMetadata
                )
            ]
        )
        var draft = PaperInfoDraft(snapshot: snapshot)

        draft.updateAuthorDisplayName(id: firstAuthorID, displayName: "Ada Lovelace")
        #expect(draft.authorCredits[0].familyName == "Lovelace")
        draft.updateAuthorFamilyName(id: firstAuthorID, familyName: "Byron King")
        draft.updateAuthorDisplayName(id: firstAuthorID, displayName: "Augusta Ada King")
        draft.removeAuthorCredit(id: removedAuthorID)
        draft.addAuthorCredit(id: addedAuthorID)
        draft.updateAuthorDisplayName(id: addedAuthorID, displayName: "Grace Hopper")
        draft.moveAuthorCredit(id: addedAuthorID, toInsertionIndex: 0)

        let update = try draft.makeUpdate()
        let authors = update.authorCredits
        #expect(authors.map(\.id) == [addedAuthorID, firstAuthorID])
        #expect(authors.map(\.displayName) == ["Grace Hopper", "Augusta Ada King"])
        #expect(authors.map(\.familyName) == ["Hopper", "Byron King"])
    }

    @Test("Paper Info moves Author Credits by arbitrary offsets without disturbing intervening rows")
    func paperInfoDraftMovesAuthorCreditsByOffset() {
        let firstAuthorID = UUID()
        let secondAuthorID = UUID()
        let thirdAuthorID = UUID()
        var draft = PaperInfoDraft(authorCredits: [
            PaperInfoAuthorCreditDraft(id: firstAuthorID, displayName: "First Author", familyName: "Author"),
            PaperInfoAuthorCreditDraft(id: secondAuthorID, displayName: "Second Author", familyName: "Author"),
            PaperInfoAuthorCreditDraft(id: thirdAuthorID, displayName: "Third Author", familyName: "Author")
        ])

        draft.moveAuthorCredit(id: firstAuthorID, by: 2)

        #expect(draft.authorCredits.map(\.id) == [secondAuthorID, thirdAuthorID, firstAuthorID])
    }

    @MainActor
    @Test("Paper Info Cancel discards every staged Author Credit operation")
    func paperInfoCancelDiscardsAuthorCreditChanges() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let authorID = UUID()
        let paper = Paper(
            fingerprint: Data(repeating: 21, count: 32),
            title: "Staged Authors",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "staged-authors.pdf",
            sourceFileSize: 100,
            authorCredits: [
                AuthorCredit(
                    id: authorID,
                    position: 0,
                    displayName: "Ada Byron",
                    familyName: "Byron",
                    provenance: .firstPage
                )
            ]
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)

        workflow.draft.updateAuthorDisplayName(id: authorID, displayName: "Ada Lovelace")
        let addedAuthorID = UUID()
        workflow.draft.addAuthorCredit(id: addedAuthorID)
        workflow.draft.updateAuthorDisplayName(id: addedAuthorID, displayName: "Grace Hopper")
        workflow.draft.moveAuthorCredit(id: authorID, toInsertionIndex: 2)
        workflow.draft.removeAuthorCredit(id: addedAuthorID)
        #expect(workflow.hasChanges)
        workflow.dismiss()

        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
    }

    @MainActor
    @Test("Paper Info Save participates in native Undo and Redo with provenance")
    func paperInfoUndoRedo() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let retainedAuthorID = UUID()
        let removedAuthorID = UUID()
        let addedAuthorID = UUID()
        let paper = Paper(
            fingerprint: Data(repeating: 15, count: 32),
            title: "Inferred Title",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "info.pdf",
            sourceFileSize: 100,
            authorCredits: [
                AuthorCredit(
                    id: retainedAuthorID,
                    position: 0,
                    displayName: "Ada Byron",
                    familyName: "Byron",
                    provenance: .firstPage
                ),
                AuthorCredit(
                    id: removedAuthorID,
                    position: 1,
                    displayName: "Remove Me",
                    familyName: "Me",
                    provenance: .embeddedMetadata
                )
            ]
        )
        try repository.insert(paper)
        let change = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "Edited Title",
                publicationYear: 2026,
                doi: nil,
                arxivID: nil,
                authorCredits: [
                    AuthorCreditUpdate(
                        id: addedAuthorID,
                        displayName: "Grace Hopper",
                        familyName: "Hopper"
                    ),
                    AuthorCreditUpdate(
                        id: retainedAuthorID,
                        displayName: "Ada Lovelace",
                        familyName: "Lovelace"
                    )
                ]
            )
        )
        let undoManager = UndoManager()
        let undoTarget = PaperInfoUndoTarget()
        var errors: [Error] = []
        PaperInfoUndo.register(
            change: change,
            repository: repository,
            target: undoTarget,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        let undone = try repository.paperInfoSnapshot(paperID: paper.id)
        #expect(undone.title == "Inferred Title")
        #expect(undone.titleProvenance == .firstPage)
        #expect(undone.authorCredits.map(\.id) == [retainedAuthorID, removedAuthorID])
        #expect(undone.authorCredits.map(\.displayName) == ["Ada Byron", "Remove Me"])
        #expect(undone.authorCredits.map(\.provenance) == [.firstPage, .embeddedMetadata])

        undoManager.redo()
        let redone = try repository.paperInfoSnapshot(paperID: paper.id)
        #expect(redone.title == "Edited Title")
        #expect(redone.titleProvenance == .userEntry)
        #expect(redone.authorCredits.map(\.id) == [addedAuthorID, retainedAuthorID])
        #expect(redone.authorCredits.map(\.displayName) == ["Grace Hopper", "Ada Lovelace"])
        #expect(redone.authorCredits.map(\.provenance) == [.userEntry, .userEntry])
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("Reparse Metadata stages only approved replacements and preserves their provenance")
    func reparseMetadataStagesApprovedFields() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 22, count: 32),
            title: "Original Title",
            titleProvenance: .filenameFallback,
            publicationYear: 2024,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/original",
            doiProvenance: .firstPage,
            arxivID: "2401.12345",
            arxivIDProvenance: .embeddedMetadata,
            storageMode: .managedCopy,
            sourceFilename: "reparse.pdf",
            sourceFileSize: 100,
            authorCredits: [
                AuthorCredit(
                    position: 0,
                    displayName: "Ada Original",
                    familyName: "Original",
                    provenance: .firstPage
                )
            ]
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        workflow.draft.doi = "10.2000/manual"

        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "Fresh Title",
            titleProvenance: .embeddedMetadata,
            authors: [
                ParsedAuthorCredit(
                    displayName: "Grace Fresh",
                    familyName: "Fresh",
                    provenance: .embeddedMetadata
                )
            ],
            publicationYear: 2025,
            publicationYearProvenance: .firstPage,
            doi: "10.3000/fresh",
            doiProvenance: .firstPage,
            arxivID: "arXiv: 2401.12345",
            arxivIDProvenance: .firstPage
        ))

        #expect(workflow.reparseProposal?.remainingFields == [
            .title,
            .authorCredits,
            .publicationYear,
            .doi
        ])
        workflow.acceptReparsed(.title)
        workflow.acceptReparsed(.authorCredits)
        workflow.keepCurrent(.publicationYear)
        workflow.keepCurrent(.doi)
        #expect(workflow.reparseProposal?.remainingFields.isEmpty == true)
        workflow.finishReparseReview()

        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
        let target = try workflow.makeTargetSnapshot()
        #expect(target.title == "Fresh Title")
        #expect(target.titleProvenance == .embeddedMetadata)
        #expect(target.publicationYear == 2024)
        #expect(target.publicationYearProvenance == .embeddedMetadata)
        #expect(target.doi == "10.2000/manual")
        #expect(target.doiProvenance == .userEntry)
        #expect(target.arxivID == "2401.12345")
        #expect(target.arxivIDProvenance == .embeddedMetadata)
        #expect(target.authorCredits.map(\.displayName) == ["Grace Fresh"])
        #expect(target.authorCredits.map(\.provenance) == [.embeddedMetadata])
        #expect(workflow.reparseProposal == nil)

        let change = try repository.applyPaperInfoSnapshot(target)
        let undoManager = UndoManager()
        let undoTarget = PaperInfoUndoTarget()
        var errors: [Error] = []
        PaperInfoUndo.register(
            change: change,
            repository: repository,
            target: undoTarget,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )
        undoManager.undo()
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
        undoManager.redo()
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == change.after)
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("Accepted reparse values keep fresh provenance even when they equal stored values")
    func acceptedReparseValuesPreferFreshProvenance() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 27, count: 32),
            title: "Stored Title",
            titleProvenance: .filenameFallback,
            publicationYear: 2024,
            publicationYearProvenance: .embeddedMetadata,
            doi: "10.1000/stored",
            doiProvenance: .embeddedMetadata,
            arxivID: "2401.12345",
            arxivIDProvenance: .embeddedMetadata,
            storageMode: .managedCopy,
            sourceFilename: "fresh-provenance.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        workflow.draft.title = "Manual Title"
        workflow.draft.publicationYearText = "2025"
        workflow.draft.doi = "10.2000/manual"
        workflow.draft.arxivID = "2501.12345"

        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "Stored Title",
            titleProvenance: .embeddedMetadata,
            publicationYear: 2024,
            publicationYearProvenance: .firstPage,
            doi: "https://doi.org/10.1000/stored",
            doiProvenance: .firstPage,
            arxivID: "arXiv: 2401.12345",
            arxivIDProvenance: .firstPage
        ))
        for field in [
            PaperInfoMetadataField.title,
            .publicationYear,
            .doi,
            .arxivID
        ] {
            workflow.acceptReparsed(field)
        }

        let target = try workflow.makeTargetSnapshot()
        #expect(target.titleProvenance == .embeddedMetadata)
        #expect(target.publicationYearProvenance == .firstPage)
        #expect(target.doiProvenance == .firstPage)
        #expect(target.arxivIDProvenance == .firstPage)
    }

    @MainActor
    @Test("Reparse Metadata decisions remain reversible until review finishes")
    func reparseMetadataDecisionsRemainReversible() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 24, count: 32),
            title: "Original Title",
            titleProvenance: .filenameFallback,
            publicationYear: 2024,
            publicationYearProvenance: .embeddedMetadata,
            storageMode: .managedCopy,
            sourceFilename: "reversible.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "Fresh Title",
            titleProvenance: .firstPage,
            publicationYear: 2025,
            publicationYearProvenance: .firstPage
        ))

        workflow.acceptReparsed(.title)
        workflow.keepCurrent(.title)

        var target = try workflow.makeTargetSnapshot()
        #expect(target.title == "Original Title")
        #expect(target.titleProvenance == .filenameFallback)

        workflow.acceptReparsed(.title)
        workflow.discardReparseResults()

        target = try workflow.makeTargetSnapshot()
        #expect(target.title == "Original Title")
        #expect(target.titleProvenance == .filenameFallback)
        #expect(workflow.reparseProposal == nil)
    }

    @MainActor
    @Test("Paper Info reports malformed identifiers through their field validation")
    func paperInfoReportsMalformedIdentifiers() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 25, count: 32),
            title: "Identifier Validation",
            storageMode: .managedCopy,
            sourceFilename: "identifiers.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)

        workflow.draft.doi = "not a DOI"
        var target = try workflow.makeTargetSnapshot()
        #expect(target.doiProvenance == .userEntry)
        #expect(throws: LibraryRepositoryError.invalidDOI) {
            _ = try repository.applyPaperInfoSnapshot(target)
        }

        workflow.draft.doi = ""
        workflow.draft.arxivID = "not an arXiv ID"
        target = try workflow.makeTargetSnapshot()
        #expect(target.arxivIDProvenance == .userEntry)
        #expect(throws: LibraryRepositoryError.invalidArxivID) {
            _ = try repository.applyPaperInfoSnapshot(target)
        }
    }

    @MainActor
    @Test("Reparse Metadata does not offer an unusable title")
    func reparseMetadataRejectsUnusableTitle() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 26, count: 32),
            title: "Usable Existing Title",
            storageMode: .managedCopy,
            sourceFilename: "title.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)

        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "untitled",
            titleProvenance: .filenameFallback
        ))

        #expect(workflow.reparseProposal == nil)
        #expect(workflow.reparseMessage == "No different usable metadata was found.")
    }

    @MainActor
    @Test("Reparse Metadata rejects malformed parsed field values")
    func reparseMetadataRejectsMalformedFields() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 28, count: 32),
            title: "Validated Metadata",
            publicationYear: 2024,
            publicationYearProvenance: .userEntry,
            doi: "10.1000/current",
            doiProvenance: .userEntry,
            arxivID: "2401.12345",
            arxivIDProvenance: .userEntry,
            storageMode: .managedCopy,
            sourceFilename: "validation.pdf",
            sourceFileSize: 100,
            authorCredits: [
                AuthorCredit(
                    position: 0,
                    displayName: "Valid Author",
                    familyName: "Author",
                    provenance: .userEntry
                )
            ]
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)

        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "Validated Metadata",
            titleProvenance: .embeddedMetadata,
            authors: [
                ParsedAuthorCredit(
                    displayName: "   ",
                    familyName: "Author",
                    provenance: .firstPage
                )
            ],
            publicationYear: 999,
            publicationYearProvenance: .firstPage,
            doi: "not a DOI",
            doiProvenance: .firstPage,
            arxivID: "not an arXiv ID",
            arxivIDProvenance: .firstPage
        ))

        #expect(workflow.reparseProposal == nil)
        #expect(workflow.reparseMessage == "No different usable metadata was found.")
    }

    @MainActor
    @Test("Reparse Metadata can replace malformed staged year text")
    func reparseMetadataCanCorrectMalformedStagedYear() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 29, count: 32),
            title: "Year Correction",
            storageMode: .managedCopy,
            sourceFilename: "year.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        workflow.draft.publicationYearText = "02025"

        workflow.reviewReparsedMetadata(ParsedPaperMetadata(
            title: "Year Correction",
            titleProvenance: .embeddedMetadata,
            publicationYear: 2025,
            publicationYearProvenance: .firstPage
        ))

        #expect(workflow.reparseProposal?.remainingFields == [.publicationYear])
        workflow.acceptReparsed(.publicationYear)
        #expect(workflow.draft.publicationYearText == "2025")
    }

    @MainActor
    @Test("Reparse Metadata rereads a verified managed Source PDF")
    func reparseMetadataReadsVerifiedSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let relativePath = "verified-reparse.pdf"
        let sourceURL = directory.appendingPathComponent(relativePath)
        try Data("verified-source".utf8).write(to: sourceURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let modificationDate = try #require(attributes[.modificationDate] as? Date)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: sourceURL),
            title: "Original Title",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: relativePath,
            sourceFileSize: 15,
            sourceModificationDate: modificationDate
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        let parsed = ParsedPaperMetadata(
            title: "Fresh Verified Title",
            titleProvenance: .firstPage
        )

        await workflow.reparse(
            repository: repository,
            analyzer: StubDocumentAnalyzer(metadata: parsed),
            managedStore: ManagedPaperStore(rootURL: directory)
        )

        #expect(workflow.reparseProposal?.remainingFields == [.title])
        #expect(workflow.reparseProposal?.metadata.title == "Fresh Verified Title")
        #expect(workflow.reparseErrorMessage == nil)
        #expect(paper.sourceState == .available)
    }

    @MainActor
    @Test("Reparse Metadata rejects a Source PDF that changes during analysis")
    func reparseMetadataRejectsSourceChangedDuringAnalysis() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalData = Data("stable-source".utf8)
        let relativePath = "changing-reparse.pdf"
        let sourceURL = directory.appendingPathComponent(relativePath)
        try originalData.write(to: sourceURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let modificationDate = try #require(attributes[.modificationDate] as? Date)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: sourceURL),
            title: "Stable Metadata",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: relativePath,
            sourceFileSize: Int64(originalData.count),
            sourceModificationDate: modificationDate
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        let draftBeforeReparse = workflow.draft

        await workflow.reparse(
            repository: repository,
            analyzer: SourceMutatingDocumentAnalyzer(
                replacementData: Data("different-source-bytes".utf8),
                metadata: ParsedPaperMetadata(
                    title: "Untrusted Fresh Title",
                    titleProvenance: .firstPage
                )
            ),
            managedStore: ManagedPaperStore(rootURL: directory)
        )

        #expect(workflow.draft == draftBeforeReparse)
        #expect(workflow.reparseProposal == nil)
        #expect(workflow.reparseErrorMessage?.contains("no longer matches") == true)
        #expect(paper.sourceState == .sourceChanged)
    }

    @MainActor
    @Test("Dismissing Paper Info cancels active metadata analysis")
    func dismissingPaperInfoCancelsMetadataAnalysis() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let relativePath = "cancel-reparse.pdf"
        let sourceURL = directory.appendingPathComponent(relativePath)
        try Data("cancel-reparse".utf8).write(to: sourceURL)
        let managedStore = ManagedPaperStore(rootURL: directory)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: sourceURL),
            title: "Cancel Reparse",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: relativePath,
            sourceFileSize: 14
        )
        try repository.insert(paper)
        let before = try repository.paperInfoSnapshot(paperID: paper.id)
        let probe = CancellationProbe()
        let analyzer = CancellationObservingDocumentAnalyzer(probe: probe)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)

        let reparse = Task { @MainActor in
            await workflow.reparse(
                repository: repository,
                analyzer: analyzer,
                managedStore: managedStore
            )
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !probe.hasStarted, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(probe.hasStarted)
        #expect(workflow.isReparsing)

        workflow.dismiss()
        await reparse.value

        #expect(probe.observedCancellation)
        #expect(!workflow.isPresented)
        #expect(workflow.paperID == nil)
        #expect(!workflow.isReparsing)
        #expect(workflow.reparseProposal == nil)
        #expect(workflow.reparseErrorMessage == nil)
        #expect(workflow.reparseMessage == nil)
        #expect(workflow.draft == PaperInfoDraft())
        #expect(try repository.paperInfoSnapshot(paperID: paper.id) == before)
    }

    @MainActor
    @Test("Reparse Metadata blocks a missing managed Source PDF without changing the draft")
    func reparseMetadataBlocksMissingManagedSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 23, count: 32),
            title: "Keep This Draft",
            storageMode: .managedCopy,
            managedRelativePath: "missing.pdf",
            sourceFilename: "missing.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let workflow = PaperInfoWorkflow()
        try workflow.present(paperID: paper.id, repository: repository)
        let draftBeforeReparse = workflow.draft

        await workflow.reparse(
            repository: repository,
            analyzer: StubDocumentAnalyzer(metadata: ParsedPaperMetadata(
                title: "Should Not Be Used",
                titleProvenance: .embeddedMetadata
            )),
            managedStore: ManagedPaperStore(rootURL: directory)
        )

        #expect(workflow.draft == draftBeforeReparse)
        #expect(workflow.reparseProposal == nil)
        #expect(workflow.reparseErrorMessage?.contains("Restore the missing") == true)
        #expect(paper.sourceState == .libraryCopyMissing)
    }

    @MainActor
    @Test("removing a managed Paper participates in native Undo and Redo")
    func paperRemovalUndoRedo() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let relativePath = "undo-removal.pdf"
        let sourceURL = directory.appendingPathComponent(relativePath)
        try Data("undo-removal".utf8).write(to: sourceURL)
        let managedStore = ManagedPaperStore(rootURL: directory)
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: sourceURL),
            title: "Undo Removal",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: relativePath,
            sourceFileSize: 12
        )
        try repository.insert(paper)
        let snapshot = try repository.removePaper(paperID: paper.id, managedStore: managedStore)
        let undoManager = UndoManager()
        let undoTarget = PaperRemovalUndoTarget()
        var errors: [Error] = []
        PaperRemovalUndo.register(
            snapshot: snapshot,
            repository: repository,
            managedStore: managedStore,
            target: undoTarget,
            undoManager: undoManager,
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.paper(id: paper.id) != nil)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))

        undoManager.redo()
        #expect(try repository.paper(id: paper.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(errors.isEmpty)
    }

    @MainActor
    @Test("annotation creation participates in native Undo and Redo")
    func annotationCreationUndoRedo() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 6, count: 32),
            title: "Undoable Paper",
            storageMode: .managedCopy,
            sourceFilename: "undo.pdf",
            sourceFileSize: 100,
            pageCount: 2
        )
        try repository.insert(paper)
        let anchors = [0, 1].map { pageIndex in
            AnnotationAnchor(
                pageIndex: pageIndex,
                quadrilaterals: [
                    AnnotationQuadrilateral(
                        upperLeft: AnnotationPoint(x: 10, y: 50),
                        upperRight: AnnotationPoint(x: 80, y: 50),
                        lowerLeft: AnnotationPoint(x: 10, y: 35),
                        lowerRight: AnnotationPoint(x: 80, y: 35)
                    )
                ],
                selectedText: "Page \(pageIndex + 1) selection"
            )
        }
        let created = try repository.createAnnotations(
            paperID: paper.id,
            anchors: anchors,
            color: .blue
        )
        let undoManager = UndoManager()
        let undoTarget = AnnotationUndoTarget()
        var errors: [Error] = []
        AnnotationUndo.registerUndoForCreation(
            annotationIDs: created.map(\.id),
            repository: repository,
            target: undoTarget,
            undoManager: undoManager,
            onChange: {},
            onError: { errors.append($0) }
        )

        undoManager.undo()
        #expect(try repository.annotations(paperID: paper.id).isEmpty)

        undoManager.redo()
        #expect(try repository.annotations(paperID: paper.id).map(\.selectedText) == [
            "Page 1 selection",
            "Page 2 selection"
        ])
        #expect(errors.isEmpty)
    }

    @MainActor
    private func makePaper(
        title: String,
        dateAdded: Date,
        lastOpenedAt: Date? = nil,
        author: String? = nil,
        publicationYear: Int? = nil,
        note: String? = nil
    ) -> Paper {
        let credits = author.map {
            [AuthorCredit(position: 0, displayName: $0, familyName: $0, provenance: .userEntry)]
        } ?? []
        let paper = Paper(
            fingerprint: Data(UUID().uuidString.utf8),
            title: title,
            publicationYear: publicationYear,
            storageMode: .referenced,
            sourceFilename: "\(title).pdf",
            sourceFileSize: 1,
            dateAdded: dateAdded,
            authorCredits: credits
        )
        paper.lastOpenedAt = lastOpenedAt
        if let note {
            paper.annotations = [
                Annotation(
                    pageIndex: 0,
                    quadrilaterals: Data(),
                    selectedText: "Selection",
                    color: .yellow,
                    note: note,
                    paper: paper
                )
            ]
        }
        return paper
    }
}

private struct StubDocumentAnalyzer: DocumentAnalyzing {
    let metadata: ParsedPaperMetadata

    func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        metadata
    }
}

private struct SourceMutatingDocumentAnalyzer: DocumentAnalyzing {
    let replacementData: Data
    let metadata: ParsedPaperMetadata

    func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        try replacementData.write(to: url)
        return metadata
    }
}

private struct CancellationObservingDocumentAnalyzer: DocumentAnalyzing {
    let probe: CancellationProbe

    func analyze(_ url: URL) throws -> ParsedPaperMetadata {
        probe.markStarted()
        for _ in 0..<1_000 {
            if Task.isCancelled {
                probe.markCancellationObserved()
                break
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return ParsedPaperMetadata(
            title: "Must Never Appear",
            titleProvenance: .firstPage
        )
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancellationObserved = false

    var hasStarted: Bool {
        lock.withLock { started }
    }

    var observedCancellation: Bool {
        lock.withLock { cancellationObserved }
    }

    func markStarted() {
        lock.withLock { started = true }
    }

    func markCancellationObserved() {
        lock.withLock { cancellationObserved = true }
    }
}
