import CanopyCore
import Foundation
import Observation

@Observable
@MainActor
final class PaperStorageConversionWorkflow {
    private(set) var isConverting = false
    var errorMessage: String?

    func convertToManagedCopy(
        paperID: UUID,
        repository: LibraryRepository,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) async -> Bool {
        guard !isConverting else { return false }
        isConverting = true
        errorMessage = nil
        defer { isConverting = false }

        do {
            guard let paper = try repository.paper(id: paperID),
                  paper.storageMode == .referenced,
                  paper.sourceState == .available else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
            let expectedFingerprint = paper.fingerprint
            let sourceAccess = try repository.sourceAccess(
                paperID: paperID,
                managedStore: suppliedManagedStore
            )
            let sourceURL = sourceAccess.url
            let managedStore = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
            let relativePath = try await Task.detached(priority: .userInitiated) {
                try managedStore.copyVerified(
                    sourceURL,
                    paperID: paperID,
                    expectedFingerprint: expectedFingerprint
                )
            }.value
            withExtendedLifetime(sourceAccess) {}
            let destination = managedStore.rootURL.appendingPathComponent(relativePath)
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            do {
                try repository.convertReferencedPaperToManagedCopy(
                    paperID: paperID,
                    expectedFingerprint: expectedFingerprint,
                    managedRelativePath: relativePath,
                    fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                    modificationDate: attributes[.modificationDate] as? Date
                )
            } catch {
                try? managedStore.remove(relativePath: relativePath)
                throw error
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func convertToReferenced(
        paperID: UUID,
        destinationURL: URL,
        repository: LibraryRepository,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) async -> Bool {
        guard !isConverting else { return false }
        isConverting = true
        errorMessage = nil
        defer { isConverting = false }

        do {
            guard let paper = try repository.paper(id: paperID),
                  paper.storageMode == .managedCopy,
                  paper.sourceState == .available,
                  let managedRelativePath = paper.managedRelativePath else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
            let expectedFingerprint = paper.fingerprint
            let managedStore = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
            guard !destinationURL.isContained(in: managedStore.rootURL) else {
                throw PaperFileAccessError.cannotAccessSource
            }
            let isAccessingDestination = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessingDestination {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }
            let sourceAccess = try repository.sourceAccess(
                paperID: paperID,
                managedStore: managedStore
            )
            let sourceURL = sourceAccess.url
            let preparedTransfer = try await Task.detached(priority: .userInitiated) {
                try PaperFileTransfer().prepareVerifiedCopy(
                    from: sourceURL,
                    to: destinationURL,
                    expectedFingerprint: expectedFingerprint
                )
            }.value
            withExtendedLifetime(sourceAccess) {}
            var transferCommitted = false
            defer {
                if !transferCommitted {
                    try? preparedTransfer.rollback()
                }
            }
            let verified = try preparedTransfer.publish()
            let bookmark = try SecurityScopedBookmarkService().makeBookmark(for: verified.url)

            guard try managedStore.stageForRecovery(
                relativePath: managedRelativePath,
                paperID: paperID
            ) else {
                throw PaperFileAccessError.cannotAccessSource
            }
            do {
                try repository.convertManagedPaperToReferenced(
                    paperID: paperID,
                    expectedFingerprint: expectedFingerprint,
                    bookmarkData: bookmark,
                    rememberedLocation: verified.url.path,
                    sourceFilename: verified.url.lastPathComponent,
                    fileSize: verified.fileSize,
                    modificationDate: verified.modificationDate
                )
            } catch {
                try? managedStore.restoreFromRecovery(
                    relativePath: managedRelativePath,
                    paperID: paperID
                )
                throw error
            }
            // The Paper now references the verified destination. Failure to remove
            // this recovery copy is harmless and startup reconciliation will retry.
            preparedTransfer.commit()
            transferCommitted = true
            try? managedStore.discardRecovery(paperID: paperID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

private extension URL {
    func isContained(in directoryURL: URL) -> Bool {
        let normalizedDirectory = directoryURL.standardizedFileURL.resolvingSymlinksInPath().path
        let normalizedDestination = standardizedFileURL.resolvingSymlinksInPath().path
        return normalizedDestination == normalizedDirectory
            || normalizedDestination.hasPrefix(normalizedDirectory + "/")
    }
}
