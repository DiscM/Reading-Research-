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
}
