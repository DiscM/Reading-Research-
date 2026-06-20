import Foundation
import Testing
@testable import ResearchPaperReader

struct ResearchFeatureTests {
    @Test @MainActor func researchFeaturesPersistTogetherAndDeletionCleansReferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearchPaperReaderTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = paper(title: "First Source", text: "Semantic retrieval uses local vectors.")
        let second = paper(title: "Second Source", text: "Evidence tables compare methods.")
        let store = PaperStore(baseDirectory: directory)
        store.papers = [first, second]
        store.createCollection(name: "Thesis")
        let collectionID = try #require(store.researchState.collections.first?.id)
        store.setPaper(first.id, in: collectionID, included: true)
        store.createSmartFolder(name: "Vectors", rules: [SmartFolderRule(field: .allText, value: "vectors")])
        let report = try store.importCitations("""
        @article{fixture2026,
          title = {Persistent Citation},
          author = {Fixture, Test},
          year = {2026},
          doi = {10.1000/persist}
        }
        """)
        store.createEvidenceTable(name: "Comparison", paperIDs: [first.id, second.id])
        let tableID = try #require(store.researchState.evidenceTables.first?.id)
        store.createWorkspace(name: "Draft", paperIDs: [first.id, second.id], evidenceTableID: tableID)
        let workspaceID = try #require(store.researchState.workspaces.first?.id)
        store.generateOutline(for: workspaceID)
        store.createAlert(name: "Semantic", kind: .query, query: "semantic retrieval")
        store.save()
        store.saveResearchState()

        #expect(report == CitationImportReport(imported: 1, merged: 0))
        let reloaded = PaperStore(baseDirectory: directory)
        #expect(reloaded.papers.count == 2)
        #expect(reloaded.papersInCollection(collectionID).map(\.id) == [first.id])
        #expect(reloaded.researchState.smartFolders.count == 1)
        #expect(reloaded.researchState.citations.first?.doi == "10.1000/persist")
        #expect(reloaded.researchState.evidenceTables.first?.rows.count == 2)
        #expect(reloaded.researchState.workspaces.first?.outline.contains("# Draft") == true)
        #expect(reloaded.researchState.alerts.count == 1)

