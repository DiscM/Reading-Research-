import Foundation
import SwiftData

public enum ApprovedPaperSource: Sendable {
    case referenced(bookmarkData: Data, rememberedLocation: String)
    case managedCopy(relativePath: String)
}

public enum LibraryRepositoryError: LocalizedError, Equatable {
    case paperNotFound
    case documentNotFound
    case collectionNotFound
    case invalidCollectionName
    case duplicateCollectionName
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
        case .paperNotFound: "The Document is no longer in the library."
        case .documentNotFound: "The Document is no longer in the library."
        case .collectionNotFound: "The Collection is no longer in the library."
        case .invalidCollectionName: "Enter a name for this Collection."
        case .duplicateCollectionName: "A Collection with this name already exists."
        case .annotationNotFound: "The annotation is no longer attached to this Document."
        case .annotationsUnavailable: "Canopy must verify the Document's original Source PDF before changing its annotations."
        case .invalidAnnotationAnchor: "The annotation could not be anchored on this PDF page."
        case .invalidTitle: "Enter a valid title for this Document."
        case .invalidPublicationYear: "Enter a publication year from 1000 through next year, or leave it blank."
        case .invalidDOI: "Enter a valid DOI, or leave it blank."
        case .invalidArxivID: "Enter a valid arXiv ID, or leave it blank."
        case .invalidAuthorCredit: "Enter a display and family name for each Author Credit, or remove empty rows."
        case .invalidMetadataProvenance: "The Document Info snapshot has inconsistent metadata provenance."
        case .contentIdentityMismatch: "The selected PDF does not match the Document's original content."
        case .incompatibleStorageMode: "This source operation is not valid for the Document's storage mode."
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

    public func documents() throws -> [Document] {
        try context.fetch(FetchDescriptor<Document>())
    }

