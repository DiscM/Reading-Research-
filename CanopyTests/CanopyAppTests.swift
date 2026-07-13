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
}
