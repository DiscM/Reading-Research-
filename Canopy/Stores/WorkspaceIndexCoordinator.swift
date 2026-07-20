import CanopyCore
import Foundation
import Observation

@Observable
@MainActor
final class WorkspaceIndexCoordinator {
    private(set) var statuses: [PDFTextIndexStatus] = []
    private(set) var setupErrorMessage: String?

    @ObservationIgnored private var store: PDFTextIndexStore?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?

    init(databaseURL: URL) {
        do {
            store = try PDFTextIndexStore(databaseURL: databaseURL)
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    var activeStatuses: [PDFTextIndexStatus] {
        statuses.filter { $0.lifecycle != .ready }
    }

    var isWorking: Bool {
        activeStatuses.contains { $0.lifecycle == .pending || $0.lifecycle == .indexing }
    }

    var aggregateFractionCompleted: Double {
        let work = activeStatuses.filter {
            $0.lifecycle == .pending || $0.lifecycle == .indexing
        }
        guard !work.isEmpty else { return 0 }
        let indexed = work.reduce(0) { $0 + $1.indexedPageCount }
        let total = work.reduce(0) { $0 + max($1.totalPageCount, 1) }
        return Double(indexed) / Double(total)
    }

    func schedule(repository: LibraryRepository) {
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            guard let self else { return }
            await reconcileAndIndex(repository: repository)
        }
    }

    func enqueueDeletions(_ fingerprints: Set<Data>) async {
        guard !fingerprints.isEmpty else { return }
        guard let store else {
            if setupErrorMessage == nil {
                setupErrorMessage = "The search index is unavailable."
            }
            return
        }
        do {
            for fingerprint in fingerprints {
                try Task.checkCancellation()
                try await store.enqueueDeletion(forFingerprint: fingerprint)
            }
            setupErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    func retry(fingerprint: Data, repository: LibraryRepository) {
        indexingTask?.cancel()
        indexingTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let document = try repository.documents().first(where: {
                    $0.fingerprint == fingerprint
                }) else { return }
                try await index(document: document, repository: repository, retriesFailures: true)
                await refreshStatuses()
            } catch {
                setupErrorMessage = error.localizedDescription
            }
        }
    }

    func search(
        _ query: String,
        fingerprints: [Data]? = nil,
        limit: Int = 100
    ) async -> [PDFTextSearchHit] {
        guard let store else { return [] }
        do {
            let results = try await store.search(
                query,
                formatVersion: PDFTextIndexFormat.currentVersion,
                fingerprints: fingerprints,
                limit: limit
            )
            setupErrorMessage = nil
            return results
        } catch is CancellationError {
            return []
        } catch {
            setupErrorMessage = error.localizedDescription
            return []
        }
    }

    func status(for fingerprint: Data) -> PDFTextIndexStatus? {
        statuses.first { $0.key.fingerprint == fingerprint }
    }

    private func reconcileAndIndex(repository: LibraryRepository) async {
        guard let store else { return }
        do {
            let documents = try repository.documents()
            let retainedFingerprints = Set(documents.map(\.fingerprint))
            for fingerprint in retainedFingerprints {
                try Task.checkCancellation()
                try await store.cancelDeletion(forFingerprint: fingerprint)
            }
            for fingerprint in try await store.pendingDeletionFingerprints()
                where !retainedFingerprints.contains(fingerprint) {
                try Task.checkCancellation()
                try await store.deleteAllIndexData(forFingerprint: fingerprint)
            }
            let allStatuses = try await store.statuses()
            for fingerprint in Set(allStatuses.map(\.key.fingerprint))
                where !retainedFingerprints.contains(fingerprint) {
                try Task.checkCancellation()
                try await store.deleteAllIndexData(forFingerprint: fingerprint)
            }

            await refreshStatuses()
            setupErrorMessage = nil
            for document in documents.sorted(by: { $0.dateAdded < $1.dateAdded }) {
                try Task.checkCancellation()
                try await index(document: document, repository: repository, retriesFailures: false)
            }
            await refreshStatuses()
        } catch is CancellationError {
            return
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    private func index(
        document: Document,
        repository: LibraryRepository,
        retriesFailures: Bool
    ) async throws {
        guard let store else { return }
        let key = try PDFTextIndexKey(
            fingerprint: document.fingerprint,
            formatVersion: PDFTextIndexFormat.currentVersion
        )

        if let existing = try await store.status(for: key) {
            if existing.lifecycle == .ready { return }
            if existing.lifecycle == .failed, !retriesFailures { return }
        }

        guard document.sourceState == .available else {
            let preparation = try await prepare(
                key,
                totalPageCount: document.pageCount,
                store: store
            )
            _ = preparation
            _ = try await store.markNeedsSource(key)
            await refreshStatuses()
            return
        }

        let sourceSnapshot = DocumentSourceAccessSnapshot(document: document)
        let sourceAccess: PaperSourceAccess
        let extractor: PDFKitPageTextExtractor
        let pageCount: Int
        do {
            (sourceAccess, extractor, pageCount) = try await Task.detached(priority: .utility) {
                let access = try PaperSourceAccess(snapshot: sourceSnapshot)
                let extractor = try PDFKitPageTextExtractor(url: access.url)
                let pageCount = await extractor.pageCount
                return (access, extractor, pageCount)
            }.value
            if sourceAccess.attributesChanged || sourceSnapshot.sourceState != .available {
                try repository.recordVerifiedSourceAccess(
                    documentID: document.id,
                    fileSize: sourceAccess.verifiedFileSize,
                    modificationDate: sourceAccess.verifiedModificationDate
                )
            }
        } catch let sourceError as PaperSourceAccessError {
            try? repository.recordSourceAccessFailure(
                documentID: document.id,
                error: sourceError
            )
            _ = try await prepare(
                key,
                totalPageCount: document.pageCount,
                store: store
            )
            _ = try await store.markNeedsSource(key)
            await refreshStatuses()
            return
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            _ = try await prepare(
                key,
                totalPageCount: document.pageCount,
                store: store
            )
            replaceStatus(try await store.markFailed(key, reason: error.localizedDescription))
            return
        }

        do {
            let preparation = try await prepare(
                key,
                totalPageCount: pageCount,
                store: store
            )
            if preparation.status.indexedPageCount == pageCount {
                _ = try await store.markReady(key)
                await refreshStatuses()
                return
            }

            var pageIndex = preparation.status.nextPageIndex ?? 0
            while pageIndex < pageCount {
                try Task.checkCancellation()
                let page = try await extractor.extractPage(at: pageIndex)
                let status = try await store.storePageText(
                    page.text,
                    pageIndex: page.pageIndex,
                    for: key
                )
                replaceStatus(status)
                pageIndex = status.nextPageIndex ?? pageCount
            }
            replaceStatus(try await store.markReady(key))
            withExtendedLifetime(sourceAccess) {}
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if try await store.status(for: key) != nil {
                replaceStatus(try await store.markFailed(key, reason: error.localizedDescription))
            }
        }
    }

    private func prepare(
        _ key: PDFTextIndexKey,
        totalPageCount: Int,
        store: PDFTextIndexStore
    ) async throws -> PDFTextIndexPreparation {
        do {
            let preparation = try await store.prepare(key, totalPageCount: totalPageCount)
            replaceStatus(preparation.status)
            return preparation
        } catch let error as PDFTextIndexError {
            guard case .pageCountMismatch = error else { throw error }
            let status = try await store.rebuild(key, totalPageCount: totalPageCount)
            replaceStatus(status)
            return PDFTextIndexPreparation(disposition: .resumable, status: status)
        }
    }

    private func refreshStatuses() async {
        guard let store else { return }
        do {
            statuses = try await store.statuses(
                formatVersion: PDFTextIndexFormat.currentVersion
            )
            setupErrorMessage = nil
        } catch {
            setupErrorMessage = error.localizedDescription
        }
    }

    private func replaceStatus(_ status: PDFTextIndexStatus) {
        statuses.removeAll { $0.key == status.key }
        statuses.append(status)
        statuses.sort { lhs, rhs in
            lhs.key.fingerprint.lexicographicallyPrecedes(rhs.key.fingerprint)
        }
    }
}