        reloaded.delete(first)
        #expect(reloaded.papersInCollection(collectionID).isEmpty)
        #expect(reloaded.researchState.evidenceTables.first?.rows.map(\.paperID) == [second.id])
        #expect(reloaded.researchState.workspaces.first?.paperIDs == [second.id])
    }

    @Test func researchStateDefaultsMissingFieldsForForwardMigration() throws {
        let data = Data(#"{"collections":[]}"#.utf8)
        let state = try JSONDecoder().decode(ResearchState.self, from: data)

        #expect(state.collections.isEmpty)
        #expect(state.smartFolders.isEmpty)
        #expect(state.citations.isEmpty)
        #expect(state.evidenceTables.isEmpty)
        #expect(state.workspaces.isEmpty)
        #expect(state.alerts.isEmpty)
    }

    @Test func smartFoldersCombineRulesWithoutChangingPapers() {
        var target = paper(title: "Local Language Models", text: "Private inference on a laptop")
        target.tags = ["AI"]
        target.status = .reading
        let other = paper(title: "Ocean Currents", text: "Thermohaline circulation")
        let folder = SmartFolder(
            name: "Active AI",
            rules: [
                SmartFolderRule(field: .tag, value: "ai"),
                SmartFolderRule(field: .status, value: "Reading"),
            ]
        )

        #expect(folder.matches(target))
        #expect(!folder.matches(other))
        #expect(target.tags == ["AI"])
    }

    @Test func bibTeXAndRISRoundTripAndDeduplicateByDOI() throws {
        let bibtex = """
        @article{smith2025local,
          title = {Local Research Systems},
          author = {Smith, Alex and Jones, Pat},
          year = {2025},
          journal = {Research Tools},
          doi = {10.1000/example}
        }
        """
        let parsed = try CitationService.parse(bibtex)
        let ris = CitationService.ris(for: parsed)
        let reparsed = try CitationService.parse(ris)
        let combined = CitationService.deduplicated(parsed + reparsed)

        #expect(parsed.count == 1)
        #expect(reparsed.count == 1)
        #expect(combined.count == 1)
        #expect(combined[0].title == "Local Research Systems")
        #expect(CitationService.bibTeX(for: combined).contains("10.1000/example"))
    }

    @Test func evidenceTableRetainsPaperAnchorsAndBuildsCitedOutline() {
        var source = paper(title: "Anchored Evidence", text: "The sample included 42 participants. A limitation was selection bias.")
        source.authors = "Rivera, Sam"
        source.year = "2026"
        source.sections = [
            PaperSection(kind: .method, title: "Method", text: "We used a longitudinal experiment.", order: 1, page: 2),
            PaperSection(kind: .results, title: "Results", text: "The intervention improved recall.", order: 2, page: 4),
        ]
        let table = EvidenceService.makeTable(name: "Review", papers: [source])
        let workspace = SynthesisWorkspace(name: "Review", paperIDs: [source.id], evidenceTableID: table.id)
        let outline = EvidenceService.outline(workspace: workspace, papers: [source], table: table)

        #expect(table.rows.count == 1)
        #expect(table.rows[0].paperID == source.id)
        #expect(table.rows[0].cells.contains { $0.value.contains("42 participants") })
        #expect(outline.contains("[@rivera2026anchored]"))
        #expect(outline.contains("The intervention improved recall"))
    }

    @Test func semanticSearchReturnsGroundedPaperAndPage() {
        var relevant = paper(title: "Neural Retrieval", text: "Vector embeddings improve semantic document retrieval and nearest neighbor search.")
        relevant.allTextPageOffsets = [0]
        let unrelated = paper(title: "Marine Biology", text: "Coral reefs support diverse ocean ecosystems.")

        let results = SemanticSearchService.search(query: "meaning based document search", papers: [unrelated, relevant])
        let answer = SemanticSearchService.groundedAnswer(question: "How is meaning-based search implemented?", results: results)

        #expect(results.first?.paperID == relevant.id)
        #expect(results.first?.page == 1)
        #expect(answer.contains("Neural Retrieval"))
    }

    @Test func citationGraphLinksReferencesToLocalDOI() {
        var source = paper(title: "Citing Work", text: "")
        source.sections = [PaperSection(
            kind: .references,
            title: "References",
            text: "[1] Smith, A. Local Research Systems. Research Tools. 2025. doi:10.1000/example",
            order: 1,
            page: 8
        )]
        var target = paper(title: "Local Research Systems", text: "")
        target.doi = "10.1000/example"

        let edges = CitationGraphService.edges(for: [source, target])

        #expect(edges.count == 1)
        #expect(edges[0].sourcePaperID == source.id)
        #expect(edges[0].targetPaperID == target.id)
    }

    @Test func discoveryProviderPayloadsDecodeIntoCommonResults() throws {
        let crossRef = Data(#"{"message":{"items":[{"DOI":"10.1/crossref","title":["CrossRef Result"],"author":[{"given":"Ada","family":"Lovelace"}],"published":{"date-parts":[[2026]]},"container-title":["Journal"],"is-referenced-by-count":7}]}}"#.utf8)
        let openAlex = Data(#"{"results":[{"id":"https://openalex.org/W1","title":"Citing Work","doi":"https://doi.org/10.1/citing","publication_year":2025,"cited_by_count":3,"authorships":[{"author":{"display_name":"Grace Hopper"}}],"primary_location":{"source":{"display_name":"Proceedings"}}}]}"#.utf8)

        let crossRefResults = try DiscoveryService.decodeCrossRefResults(crossRef)
        let openAlexResults = try DiscoveryService.decodeOpenAlexResults(openAlex)

        #expect(crossRefResults.first?.title == "CrossRef Result")
        #expect(crossRefResults.first?.authors == "Ada Lovelace")
        #expect(openAlexResults.first?.title == "Citing Work")
        #expect(openAlexResults.first?.doi == "10.1/citing")
        #expect(openAlexResults.first?.venue == "Proceedings")
    }

    private func paper(title: String, text: String) -> Paper {
        Paper(title: title, authors: "", year: "", abstract: "", filePath: "/tmp/\(UUID()).pdf", allText: text)
    }
}
