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

    @MainActor
    @Test("Paper Info Save participates in native Undo and Redo with provenance")
    func paperInfoUndoRedo() throws {
        let container = try CanopyModelContainer.make(inMemory: true)
        let repository = LibraryRepository(container: container)
        let paper = Paper(
            fingerprint: Data(repeating: 15, count: 32),
            title: "Inferred Title",
            titleProvenance: .firstPage,
            storageMode: .referenced,
            sourceFilename: "info.pdf",
            sourceFileSize: 100
        )
        try repository.insert(paper)
        let change = try repository.updatePaperInfo(
            paperID: paper.id,
            update: PaperInfoUpdate(
                title: "Edited Title",
                publicationYear: 2026,
                doi: nil,
                arxivID: nil
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
        #expect(paper.title == "Inferred Title")
        #expect(paper.titleProvenance == .firstPage)

        undoManager.redo()
        #expect(paper.title == "Edited Title")
        #expect(paper.titleProvenance == .userEntry)
        #expect(errors.isEmpty)
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
