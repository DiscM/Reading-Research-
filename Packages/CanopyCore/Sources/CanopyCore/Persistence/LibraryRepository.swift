import Foundation
import SwiftData

public enum ApprovedPaperSource: Sendable {
    case referenced(bookmarkData: Data, rememberedLocation: String)
    case managedCopy(relativePath: String)
}

public enum LibraryRepositoryError: LocalizedError, Equatable {
    case paperNotFound
    case annotationNotFound
    case annotationsUnavailable
    case invalidAnnotationAnchor
    case invalidTitle
    case invalidPublicationYear
    case invalidDOI
    case invalidArxivID
    case invalidAuthorCredit
    case invalidMetadataProvenance
    case contentIdentityMismatch
    case incompatibleStorageMode

    public var errorDescription: String? {
        switch self {
        case .paperNotFound: "The Paper is no longer in the library."
        case .annotationNotFound: "The annotation is no longer attached to this Paper."
        case .annotationsUnavailable: "Canopy must verify the Paper's original Source PDF before changing its annotations."
        case .invalidAnnotationAnchor: "The selected text could not be anchored in this PDF."
        case .invalidTitle: "Enter a valid title for this Paper."
        case .invalidPublicationYear: "Enter a publication year from 1000 through next year, or leave it blank."
        case .invalidDOI: "Enter a valid DOI, or leave it blank."
        case .invalidArxivID: "Enter a valid arXiv ID, or leave it blank."
        case .invalidAuthorCredit: "Enter a display and family name for each Author Credit, or remove empty rows."
        case .invalidMetadataProvenance: "The Paper Info snapshot has inconsistent metadata provenance."
        case .contentIdentityMismatch: "The selected PDF does not match the Paper's original content."
        case .incompatibleStorageMode: "This source operation is not valid for the Paper's storage mode."
        }
    }
}

@MainActor
public final class LibraryRepository {
    public let container: ModelContainer
    private let suppliedContext: ModelContext?
    public var context: ModelContext { suppliedContext ?? container.mainContext }

    public init(container: ModelContainer) {
        self.container = container
        self.suppliedContext = nil
        context.autosaveEnabled = false
    }

    public init(context: ModelContext) {
        self.container = context.container
        self.suppliedContext = context
        context.autosaveEnabled = false
    }

    public func insert(_ paper: Paper) throws {
        context.insert(paper)
        try context.save()
    }

    @discardableResult
    public func add(_ candidate: PreflightCandidate, source: ApprovedPaperSource) throws -> Paper {
        let storageMode: PaperStorageMode
        let bookmarkData: Data?
        let managedRelativePath: String?
        let rememberedLocation: String?
        switch source {
        case let .referenced(data, location):
            storageMode = .referenced
            bookmarkData = data
            managedRelativePath = nil
            rememberedLocation = location
        case let .managedCopy(relativePath):
            storageMode = .managedCopy
            bookmarkData = nil
            managedRelativePath = relativePath
            rememberedLocation = nil
        }

        let credits = candidate.metadata.authors.enumerated().map { index, author in
            AuthorCredit(
                position: index,
                displayName: author.displayName,
                familyName: author.familyName,
                provenance: author.provenance
            )
        }
        let paper = Paper(
            fingerprint: candidate.fingerprint,
            title: candidate.metadata.title,
            titleProvenance: candidate.metadata.titleProvenance,
            publicationYear: candidate.metadata.publicationYear,
            publicationYearProvenance: candidate.metadata.publicationYearProvenance,
            doi: candidate.metadata.doi,
            doiProvenance: candidate.metadata.doiProvenance,
            arxivID: candidate.metadata.arxivID,
            arxivIDProvenance: candidate.metadata.arxivIDProvenance,
            storageMode: storageMode,
            bookmarkData: bookmarkData,
            managedRelativePath: managedRelativePath,
            sourceFilename: candidate.url.lastPathComponent,
            rememberedLocation: rememberedLocation,
            sourceFileSize: candidate.fileSize,
            sourceModificationDate: candidate.modificationDate,
            pageCount: candidate.metadata.pageTexts.count,
            embeddedCreationDate: candidate.metadata.embeddedCreationDate,
            embeddedModificationDate: candidate.metadata.embeddedModificationDate,
            authorCredits: credits
        )
        try insert(paper)
        return paper
    }

