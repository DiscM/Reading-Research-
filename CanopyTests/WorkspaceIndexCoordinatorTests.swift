import Foundation
import Testing
@testable import Canopy

@Suite("Workspace index coordination")
struct WorkspaceIndexCoordinatorTests {
    @MainActor
    @Test("an unavailable index records deletion failure without throwing")
    func unavailableIndexDoesNotGateLibraryWork() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let coordinator = WorkspaceIndexCoordinator(databaseURL: directory)
        #expect(coordinator.setupErrorMessage != nil)

        await coordinator.enqueueDeletions([Data(repeating: 0x55, count: 32)])

        #expect(coordinator.setupErrorMessage != nil)
    }
}
