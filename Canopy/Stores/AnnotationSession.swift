import CanopyCore
import Foundation
import Observation

@MainActor
@Observable
final class AnnotationSession {
    private(set) var paperID: UUID?
    private(set) var isSourceVerified = false
    private(set) var annotations: [Annotation] = []
    private(set) var loadErrorMessage: String?
    private(set) var verificationErrorMessage: String?

    func beginVerification(paperID: UUID?) {
        self.paperID = paperID
        isSourceVerified = false
        annotations = []
        loadErrorMessage = nil
        verificationErrorMessage = nil
    }

    func sourceVerified(paperID: UUID, repository: LibraryRepository) {
        guard self.paperID == paperID else { return }
        isSourceVerified = true
        verificationErrorMessage = nil
        reload(repository: repository)
    }

    func verificationFailed(paperID: UUID, message: String) {
        guard self.paperID == paperID else { return }
        isSourceVerified = false
        annotations = []
        loadErrorMessage = nil
        verificationErrorMessage = message
    }

    func reload(repository: LibraryRepository) {
        guard isSourceVerified, let paperID else { return }
        do {
            annotations = try repository.annotations(paperID: paperID)
            loadErrorMessage = nil
        } catch {
            annotations = []
            loadErrorMessage = error.localizedDescription
        }
    }
}