    public func document(id: UUID) throws -> Document? {
        var descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func collections() throws -> [Collection] {
        try context.fetch(FetchDescriptor<Collection>()).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func collection(id: UUID) throws -> Collection? {
        var descriptor = FetchDescriptor<Collection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func collectionSnapshot(id: UUID) throws -> CollectionSnapshot {
        guard let collection = try collection(id: id) else {
            throw LibraryRepositoryError.collectionNotFound
        }
        return CollectionSnapshot(
            id: collection.id,
            name: collection.name,
            dateCreated: collection.dateCreated,
            documentIDs: collection.documents.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    @discardableResult
    public func createCollection(
        name: String,
        documentIDs: [UUID] = []
    ) throws -> Collection {
        let name = try validatedCollectionName(name)
        try ensureCollectionNameIsAvailable(name)
        let documents = try requiredDocuments(ids: documentIDs)
        let collection = Collection(name: name, documents: documents)
        do {
            context.insert(collection)
            for document in documents where !document.collections.contains(where: { $0.id == collection.id }) {
                document.collections.append(collection)
            }
            try save()
            return collection
        } catch {
            context.rollback()
            throw error
        }
    }

    public func renameCollection(id: UUID, name: String) throws {
        guard let collection = try collection(id: id) else {
            throw LibraryRepositoryError.collectionNotFound
        }
        let name = try validatedCollectionName(name)
        try ensureCollectionNameIsAvailable(name, excluding: id)
        do {
            collection.name = name
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func collectionMemberships(for documentID: UUID) throws -> [Collection] {
        guard let document = try document(id: documentID) else {
            throw LibraryRepositoryError.documentNotFound
        }
        return document.collections.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func addDocuments(_ documentIDs: [UUID], toCollection collectionID: UUID) throws {
        guard let collection = try collection(id: collectionID) else {
            throw LibraryRepositoryError.collectionNotFound
        }
        let documents = try requiredDocuments(ids: documentIDs)
        guard !documents.isEmpty else { return }
        do {
            var changed = false
            for document in documents where !document.collections.contains(where: { $0.id == collectionID }) {
                document.collections.append(collection)
                changed = true
            }
            if changed {
                try save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    public func removeDocuments(_ documentIDs: [UUID], fromCollection collectionID: UUID) throws {
        guard try collection(id: collectionID) != nil else {
            throw LibraryRepositoryError.collectionNotFound
        }
        let documents = try requiredDocuments(ids: documentIDs)
        guard !documents.isEmpty else { return }
        do {
            var changed = false
            for document in documents where document.collections.contains(where: { $0.id == collectionID }) {
                document.collections.removeAll { $0.id == collectionID }
                changed = true
            }
            if changed {
                try save()
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    public func deleteCollection(id: UUID) throws {
        guard let collection = try collection(id: id) else {
            throw LibraryRepositoryError.collectionNotFound
        }
        do {
            for document in collection.documents {
                document.collections.removeAll { $0.id == id }
            }
            context.delete(collection)
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func restoreCollection(_ snapshot: CollectionSnapshot) throws {
        guard try collection(id: snapshot.id) == nil else {
            throw LibraryRepositoryError.duplicateCollectionName
        }
        let name = try validatedCollectionName(snapshot.name)
        try ensureCollectionNameIsAvailable(name)
        let documents = try requiredDocuments(ids: snapshot.documentIDs)
        let collection = Collection(
            id: snapshot.id,
            name: name,
            dateCreated: snapshot.dateCreated,
            documents: documents
        )
        do {
            context.insert(collection)
            for document in documents where !document.collections.contains(where: { $0.id == snapshot.id }) {
                document.collections.append(collection)
            }
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func updateDocumentNote(documentID: UUID, note: String) throws {
        guard let document = try document(id: documentID) else {
            throw LibraryRepositoryError.documentNotFound
        }
        do {
            document.documentNote = note
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func updateDocumentDate(documentID: UUID, date: DocumentDate?) throws {
        try setDocumentDate(
            date,
            provenance: date == nil ? nil : .userEntry,
            for: documentID
        )
    }

    public func setDocumentDate(
        _ date: DocumentDate?,
        provenance: MetadataProvenance?,
        for documentID: UUID
    ) throws {
        guard MetadataValidator.validPublicationYear(date?.year) else {
            throw LibraryRepositoryError.invalidPublicationYear
        }
        guard let document = try document(id: documentID) else {
            throw LibraryRepositoryError.documentNotFound
        }
        guard (date == nil) == (provenance == nil) else {
            throw LibraryRepositoryError.invalidMetadataProvenance
        }
        do {
            document.documentDate = date
            document.documentDateProvenance = provenance
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func setDocumentKind(_ kind: DocumentKind, for documentIDs: [UUID]) throws {
        try setDocumentKinds(Dictionary(uniqueKeysWithValues: documentIDs.map { ($0, kind) }))
    }

    public func setDocumentKinds(_ kindsByDocumentID: [UUID: DocumentKind]) throws {
        let documentIDs = Array(kindsByDocumentID.keys)
        let documents = try requiredDocuments(ids: documentIDs)
        guard !documents.isEmpty else { return }
        do {
            for document in documents {
                guard let kind = kindsByDocumentID[document.id] else { continue }
                document.kind = kind
            }
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func setCollectionMembership(
        collectionID: UUID,
        documentIDs: [UUID],
        memberDocumentIDs: Set<UUID>
    ) throws {
        guard let collection = try collection(id: collectionID) else {
            throw LibraryRepositoryError.collectionNotFound
        }
        let uniqueDocumentIDs = Array(Set(documentIDs))
        guard memberDocumentIDs.isSubset(of: Set(uniqueDocumentIDs)) else {
            throw LibraryRepositoryError.documentNotFound
        }
        let documents = try requiredDocuments(ids: uniqueDocumentIDs)
        guard !documents.isEmpty else { return }
        do {
            for document in documents {
                let isMember = document.collections.contains { $0.id == collectionID }
                let shouldBeMember = memberDocumentIDs.contains(document.id)
                if shouldBeMember, !isMember {
                    document.collections.append(collection)
                } else if !shouldBeMember, isMember {
                    document.collections.removeAll { $0.id == collectionID }
                }
            }
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    public func add(
        _ candidate: PreflightCandidate,
        source: ApprovedPaperSource,
        kind: DocumentKind = .generalDocument,
        toCollection collectionID: UUID? = nil
    ) throws -> Document {
        let destinationCollection: Collection?
        if let collectionID {
            guard let collection = try collection(id: collectionID) else {
                throw LibraryRepositoryError.collectionNotFound
            }
            destinationCollection = collection
        } else {
            destinationCollection = nil
        }
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

        let isResearchPaper = kind == .researchPaper
        let acceptedAuthors = isResearchPaper
            ? candidate.metadata.authors
            : candidate.metadata.authors.filter { $0.provenance == .embeddedMetadata }
        let credits = acceptedAuthors.enumerated().map { index, author in
            CreatorCredit(
                position: index,
                displayName: author.displayName,
                familyName: author.familyName,
                provenance: author.provenance
            )
        }
        let acceptsParsedDate = isResearchPaper
            || candidate.metadata.publicationYearProvenance == .embeddedMetadata
        let publicationYear = acceptsParsedDate ? candidate.metadata.publicationYear : nil
        let publicationYearProvenance = acceptsParsedDate
            ? candidate.metadata.publicationYearProvenance
            : nil
        let paper = Paper(
            fingerprint: candidate.fingerprint,
            title: candidate.metadata.title,
            titleProvenance: candidate.metadata.titleProvenance,
            publicationYear: publicationYear,
            publicationYearProvenance: publicationYearProvenance,
            doi: isResearchPaper ? candidate.metadata.doi : nil,
            doiProvenance: isResearchPaper ? candidate.metadata.doiProvenance : nil,
            arxivID: isResearchPaper ? candidate.metadata.arxivID : nil,
            arxivIDProvenance: isResearchPaper ? candidate.metadata.arxivIDProvenance : nil,
            kind: kind,
            storageMode: storageMode,
            bookmarkData: bookmarkData,
            managedRelativePath: managedRelativePath,
            sourceFilename: candidate.url.lastPathComponent,
            rememberedLocation: rememberedLocation,
            sourceFileSize: candidate.fileSize,
            sourceModificationDate: candidate.modificationDate,
            pageCount: candidate.metadata.pageCount,
            hasSelectableText: candidate.metadata.hasSelectableText,
            authorCredits: credits
        )
        do {
            context.insert(paper)
            if let destinationCollection {
                paper.collections.append(destinationCollection)
            }
            try save()
            return paper
        } catch {
            context.rollback()
            throw error
        }
    }

    public func paperIdentitySnapshots() throws -> [PaperIdentitySnapshot] {
        try context.fetch(FetchDescriptor<Paper>()).map { paper in
            PaperIdentitySnapshot(
                id: paper.id,
                fingerprint: paper.fingerprint,
                kind: paper.kind,
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
                authorDisplayNames: paper.authorCredits.sorted { $0.position < $1.position }.map(\.displayName)
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
        let targetDate = values.publicationYear == before.publicationYear
            ? before.documentDate
            : values.publicationYear.flatMap { DocumentDate(year: $0) }
        let targetDateProvenance = values.publicationYear == before.publicationYear
            ? before.documentDateProvenance
            : values.publicationYear.map { _ in MetadataProvenance.userEntry }
        let target = PaperInfoSnapshot(
            paperID: paperID,
            title: values.title,
            titleProvenance: values.title == before.title ? before.titleProvenance : .userEntry,
            documentDate: targetDate,
            documentDateProvenance: targetDateProvenance,
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
        guard (snapshot.documentDate == nil) == (snapshot.documentDateProvenance == nil),
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
            documentDate: snapshot.documentDate,
            documentDateProvenance: snapshot.documentDateProvenance,
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
    public func createTextAnnotation(
        paperID: UUID,
        anchor: TextAnnotationAnchor,
        color: HighlightColor,
        note: String = ""
    ) throws -> Annotation {
        guard let annotation = try createTextAnnotations(
            paperID: paperID,
            anchors: [anchor],
            color: color,
            note: note
        ).first else {
            throw LibraryRepositoryError.invalidAnnotationAnchor
        }
        return annotation
    }

    @discardableResult
    public func createTextAnnotations(
        paperID: UUID,
        anchors: [TextAnnotationAnchor],
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
              anchors.allSatisfy({ $0.isValid(pageCount: paper.pageCount) }) else {
            throw LibraryRepositoryError.invalidAnnotationAnchor
        }

        do {
            let annotations = try anchors.map { anchor in
                let annotation = try Annotation(textAnchor: anchor, color: color, note: note, paper: paper)
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

    @discardableResult
    public func createAreaAnnotation(
        paperID: UUID,
        anchor: AreaAnnotationAnchor,
        color: HighlightColor,
        note: String = ""
    ) throws -> Annotation {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        guard anchor.isValid(pageCount: paper.pageCount) else {
            throw LibraryRepositoryError.invalidAnnotationAnchor
        }

        do {
            let annotation = try Annotation(areaAnchor: anchor, color: color, note: note, paper: paper)
            context.insert(annotation)
            try context.save()
            return annotation
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

    public func updateAnnotationColor(
        annotationID: UUID,
        color: HighlightColor
    ) throws {
        guard let annotation = try annotation(id: annotationID) else {
            throw LibraryRepositoryError.annotationNotFound
        }
        guard annotation.paper?.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        guard annotation.color != color else { return }
        annotation.color = color
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func updateTextAnnotationAnchor(
        annotationID: UUID,
        anchor: TextAnnotationAnchor
    ) throws {
        try updateAnnotationAnchor(annotationID: annotationID, kind: .textHighlight) { annotation, paper in
            guard anchor.isValid(pageCount: paper.pageCount) else {
                throw LibraryRepositoryError.invalidAnnotationAnchor
            }
            try annotation.replaceTextAnchor(anchor)
        }
    }

    public func updateAreaAnnotationAnchor(
        annotationID: UUID,
        anchor: AreaAnnotationAnchor
    ) throws {
        try updateAnnotationAnchor(annotationID: annotationID, kind: .area) { annotation, paper in
            guard anchor.isValid(pageCount: paper.pageCount) else {
                throw LibraryRepositoryError.invalidAnnotationAnchor
            }
            try annotation.replaceAreaAnchor(anchor)
        }
    }

    private func updateAnnotationAnchor(
        annotationID: UUID,
        kind: AnnotationKind,
        apply: (Annotation, Paper) throws -> Void
    ) throws {
        guard let annotation = try annotation(id: annotationID) else {
            throw LibraryRepositoryError.annotationNotFound
        }
        guard let paper = annotation.paper, paper.sourceState == .available else {
            throw LibraryRepositoryError.annotationsUnavailable
        }
        guard annotation.kind == kind else {
            throw LibraryRepositoryError.invalidAnnotationAnchor
        }
        do {
            try apply(annotation, paper)
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
            let annotations = try snapshotPapers.map { snapshot, paper in
                let annotation = try annotation(from: snapshot, paper: paper)
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
                try recordVerifiedSourceAccess(
                    documentID: paperID,
                    fileSize: access.verifiedFileSize,
                    modificationDate: access.verifiedModificationDate
                )
            }
            return access
        } catch let error as PaperSourceAccessError {
            try recordSourceAccessFailure(documentID: paperID, error: error)
            throw error
        }
    }

    public func recordVerifiedSourceAccess(
        documentID: UUID,
        fileSize: Int64,
        modificationDate: Date?
    ) throws {
        guard let document = try document(id: documentID) else {
            throw LibraryRepositoryError.documentNotFound
        }
        try markSourceAvailable(
            document,
            fileSize: fileSize,
            modificationDate: modificationDate
        )
    }

    public func recordSourceAccessFailure(
        documentID: UUID,
        error: PaperSourceAccessError
    ) throws {
        guard let document = try document(id: documentID) else {
            throw LibraryRepositoryError.documentNotFound
        }
        let previousState = document.sourceState
        document.sourceState = switch error {
        case .sourceUnavailable: .sourceUnavailable
        case .sourceMissing: .brokenReference
        case .sourceChanged: .sourceChanged
        case .libraryCopyMissing: .libraryCopyMissing
        }
        do {
            try save()
        } catch {
            document.sourceState = previousState
            context.rollback()
            throw error
        }
    }

    public func convertReferencedPaperToManagedCopy(
        paperID: UUID,
        expectedFingerprint: Data,
        managedRelativePath: String,
        fileSize: Int64,
        modificationDate: Date?
    ) throws {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.storageMode == .referenced, paper.sourceState == .available else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        guard paper.fingerprint == expectedFingerprint else {
            throw LibraryRepositoryError.contentIdentityMismatch
        }
        guard !managedRelativePath.isEmpty,
              URL(fileURLWithPath: managedRelativePath).lastPathComponent == managedRelativePath else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        let previousStorage = PaperStorageSnapshot(paper: paper)
        paper.storageMode = .managedCopy
        paper.bookmarkData = nil
        paper.managedRelativePath = managedRelativePath
        paper.rememberedLocation = nil
        paper.sourceFileSize = fileSize
        paper.sourceModificationDate = modificationDate
        paper.sourceState = .available
        do {
            try save()
        } catch {
            context.rollback()
            previousStorage.restore(on: paper)
            throw error
        }
    }

    public func convertManagedPaperToReferenced(
        paperID: UUID,
        expectedFingerprint: Data,
        bookmarkData: Data,
        rememberedLocation: String,
        sourceFilename: String,
        fileSize: Int64,
        modificationDate: Date?
    ) throws {
        guard let paper = try paper(id: paperID) else {
            throw LibraryRepositoryError.paperNotFound
        }
        guard paper.storageMode == .managedCopy, paper.sourceState == .available else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        guard paper.fingerprint == expectedFingerprint else {
            throw LibraryRepositoryError.contentIdentityMismatch
        }
        guard !bookmarkData.isEmpty,
              !rememberedLocation.isEmpty,
              !sourceFilename.isEmpty else {
            throw LibraryRepositoryError.incompatibleStorageMode
        }
        let previousStorage = PaperStorageSnapshot(paper: paper)
        paper.storageMode = .referenced
        paper.bookmarkData = bookmarkData
        paper.managedRelativePath = nil
        paper.rememberedLocation = rememberedLocation
        paper.sourceFilename = sourceFilename
        paper.sourceFileSize = fileSize
        paper.sourceModificationDate = modificationDate
        paper.sourceState = .available
        do {
            try save()
        } catch {
            context.rollback()
            previousStorage.restore(on: paper)
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

    public func removeDocuments(
        documentIDs: [UUID],
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> [RemovedPaperSnapshot] {
        var seenDocumentIDs = Set<UUID>()
        let orderedDocumentIDs = documentIDs.filter {
            seenDocumentIDs.insert($0).inserted
        }
        guard !orderedDocumentIDs.isEmpty else { return [] }

        let documents = try orderedDocumentIDs.map { documentID in
            guard let document = try paper(id: documentID) else {
                throw LibraryRepositoryError.paperNotFound
            }
            return document
        }

        var managedStore = suppliedManagedStore
        var stagedManagedCopyByDocumentID: [UUID: Bool] = [:]

        func restoreStagedManagedCopies() throws {
            guard let managedStore else { return }
            for document in documents.reversed()
                where stagedManagedCopyByDocumentID[document.id] == true {
                guard let relativePath = document.managedRelativePath else {
                    throw LibraryRepositoryError.incompatibleStorageMode
                }
                try managedStore.restoreFromRecovery(
                    relativePath: relativePath,
                    paperID: document.id
                )
            }
        }

        do {
            for document in documents where document.storageMode == .managedCopy {
                guard let relativePath = document.managedRelativePath else {
                    throw LibraryRepositoryError.incompatibleStorageMode
                }
                if managedStore == nil {
                    managedStore = try ManagedPaperStore.applicationSupport()
                }
                stagedManagedCopyByDocumentID[document.id] = try managedStore?.stageForRecovery(
                    relativePath: relativePath,
                    paperID: document.id
                ) ?? false
            }
        } catch {
            let operationError = error
            try restoreStagedManagedCopies()
            throw operationError
        }

        let snapshots = documents.map { document in
            RemovedPaperSnapshot(
                paper: document,
                managedCopyWasStaged: stagedManagedCopyByDocumentID[document.id] == true
            )
        }
        for document in documents {
            context.delete(document)
        }

        do {
            try context.save()
            return snapshots
        } catch {
            let saveError = error
            context.rollback()
            try restoreStagedManagedCopies()
            throw saveError
        }
    }

    public func removePaper(
        paperID: UUID,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> RemovedPaperSnapshot {
        guard let snapshot = try removeDocuments(
            documentIDs: [paperID],
            managedStore: suppliedManagedStore
        ).first else {
            throw LibraryRepositoryError.paperNotFound
        }
        return snapshot
    }

    @discardableResult
    public func restoreRemovedDocuments(
        snapshots: [RemovedPaperSnapshot],
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> [Document] {
        guard !snapshots.isEmpty else { return [] }
        var snapshotIDs = Set<UUID>()
        for snapshot in snapshots {
            guard snapshotIDs.insert(snapshot.id).inserted,
                  try paper(id: snapshot.id) == nil else {
                throw LibraryRepositoryError.incompatibleStorageMode
            }
        }

        var managedStore = suppliedManagedStore
        var restoredManagedCopyIDs = Set<UUID>()

        func restageRestoredManagedCopies() throws {
            guard let managedStore else { return }
            for snapshot in snapshots.reversed()
                where restoredManagedCopyIDs.contains(snapshot.id) {
                guard let relativePath = snapshot.managedRelativePath else {
                    throw LibraryRepositoryError.incompatibleStorageMode
                }
                _ = try managedStore.stageForRecovery(
                    relativePath: relativePath,
                    paperID: snapshot.id
                )
            }
        }

        do {
            for snapshot in snapshots
                where snapshot.storageMode == .managedCopy && snapshot.managedCopyWasStaged {
                guard let relativePath = snapshot.managedRelativePath else {
                    throw LibraryRepositoryError.incompatibleStorageMode
                }
                if managedStore == nil {
                    managedStore = try ManagedPaperStore.applicationSupport()
                }
                try managedStore?.restoreFromRecovery(
                    relativePath: relativePath,
                    paperID: snapshot.id
                )
                restoredManagedCopyIDs.insert(snapshot.id)
            }
        } catch {
            let operationError = error
            try restageRestoredManagedCopies()
            throw operationError
        }

        do {
            let availableCollections = try context.fetch(FetchDescriptor<Collection>())
            var restoredDocuments: [Document] = []
            for snapshot in snapshots {
                let creatorCredits = snapshot.authorCredits.map { creator in
                    CreatorCredit(
                        id: creator.id,
                        position: creator.position,
                        displayName: creator.displayName,
                        familyName: creator.familyName,
                        provenance: creator.provenance
                    )
                }
                let document = Document(
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
                    kind: snapshot.kind,
                    documentDate: snapshot.documentDate,
                    documentNote: snapshot.documentNote,
                    storageMode: snapshot.storageMode,
                    sourceState: snapshot.sourceState,
                    bookmarkData: snapshot.bookmarkData,
                    managedRelativePath: snapshot.managedRelativePath,
                    sourceFilename: snapshot.sourceFilename,
                    rememberedLocation: snapshot.rememberedLocation,
                    sourceFileSize: snapshot.sourceFileSize,
                    sourceModificationDate: snapshot.sourceModificationDate,
                    pageCount: snapshot.pageCount,
                    hasSelectableText: snapshot.hasSelectableText,
                    dateAdded: snapshot.dateAdded,
                    authorCredits: creatorCredits
                )
                document.lastOpenedAt = snapshot.lastOpenedAt
                document.lastPageIndex = snapshot.lastPageIndex
                document.lastViewport = snapshot.lastViewport
                document.lastZoomScale = snapshot.lastZoomScale
                document.isInspectorPresented = snapshot.isInspectorPresented
                document.documentDateProvenance = snapshot.documentDateProvenance
                let collectionIDs = Set(snapshot.collectionIDs)
                document.collections = availableCollections.filter {
                    collectionIDs.contains($0.id)
                }

                context.insert(document)
                for annotationSnapshot in snapshot.annotations {
                    let annotation = try annotation(from: annotationSnapshot, paper: document)
                    annotation.updatedAt = annotationSnapshot.updatedAt
                    context.insert(annotation)
                }
                restoredDocuments.append(document)
            }
            try context.save()
            return restoredDocuments
        } catch {
            let saveError = error
            context.rollback()
            try restageRestoredManagedCopies()
            throw saveError
        }
    }

    @discardableResult
    public func restoreRemovedPaper(
        snapshot: RemovedPaperSnapshot,
        managedStore suppliedManagedStore: ManagedPaperStore? = nil
    ) throws -> Paper {
        guard let document = try restoreRemovedDocuments(
            snapshots: [snapshot],
            managedStore: suppliedManagedStore
        ).first else {
            throw LibraryRepositoryError.paperNotFound
        }
        return document
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

    private func annotation(from snapshot: AnnotationSnapshot, paper: Paper) throws -> Annotation {
        switch snapshot.kind {
        case .textHighlight:
            guard let anchor = snapshot.textAnchor,
                  anchor.isValid(pageCount: paper.pageCount) else {
                throw LibraryRepositoryError.invalidAnnotationAnchor
            }
            return try Annotation(
                id: snapshot.id,
                textAnchor: anchor,
                color: snapshot.color,
                note: snapshot.note,
                createdAt: snapshot.createdAt,
                paper: paper
            )
        case .area:
            guard let anchor = snapshot.areaAnchor,
                  anchor.isValid(pageCount: paper.pageCount) else {
                throw LibraryRepositoryError.invalidAnnotationAnchor
            }
            return try Annotation(
                id: snapshot.id,
                areaAnchor: anchor,
                color: snapshot.color,
                note: snapshot.note,
                createdAt: snapshot.createdAt,
                paper: paper
            )
        }
    }

    private func paperInfoSnapshot(for paper: Paper) -> PaperInfoSnapshot {
        PaperInfoSnapshot(
            paperID: paper.id,
            title: paper.title,
            titleProvenance: paper.titleProvenance,
            documentDate: paper.documentDate,
            documentDateProvenance: paper.documentDateProvenance,
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
            paper.documentDate = target.documentDate
            paper.documentDateProvenance = target.documentDateProvenance
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

    private func requiredDocuments(ids documentIDs: [UUID]) throws -> [Document] {
        let requestedIDs = Set(documentIDs)
        guard !requestedIDs.isEmpty else { return [] }
        let documents = try context.fetch(FetchDescriptor<Document>()).filter {
            requestedIDs.contains($0.id)
        }
        guard documents.count == requestedIDs.count else {
            throw LibraryRepositoryError.documentNotFound
        }
        return documents
    }

    private func validatedCollectionName(_ name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw LibraryRepositoryError.invalidCollectionName
        }
        return normalized
    }

    private func ensureCollectionNameIsAvailable(
        _ name: String,
        excluding excludedID: UUID? = nil
    ) throws {
        let conflicts = try context.fetch(FetchDescriptor<Collection>()).contains { collection in
            collection.id != excludedID
                && collection.name.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !conflicts else {
            throw LibraryRepositoryError.duplicateCollectionName
        }
    }
}

private struct PaperStorageSnapshot {
    let storageMode: PaperStorageMode
    let bookmarkData: Data?
    let managedRelativePath: String?
    let rememberedLocation: String?
    let sourceFilename: String
    let sourceFileSize: Int64
    let sourceModificationDate: Date?
    let sourceState: PaperSourceState

    init(paper: Paper) {
        storageMode = paper.storageMode
        bookmarkData = paper.bookmarkData
        managedRelativePath = paper.managedRelativePath
        rememberedLocation = paper.rememberedLocation
        sourceFilename = paper.sourceFilename
        sourceFileSize = paper.sourceFileSize
        sourceModificationDate = paper.sourceModificationDate
        sourceState = paper.sourceState
    }

    func restore(on paper: Paper) {
        paper.storageMode = storageMode
        paper.bookmarkData = bookmarkData
        paper.managedRelativePath = managedRelativePath
        paper.rememberedLocation = rememberedLocation
        paper.sourceFilename = sourceFilename
        paper.sourceFileSize = sourceFileSize
        paper.sourceModificationDate = sourceModificationDate
        paper.sourceState = sourceState
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
    public let kind: AnnotationKind
    public let pageIndex: Int
    public let quadrilaterals: Data?
    public let selectedText: String?
    public let areaRect: Data?
    public let color: HighlightColor
    public let note: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(annotation: Annotation, paperID: UUID) {
        id = annotation.id
        self.paperID = paperID
        kind = annotation.kind
        pageIndex = annotation.pageIndex
        quadrilaterals = annotation.quadrilaterals
        selectedText = annotation.selectedText
        areaRect = annotation.areaRect
        color = annotation.color
        note = annotation.note
        createdAt = annotation.createdAt
        updatedAt = annotation.updatedAt
    }

    public var textAnchor: TextAnnotationAnchor? {
        guard kind == .textHighlight,
              let quadrilaterals,
              let selectedText,
              let decoded = try? AnnotationQuadrilateralCoding.decode(quadrilaterals) else {
            return nil
        }
        return TextAnnotationAnchor(
            pageIndex: pageIndex,
            quadrilaterals: decoded,
            selectedText: selectedText
        )
    }

    public var areaAnchor: AreaAnnotationAnchor? {
        guard kind == .area,
              let areaRect,
              let decoded = try? AnnotationRectCoding.decode(areaRect) else {
            return nil
        }
        return AreaAnnotationAnchor(pageIndex: pageIndex, rect: decoded)
    }

    public static func == (lhs: AnnotationSnapshot, rhs: AnnotationSnapshot) -> Bool {
        lhs.id == rhs.id
            && lhs.paperID == rhs.paperID
            && lhs.kind == rhs.kind
            && lhs.textAnchor == rhs.textAnchor
            && lhs.areaAnchor == rhs.areaAnchor
            && lhs.color == rhs.color
            && lhs.note == rhs.note
            && lhs.createdAt == rhs.createdAt
            && lhs.updatedAt == rhs.updatedAt
    }
}
