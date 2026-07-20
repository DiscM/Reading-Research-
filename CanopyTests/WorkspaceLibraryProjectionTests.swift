import CanopyCore
import Foundation
import Testing
@testable import Canopy

@Suite("General workspace projection")
struct WorkspaceLibraryProjectionTests {
    private let biologyID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let reviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    @Test("navigation destinations scope one shared set of Documents")
    func navigationDestinationsScopeDocuments() {
        let documents = fixtures

        #expect(project(documents, to: .allDocuments).map(\.title) == [
            "Alberts Chapter 15", "Lecture 08", "Week 7 Notes"
        ])
        #expect(project(documents, to: .recent).map(\.title) == [
            "Alberts Chapter 15", "Lecture 08"
        ])
        #expect(project(documents, to: .unfiled).map(\.title) == ["Week 7 Notes"])
        #expect(project(documents, to: .collection(biologyID)).map(\.title) == [
            "Alberts Chapter 15", "Lecture 08"
        ])
        #expect(project(documents, to: .collection(reviewID)).map(\.title) == ["Lecture 08"])
    }

    @Test("an empty Kind filter means all Kinds and multiple selected Kinds form a union")
    func kindFilterSupportsAllAndMultipleKinds() {
        let allKinds = WorkspaceLibraryProjection(
            documents: fixtures,
            destination: .allDocuments,
            selectedKinds: [],
            sort: .init(field: .title, direction: .ascending)
        ).documents
        let studyMaterials = WorkspaceLibraryProjection(
            documents: fixtures,
            destination: .allDocuments,
            selectedKinds: [.lectureSlides, .classNotes],
            sort: .init(field: .title, direction: .ascending)
        ).documents

        #expect(allKinds.count == 3)
        #expect(studyMaterials.map(\.title) == ["Lecture 08", "Week 7 Notes"])
    }

    @Test("Document Date sorting keeps unknown dates last in either direction")
    func documentDateSortKeepsUnknownDatesLast() {
        let ascending = WorkspaceLibraryProjection(
            documents: fixtures,
            destination: .allDocuments,
            selectedKinds: [],
            sort: .init(field: .documentDate, direction: .ascending)
        ).documents
        let descending = WorkspaceLibraryProjection(
            documents: fixtures,
            destination: .allDocuments,
            selectedKinds: [],
            sort: .init(field: .documentDate, direction: .descending)
        ).documents

        #expect(ascending.map(\.title) == ["Alberts Chapter 15", "Lecture 08", "Week 7 Notes"])
        #expect(descending.map(\.title) == ["Lecture 08", "Alberts Chapter 15", "Week 7 Notes"])
    }

    @Test("Recently Opened sorting is deterministic and keeps unopened Documents last")
    func recentlyOpenedSortIsDeterministic() {
        let documents = fixtures + [
            item(
                id: "00000000-0000-0000-0000-000000000004",
                title: "Cell Atlas",
                kind: .generalDocument,
                lastOpenedAt: Date(timeIntervalSince1970: 300)
            )
        ]
        let result = WorkspaceLibraryProjection(
            documents: documents,
            destination: .allDocuments,
            selectedKinds: [],
            sort: .init(field: .recentlyOpened, direction: .descending)
        ).documents

        #expect(result.map(\.title) == [
            "Cell Atlas", "Lecture 08", "Alberts Chapter 15", "Week 7 Notes"
        ])
    }

    @Test("selection reconciliation removes Documents hidden by scope or filters")
    func selectionReconciliationKeepsVisibleDocuments() {
        let selected = Set(fixtures.map(\.id))
        let visible = WorkspaceLibraryProjection(
            documents: fixtures,
            destination: .unfiled,
            selectedKinds: [.classNotes],
            sort: .init(field: .title, direction: .ascending)
        ).documents

        #expect(WorkspaceDocumentSelection.reconciled(selected, visibleDocuments: visible) == Set(visible.map(\.id)))
    }

    @Test("multi-selection summarizes storage without changing Document identity")
    func multiSelectionSummarizesStorage() {
        let summary = WorkspaceMultiSelectionSummary(documents: fixtures)

        #expect(summary.documentCount == 3)
        #expect(summary.referencedCount == 2)
        #expect(summary.managedCopyCount == 1)
        #expect(summary.kinds == [.lectureSlides, .classNotes, .textbook])
    }

    @Test("Collection membership is checked, unchecked, or mixed across a selection")
    func collectionMembershipSupportsMixedState() {
        let documents = fixtures

        #expect(WorkspaceCollectionMembershipState.resolve(
            collectionID: biologyID,
            among: documents
        ) == .mixed)
        #expect(WorkspaceCollectionMembershipState.resolve(
            collectionID: reviewID,
            among: [documents[0]]
        ) == .checked)
        #expect(WorkspaceCollectionMembershipState.resolve(
            collectionID: UUID(uuidString: "00000000-0000-0000-0000-000000000999")!,
            among: documents
        ) == .unchecked)
    }

    private var fixtures: [WorkspaceDocumentListItem] {
        [
            item(
                id: "00000000-0000-0000-0000-000000000001",
                title: "Lecture 08",
                kind: .lectureSlides,
                documentDate: DocumentDate(year: 2026, month: 7, day: 18),
                lastOpenedAt: Date(timeIntervalSince1970: 200),
                collectionIDs: [biologyID, reviewID],
                storage: .referenced
            ),
            item(
                id: "00000000-0000-0000-0000-000000000002",
                title: "Week 7 Notes",
                kind: .classNotes,
                storage: .managedCopy
            ),
            item(
                id: "00000000-0000-0000-0000-000000000003",
                title: "Alberts Chapter 15",
                kind: .textbook,
                documentDate: DocumentDate(year: 2022),
                lastOpenedAt: Date(timeIntervalSince1970: 100),
                collectionIDs: [biologyID],
                storage: .referenced
            )
        ]
    }

    private func project(
        _ documents: [WorkspaceDocumentListItem],
        to destination: WorkspaceNavigationDestination
    ) -> [WorkspaceDocumentListItem] {
        WorkspaceLibraryProjection(
            documents: documents,
            destination: destination,
            selectedKinds: [],
            sort: .init(field: .title, direction: .ascending)
        ).documents
    }

    private func item(
        id: String,
        title: String,
        kind: DocumentKind,
        documentDate: DocumentDate? = nil,
        lastOpenedAt: Date? = nil,
        collectionIDs: Set<UUID> = [],
        storage: WorkspaceDocumentStorage = .referenced
    ) -> WorkspaceDocumentListItem {
        WorkspaceDocumentListItem(
            id: UUID(uuidString: id)!,
            title: title,
            kind: kind,
            creatorSummary: "",
            documentDate: documentDate,
            dateAdded: Date(timeIntervalSince1970: 50),
            lastOpenedAt: lastOpenedAt,
            collectionIDs: collectionIDs,
            collectionNames: [],
            storage: storage,
            attention: nil
        )
    }
}
