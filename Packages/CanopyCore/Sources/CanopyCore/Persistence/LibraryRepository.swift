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
    case contentIdentityMismatch
    case incompatibleStorageMode

    public var errorDescription: String? {
        switch self {
        case .paperNotFound: "The Paper is no longer in the library."
        case .annotationNotFound: "The annotation is no longer attached to this Paper."
        case .annotationsUnavailable: "Canopy must verify the Paper's original Source PDF before changing its annotations."
        case .invalidAnnotationAnchor: "The selected text could not be anchored in this PDF."
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
                paper.sourceFileSize = access.verifiedFileSize
                paper.sourceModificationDate = access.verifiedModificationDate
                paper.sourceState = .available
                try save()
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

    public func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    public func remove(_ paper: Paper) throws {
        context.delete(paper)
        try context.save()
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