    public func paperIdentitySnapshots() throws -> [PaperIdentitySnapshot] {
        try context.fetch(FetchDescriptor<Paper>()).map { paper in
            PaperIdentitySnapshot(
                id: paper.id,
                fingerprint: paper.fingerprint,
                title: paper.title,
                authorFamilyNames: paper.authorCredits.map(\.familyName),
                publicationYear: paper.publicationYear,
                doi: paper.doi,
                arxivID: paper.arxivID,
                sourceState: paper.sourceState,
                rememberedLocation: paper.rememberedLocation,
                storageMode: paper.storageMode,
                sourceFilename: paper.sourceFilename,
                sourceFileSize: paper.sourceFileSize,
                pageCount: paper.pageCount,
                authorDisplayNames: paper.authorCredits.sorted { $0.position < $1.position }.map(\.displayName),
                titleProvenance: paper.titleProvenance,
                embeddedCreationDate: paper.embeddedCreationDate,
                embeddedModificationDate: paper.embeddedModificationDate
            )
        }
    }

    public func paper(id: UUID) throws -> Paper? {
        var descriptor = FetchDescriptor<Paper>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func sourceAvailabilityRequests() throws -> [PaperSourceAvailabilityRequest] {
        try context.fetch(FetchDescriptor<Paper>()).compactMap { paper in
            guard paper.sourceState != .brokenReference, paper.sourceState != .sourceChanged else {
                return nil
            }
            return PaperSourceAvailabilityRequest(
                paperID: paper.id,
                storageMode: paper.storageMode,
                bookmarkData: paper.bookmarkData,
                managedRelativePath: paper.managedRelativePath,
                sourceFileSize: paper.sourceFileSize,
                sourceModificationDate: paper.sourceModificationDate,
                sourceState: paper.sourceState
            )
        }
    }

    public func applySourceAvailabilityResults(
        _ results: [PaperSourceAvailabilityResult]
    ) throws {
        guard !results.isEmpty else { return }
        let papersByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Paper>()).map { ($0.id, $0) }
        )
        var changed = false
        for result in results {
            let request = result.request
            guard let paper = papersByID[result.paperID],
                  paper.storageMode == request.storageMode,
                  paper.sourceState == request.sourceState,
                  paper.bookmarkData == request.bookmarkData,
                  paper.managedRelativePath == request.managedRelativePath,
                  paper.sourceFileSize == request.sourceFileSize,
                  paper.sourceModificationDate == request.sourceModificationDate else {
                continue
            }
            let nextState: PaperSourceState
            if result.status == .available, result.attributesChanged {
                continue
            } else {
                nextState = result.status
            }
            if paper.sourceState != nextState {
                paper.sourceState = nextState
                changed = true
            }
        }
        if changed {
            try save()
        }
    }

    public func paperInfoSnapshot(paperID: UUID) throws -> PaperInfoSnapshot {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        return paperInfoSnapshot(for: paper)
    }

    @discardableResult
    public func updatePaperInfo(
        paperID: UUID,
        update: PaperInfoUpdate
    ) throws -> PaperInfoChange {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        let values = try validatedPaperInfoValues(update)
        let before = paperInfoSnapshot(for: paper)
        let target = PaperInfoSnapshot(
            paperID: paperID,
            title: values.title,
            titleProvenance: values.title == before.title ? before.titleProvenance : .userEntry,
            publicationYear: values.publicationYear,
            publicationYearProvenance: values.publicationYear == before.publicationYear
                ? before.publicationYearProvenance
                : values.publicationYear.map { _ in .userEntry },
            doi: values.doi,
            doiProvenance: values.doi == before.doi
                ? before.doiProvenance
                : values.doi.map { _ in .userEntry },
            arxivID: values.arxivID,
            arxivIDProvenance: values.arxivID == before.arxivID
                ? before.arxivIDProvenance
                : values.arxivID.map { _ in .userEntry },
            authorCredits: paperInfoAuthorSnapshots(
                from: values.authorCredits,
                before: before.authorCredits
            )
        )
        return try persistPaperInfoSnapshot(target, to: paper, before: before)
    }

    @discardableResult
    public func applyPaperInfoSnapshot(_ snapshot: PaperInfoSnapshot) throws -> PaperInfoChange {
        guard let paper = try paper(id: snapshot.paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        let target = try validatedPaperInfoSnapshot(snapshot)
        let before = paperInfoSnapshot(for: paper)
        return try persistPaperInfoSnapshot(target, to: paper, before: before)
    }

    @discardableResult
    public func restorePaperInfoSnapshot(_ snapshot: PaperInfoSnapshot) throws -> PaperInfoChange {
        try applyPaperInfoSnapshot(snapshot)
    }

    private func validatedPaperInfoSnapshot(_ snapshot: PaperInfoSnapshot) throws -> PaperInfoSnapshot {
        guard (snapshot.publicationYear == nil) == (snapshot.publicationYearProvenance == nil),
              (snapshot.doi == nil) == (snapshot.doiProvenance == nil),
              (snapshot.arxivID == nil) == (snapshot.arxivIDProvenance == nil) else {
            throw LibraryRepositoryError.invalidMetadataProvenance
        }
        let orderedAuthors = snapshot.authorCredits.sorted(by: authorCreditSnapshotOrder)
        guard orderedAuthors.map(\.position) == Array(orderedAuthors.indices),
              Set(orderedAuthors.map(\.id)).count == orderedAuthors.count else {
            throw LibraryRepositoryError.invalidAuthorCredit
        }
        let values = try validatedPaperInfoValues(PaperInfoUpdate(
            title: snapshot.title,
            publicationYear: snapshot.publicationYear,
            doi: snapshot.doi,
            arxivID: snapshot.arxivID,
            authorCredits: orderedAuthors.map {
                AuthorCreditUpdate(
                    id: $0.id,
                    displayName: $0.displayName,
                    familyName: $0.familyName
                )
            }
        ))
        let provenanceByID = Dictionary(
            uniqueKeysWithValues: orderedAuthors.map { ($0.id, $0.provenance) }
        )
        let restoredAuthors = try values.authorCredits.enumerated().map { position, author in
            guard let provenance = provenanceByID[author.id] else {
                throw LibraryRepositoryError.invalidMetadataProvenance
            }
            return AuthorCreditSnapshot(
                id: author.id,
                position: position,
                displayName: author.displayName,
                familyName: author.familyName,
                provenance: provenance
            )
        }
        return PaperInfoSnapshot(
            paperID: snapshot.paperID,
            title: values.title,
            titleProvenance: snapshot.titleProvenance,
            publicationYear: values.publicationYear,
            publicationYearProvenance: snapshot.publicationYearProvenance,
            doi: values.doi,
            doiProvenance: snapshot.doiProvenance,
            arxivID: values.arxivID,
            arxivIDProvenance: snapshot.arxivIDProvenance,
            authorCredits: restoredAuthors
        )
    }

    public func recordPaperOpened(paperID: UUID, at date: Date = .now) throws {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        paper.lastOpenedAt = date
        try save()
    }

    public func saveReaderState(paperID: UUID, state: PaperReaderState) throws {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        paper.lastPageIndex = state.pageIndex
        paper.lastViewport = try state.viewport.map { try JSONEncoder().encode($0) }
        paper.lastZoomScale = state.zoomScale
        paper.isInspectorPresented = state.isInspectorPresented
        try save()
    }

    public func readerState(paperID: UUID) throws -> PaperReaderState? {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard let pageIndex = paper.lastPageIndex,
              let zoomScale = paper.lastZoomScale else {
            return nil
        }
        let viewport = try paper.lastViewport.map { try JSONDecoder().decode(PaperViewport.self, from: $0) }
        return PaperReaderState(
            pageIndex: pageIndex,
            viewport: viewport,
            zoomScale: zoomScale,
            isInspectorPresented: paper.isInspectorPresented
        )
    }

    public func annotations(paperID: UUID) throws -> [Annotation] {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        return Annotation.sortedInPageOrder(paper.annotations)
    }

    @discardableResult
    public func createAnnotations(
        paperID: UUID,
        anchors: [AnnotationAnchor],
        color: HighlightColor,
        note: String = ""
    ) throws -> [Annotation] {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        guard !anchors.isEmpty,
              anchors.allSatisfy({
                  $0.pageIndex >= 0
                      && $0.pageIndex < max(paper.pageCount, 1)
                      && !$0.quadrilaterals.isEmpty
                      && !$0.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }) else {
            throw LibraryRepositoryError.invalidAnnotationAnchor
        }

        do {
            let annotations = try anchors.map { anchor in
                let annotation = try Annotation(anchor: anchor, color: color, note: note, paper: paper)
                context.insert(annotation)
                return annotation
            }
            try context.save()
            return Annotation.sortedInPageOrder(annotations)
        } catch {
            context.rollback()
            throw error
        }
    }

    public func updateAnnotationNote(annotationID: UUID, note: String, at date: Date = .now) throws {
        guard let annotation = try annotation(id: annotationID) else {
            throw LibraryRepositoryError.annotationNotFound
        }
        guard annotation.paper?.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        guard annotation.note != note else { return }
        annotation.note = note
        annotation.updatedAt = date
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    public func deleteAnnotation(annotationID: UUID) throws -> AnnotationSnapshot {
        guard let snapshot = try deleteAnnotations(annotationIDs: [annotationID]).first else {
            throw LibraryRepositoryError.annotationNotFound
        }
        return snapshot
    }

    @discardableResult
    public func deleteAnnotations(annotationIDs: [UUID]) throws -> [AnnotationSnapshot] {
        guard !annotationIDs.isEmpty else { return [] }
        let annotationsByID = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Annotation>()).map { ($0.id, $0) }
        )
        let annotations = try annotationIDs.map { annotationID in
            guard let annotation = annotationsByID[annotationID], let paper = annotation.paper else {
                throw LibraryRepositoryError.annotationNotFound
            }
            guard paper.sourceState == .available else {
                throw LibraryRepositoryError.annotationsUnavailable
            }
            return annotation
        }
        let snapshots = annotations.compactMap { annotation in
            annotation.paper.map { AnnotationSnapshot(annotation: annotation, paperID: $0.id) }
        }
        for annotation in annotations {
            context.delete(annotation)
        }
        do {
            try context.save()
            return snapshots
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    public func restoreAnnotation(_ snapshot: AnnotationSnapshot) throws -> Annotation {
        guard let annotation = try restoreAnnotations([snapshot]).first else {
            throw LibraryRepositoryError.annotationNotFound
        }
        return annotation
    }

    @discardableResult
    public func restoreAnnotations(_ snapshots: [AnnotationSnapshot]) throws -> [Annotation] {
        guard !snapshots.isEmpty else { return [] }
        let papers = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Paper>()).map { ($0.id, $0) }
        )
        do {
            let snapshotPapers = try snapshots.map { snapshot in
                guard let paper = papers[snapshot.paperID] else {
                    throw LibraryRepositoryError.paperNotFound
                }
                guard paper.sourceState == .available else {
                    throw LibraryRepositoryError.annotationsUnavailable
                }
                return (snapshot, paper)
            }
            let annotations = snapshotPapers.map { snapshot, paper in
                let annotation = Annotation(
                    id: snapshot.id,
                    pageIndex: snapshot.pageIndex,
                    quadrilaterals: snapshot.quadrilaterals,
                    selectedText: snapshot.selectedText,
                    contextBefore: snapshot.contextBefore,
                    contextAfter: snapshot.contextAfter,
                    color: snapshot.color,
                    note: snapshot.note,
                    createdAt: snapshot.createdAt,
                    paper: paper
                )
                annotation.updatedAt = snapshot.updatedAt
                context.insert(annotation)
                return annotation
            }
            try context.save()
            return annotations
        } catch {
            context.rollback()
            throw error
        }
    }

    public func sourceAccess(
        paperID: UUID,
        managedStore: ManagedPaperStore? = nil
    ) throws -> PaperSourceAccess {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        do {
            let access = try PaperSourceAccess(paper: paper, managedStore: managedStore)
            if access.attributesChanged || paper.sourceState != .available {
                try markSourceAvailable(
                    paper,
                    fileSize: access.verifiedFileSize,
                    modificationDate: access.verifiedModificationDate
                )
            }
            return access
        } catch let error as PaperSourceAccessError {
            switch error {
            case .sourceUnavailable:
                paper.sourceState = .sourceUnavailable
            case .sourceMissing:
                paper.sourceState = .brokenReference
            case .sourceChanged:
                paper.sourceState = .sourceChanged
            case .libraryCopyMissing:
                paper.sourceState = .libraryCopyMissing
            }
            try save()
            throw error
        }
    }

    public func repairReference(
        paperID: UUID,
        fingerprint: Data,
        bookmarkData: Data,
        rememberedLocation: String
    ) throws {
        guard let paper = try context.fetch(FetchDescriptor<Paper>()).first(where: { $0.id == paperID }) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.storageMode == .referenced else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        guard paper.fingerprint == fingerprint else {
            throw LibraryRepositoryError.contentIdentityMismatch
        }
        paper.bookmarkData = bookmarkData
        paper.rememberedLocation = rememberedLocation
        paper.sourceFilename = URL(fileURLWithPath: rememberedLocation).lastPathComponent
        paper.sourceState = .available
        try save()
    }

    public func restoreManagedCopy(
        paperID: UUID,
        from sourceURL: URL,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) async throws {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.storageMode == .managedCopy,
              let relativePath = paper.managedRelativePath else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        let expectedFingerprint = paper.fingerprint

        let managedStore = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
        let restoredURL: URL
        do {
            restoredURL = try await Task.detached(priority: .userInitiated) {
                try managedStore.restoreMissingCopy(
                    from: sourceURL,
                    relativePath: relativePath,
                    expectedFingerprint: expectedFingerprint
                )
            }.value
        } catch PaperFileAccessError.contentIdentityMismatch {
            throw LibraryRepositoryError.contentIdentityMismatch
        }

        do {
            guard let paper = try self.paper(id: paperID) else {
                throw LibraryRepositoryError.paperNotFound
            }
            guard paper.storageMode == .managedCopy,
                  paper.managedRelativePath == relativePath else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
            guard paper.fingerprint == expectedFingerprint else {
                throw LibraryRepositoryError.contentIdentityMismatch
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: restoredURL.path)
            try markSourceAvailable(
                paper,
                fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                modificationDate: attributes[.modificationDate] as? Date
            )
        } catch {
            let operationError = error
            do {
                try managedStore.remove(relativePath: relativePath)
            } catch {
                throw PaperFileAccessError.cannotAccessSource
            }
            throw operationError
        }
    }

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func markSourceAvailable(
        _ paper: Paper,
        fileSize: Int64,
        modificationDate: Date?
    ) throws {
        let previousFileSize = paper.sourceFileSize
        let previousModificationDate = paper.sourceModificationDate
        let previousSourceState = paper.sourceState
        paper.sourceFileSize = fileSize
        paper.sourceModificationDate = modificationDate
        paper.sourceState = .available
        do {
            try save()
        } catch {
            paper.sourceFileSize = previousFileSize
            paper.sourceModificationDate = previousModificationDate
            paper.sourceState = previousSourceState
            throw error
        }
    }

    public func removePaper(
        paperID: UUID,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> RemovedPaperSnapshot {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }

        var managedStore: ManagedPaperStore?
        var managedCopyWasStaged = false
        if paper.storageMode == .managedCopy {
            guard let relativePath = paper.managedRelativePath else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
            let store = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
            managedStore = store
            managedCopyWasStaged = try store.stageForRecovery(
                relativePath: relativePath,
                paperID: paper.id
            )
        }

        let snapshot = RemovedPaperSnapshot(
            paper: paper,
            managedCopyWasStaged: managedCopyWasStaged
        )
        context.delete(paper)
        do {
            try context.save()
            return snapshot
        } catch {
            let saveError = error
            defer { context.rollback() }
            if managedCopyWasStaged,
               let managedStore,
               let relativePath = snapshot.managedRelativePath {
                try managedStore.restoreFromRecovery(
                    relativePath: relativePath,
                    paperID: snapshot.id
                )
            }
            throw saveError
        }
    }

    @discardableResult
    public func restoreRemovedPaper(
        snapshot: RemovedPaperSnapshot,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> Paper {
        guard try paper(id: snapshot.id) == nil else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }

        var managedStore: ManagedPaperStore?
        if snapshot.storageMode == .managedCopy, snapshot.managedCopyWasStaged {
            guard let relativePath = snapshot.managedRelativePath else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
            let store = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
            try store.restoreFromRecovery(relativePath: relativePath, paperID: snapshot.id)
            managedStore = store
        }

        let authorCredits = snapshot.authorCredits.map { author in
            AuthorCredit(
                id: author.id,
                position: author.position,
                displayName: author.displayName,
                familyName: author.familyName,
                provenance: author.provenance
            )
        }
        let paper = Paper(
            id: snapshot.id,
            fingerprint: snapshot.fingerprint,
            title: snapshot.title,
            titleProvenance: snapshot.titleProvenance,
            publicationYear: snapshot.publicationYear,
            publicationYearProvenance: snapshot.publicationYearProvenance,
            doi: snapshot.doi,
            doiProvenance: snapshot.doiProvenance,
            arxivID: snapshot.arxivID,
            arxivIDProvenance: snapshot.arxivIDProvenance,
            storageMode: snapshot.storageMode,
            sourceState: snapshot.sourceState,
            bookmarkData: snapshot.bookmarkData,
            managedRelativePath: snapshot.managedRelativePath,
            sourceFilename: snapshot.sourceFilename,
            rememberedLocation: snapshot.rememberedLocation,
            sourceFileSize: snapshot.sourceFileSize,
            sourceModificationDate: snapshot.sourceModificationDate,
            pageCount: snapshot.pageCount,
            embeddedCreationDate: snapshot.embeddedCreationDate,
            embeddedModificationDate: snapshot.embeddedModificationDate,
            dateAdded: snapshot.dateAdded,
            authorCredits: authorCredits
        )
        paper.lastOpenedAt = snapshot.lastOpenedAt
        paper.lastPageIndex = snapshot.lastPageIndex
        paper.lastViewport = snapshot.lastViewport
        paper.lastZoomScale = snapshot.lastZoomScale
        paper.isInspectorPresented = snapshot.isInspectorPresented

        context.insert(paper)
        for annotationSnapshot in snapshot.annotations {
            let annotation = Annotation(
                id: annotationSnapshot.id,
                pageIndex: annotationSnapshot.pageIndex,
                quadrilaterals: annotationSnapshot.quadrilaterals,
                selectedText: annotationSnapshot.selectedText,
                contextBefore: annotationSnapshot.contextBefore,
                contextAfter: annotationSnapshot.contextAfter,
                color: annotationSnapshot.color,
                note: annotationSnapshot.note,
                createdAt: annotationSnapshot.createdAt,
                paper: paper
            )
            annotation.updatedAt = annotationSnapshot.updatedAt
            context.insert(annotation)
        }

        do {
            try context.save()
            return paper
        } catch {
            let saveError = error
            defer { context.rollback() }
            if snapshot.managedCopyWasStaged,
               let managedStore,
               let relativePath = snapshot.managedRelativePath {
                _ = try managedStore.stageForRecovery(
                    relativePath: relativePath,
                    paperID: snapshot.id
                )
            }
            throw saveError
        }
    }

    public func reconcileManagedPaperRecovery(
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws {
        let managedStore = try suppliedManagedStore ?? ManagedPaperStore.applicationSupport()
        let managedPaths: [UUID: String] = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<Paper>()).compactMap { paper in
                guard paper.storageMode == .managedCopy,
                      let relativePath = paper.managedRelativePath else {
                    return nil
                }
                return (paper.id, relativePath)
            }
        )
        try managedStore.reconcileRecovery(managedRelativePathsByPaperID: managedPaths)
    }

    public func clearRecentHistory() throws {
        let descriptor = FetchDescriptor<Paper>()
        for paper in try context.fetch(descriptor) {
            paper.lastOpenedAt = nil
        }
        try save()
    }

    private func annotation(id: UUID) throws -> Annotation? {
        var descriptor = FetchDescriptor<Annotation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func paperInfoSnapshot(for paper: Paper) -> PaperInfoSnapshot {
        PaperInfoSnapshot(
            paperID: paper.id,
            title: paper.title,
            titleProvenance: paper.titleProvenance,
            publicationYear: paper.publicationYear,
            publicationYearProvenance: paper.publicationYearProvenance,
            doi: paper.doi,
            doiProvenance: paper.doiProvenance,
            arxivID: paper.arxivID,
            arxivIDProvenance: paper.arxivIDProvenance,
            authorCredits: paper.authorCredits
                .map(AuthorCreditSnapshot.init)
                .sorted(by: authorCreditSnapshotOrder)
        )
    }

    private func validatedPaperInfoValues(_ update: PaperInfoUpdate) throws -> PaperInfoValues {
        guard let title = MetadataValidator.usableTitle(update.title) else {
            throw LibraryRepositoryError.invalidTitle
        }
        guard MetadataValidator.validPublicationYear(update.publicationYear) else {
            throw LibraryRepositoryError.invalidPublicationYear
        }

        let rawDOI = update.doi?.trimmingCharacters(in: .whitespacesAndNewlines)
        let doi: String?
        if let rawDOI, !rawDOI.isEmpty {
            guard let normalized = MetadataValidator.normalizedDOI(rawDOI) else {
                throw LibraryRepositoryError.invalidDOI
            }
            doi = normalized
        } else {
            doi = nil
        }

        let rawArxivID = update.arxivID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let arxivID: String?
        if let rawArxivID, !rawArxivID.isEmpty {
            guard let normalized = MetadataValidator.normalizedArxivID(rawArxivID) else {
                throw LibraryRepositoryError.invalidArxivID
            }
            arxivID = normalized
        } else {
            arxivID = nil
        }

        var authorIDs = Set<UUID>()
        let authorCredits = try update.authorCredits.map { author in
            let displayName = author.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let familyName = author.familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard authorIDs.insert(author.id).inserted,
                  !displayName.isEmpty,
                  !familyName.isEmpty else {
                throw LibraryRepositoryError.invalidAuthorCredit
            }
            return AuthorCreditUpdate(
                id: author.id,
                displayName: displayName,
                familyName: familyName
            )
        }

        return PaperInfoValues(
            title: title,
            publicationYear: update.publicationYear,
            doi: doi,
            arxivID: arxivID,
            authorCredits: authorCredits
        )
    }

    private func paperInfoAuthorSnapshots(
        from updates: [AuthorCreditUpdate],
        before: [AuthorCreditSnapshot]
    ) -> [AuthorCreditSnapshot] {
        let existingByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
        return updates.enumerated().map { position, update in
            let existing = existingByID[update.id]
            let provenance: MetadataProvenance = if let existing,
                existing.displayName == update.displayName,
                existing.familyName == update.familyName {
                existing.provenance
            } else {
                .userEntry
            }
            return AuthorCreditSnapshot(
                id: update.id,
                position: position,
                displayName: update.displayName,
                familyName: update.familyName,
                provenance: provenance
            )
        }
    }

    private func persistPaperInfoSnapshot(
        _ target: PaperInfoSnapshot,
        to paper: Paper,
        before: PaperInfoSnapshot
    ) throws -> PaperInfoChange {
        guard target != before else {
            return PaperInfoChange(before: before, after: before)
        }

        guard target.authorCredits.map(\.position) == Array(target.authorCredits.indices),
              Set(target.authorCredits.map(\.id)).count == target.authorCredits.count else {
            throw LibraryRepositoryError.invalidAuthorCredit
        }
        let targetAuthorIDs = Set(target.authorCredits.map(\.id))
        let conflictingAuthorExists = try context.fetch(FetchDescriptor<AuthorCredit>()).contains { author in
            targetAuthorIDs.contains(author.id) && author.paper?.id != paper.id
        }
        guard !conflictingAuthorExists else {
            throw LibraryRepositoryError.invalidAuthorCredit
        }

        do {
            let currentAuthors = paper.authorCredits
            let currentAuthorsByID = Dictionary(uniqueKeysWithValues: currentAuthors.map { ($0.id, $0) })
            let targetAuthors = target.authorCredits.map { snapshot in
                let author = currentAuthorsByID[snapshot.id] ?? AuthorCredit(
                    id: snapshot.id,
                    position: snapshot.position,
                    displayName: snapshot.displayName,
                    familyName: snapshot.familyName,
                    provenance: snapshot.provenance,
                    paper: paper
                )
                author.position = snapshot.position
                author.displayName = snapshot.displayName
                author.familyName = snapshot.familyName
                author.provenance = snapshot.provenance
                author.paper = paper
                if currentAuthorsByID[snapshot.id] == nil {
                    context.insert(author)
                }
                return author
            }

            paper.title = target.title
            paper.titleProvenance = target.titleProvenance
            paper.publicationYear = target.publicationYear
            paper.publicationYearProvenance = target.publicationYearProvenance
            paper.doi = target.doi
            paper.doiProvenance = target.doiProvenance
            paper.arxivID = target.arxivID
            paper.arxivIDProvenance = target.arxivIDProvenance
            paper.authorCredits = targetAuthors
            for author in currentAuthors where !targetAuthorIDs.contains(author.id) {
                context.delete(author)
            }

            try context.save()
            return PaperInfoChange(before: before, after: paperInfoSnapshot(for: paper))
        } catch {
            context.rollback()
            throw error
        }
    }

}

private struct PaperInfoValues {
    let title: String
    let publicationYear: Int?
    let doi: String?
    let arxivID: String?
    let authorCredits: [AuthorCreditUpdate]
}

private func authorCreditSnapshotOrder(_ lhs: AuthorCreditSnapshot, _ rhs: AuthorCreditSnapshot) -> Bool {
    if lhs.position != rhs.position { return lhs.position < rhs.position }
    return lhs.id.uuidString < rhs.id.uuidString
}

public struct AnnotationSnapshot: Equatable, Sendable {
    public let id: UUID
    public let paperID: UUID
    public let pageIndex: Int
    public let quadrilaterals: Data
    public let selectedText: String
    public let contextBefore: String
    public let contextAfter: String
    public let color: HighlightColor
    public let note: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(annotation: Annotation, paperID: UUID) {
        id = annotation.id
        self.paperID = paperID
        pageIndex = annotation.pageIndex
        quadrilaterals = annotation.quadrilaterals
        selectedText = annotation.selectedText
        contextBefore = annotation.contextBefore
        contextAfter = annotation.contextAfter
        color = annotation.color
        note = annotation.note
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
    }
}
