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

    @Test @MainActor func evidenceTablesPopulateProvenanceAndDeduplicateAddedSources() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearchPaperReaderEvidenceTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var first = paper(title: "Forest Methods", text: "The sample included 80 forest plots. The key finding was improved biodiversity.")
        first.sections = [PaperSection(kind: .results, title: "Results", text: "Biodiversity improved across restored plots.", order: 1, page: 4)]
        let second = paper(title: "Solar Commons", text: "The dataset contains 120 community energy projects.")
        let store = PaperStore(baseDirectory: directory)
        store.papers = [first, second]
        store.createEvidenceTable(name: "Regenerative Systems", paperIDs: [first.id])
        let tableID = try #require(store.researchState.evidenceTables.first?.id)

        let firstFinding = try #require(store.researchState.evidenceTables[0].rows[0].cells.first {
            cell in store.researchState.evidenceTables[0].columns.first(where: { $0.id == cell.columnID })?.name == "Key finding"
        })
        #expect(firstFinding.value == "Biodiversity improved across restored plots")
        #expect(firstFinding.quote == firstFinding.value)

        store.addPapers([first.id, second.id], toEvidenceTable: tableID)
        store.addPapers([second.id], toEvidenceTable: tableID)
        #expect(store.researchState.evidenceTables[0].rows.count == 2)

        #expect(store.addEvidenceColumn(name: "Policy context", to: tableID))
        #expect(!store.addEvidenceColumn(name: "policy CONTEXT", to: tableID))
        let addedColumn = try #require(store.researchState.evidenceTables[0].columns.last)
        #expect(store.researchState.evidenceTables[0].rows.allSatisfy {
            $0.cells.contains(where: { $0.columnID == addedColumn.id })
        })
        #expect(EvidenceService.csv(for: store.researchState.evidenceTables[0], papers: store.papers)
            .contains("\"Regenerative Systems\"") == false)
        #expect(EvidenceService.csv(for: store.researchState.evidenceTables[0], papers: store.papers)
            .contains("\"Forest Methods\""))
        store.researchState.evidenceTables[0].rows[0].cells[0].value = "Restoration | resilience\nmeasures"
        let markdown = EvidenceService.markdown(
            for: store.researchState.evidenceTables[0],
            papers: store.papers
        )
        #expect(markdown.hasPrefix("# Regenerative Systems\n\n| Source | Authors | Year |"))
        #expect(markdown.contains("| Forest Methods |"))
        #expect(markdown.contains("Restoration \\| resilience<br>measures"))
        #expect(store.deleteEvidenceColumn(addedColumn.id, from: tableID))
        #expect(store.researchState.evidenceTables[0].rows.allSatisfy {
            !$0.cells.contains(where: { $0.columnID == addedColumn.id })
        })

        store.researchState.evidenceTables[0].rows[1].cells[2].value = ""
        store.populateEmptyEvidenceCells(in: tableID)
        #expect(store.researchState.evidenceTables[0].rows[1].cells[2].value.contains("120 community energy projects"))

        store.removePaper(first.id, fromEvidenceTable: tableID)
        #expect(store.researchState.evidenceTables[0].rows.map(\.paperID) == [second.id])

        store.createWorkspace(name: "Evidence Draft", paperIDs: [second.id], evidenceTableID: tableID)
        store.deleteEvidenceTable(tableID)
        #expect(store.researchState.evidenceTables.isEmpty)
        #expect(store.researchState.workspaces.first?.evidenceTableID == nil)
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

    @Test func semanticSearchExcludesReferenceSectionsAndBibliographyFallback() {
        var structured = paper(
            title: "Structured Paper",
            text: "The experiment measured soil moisture.\nReferences\nPhotonic battery lattice optimization."
        )
        structured.sections = [
            PaperSection(
                kind: .results,
                title: "Results",
                text: "The experiment measured soil moisture across restored plots.",
                order: 0,
                page: 4
            ),
            PaperSection(
                kind: .references,
                title: "References",
                text: "Photonic battery lattice optimization. Journal of Energy Storage.",
                order: 1,
                page: 9
            ),
        ]

        let results = SemanticSearchService.search(
            query: "photonic battery lattice optimization",
            papers: [structured]
        )

        #expect(!results.contains { $0.text.localizedCaseInsensitiveContains("photonic battery") })

        let bodyResults = SemanticSearchService.search(
            query: "soil moisture restored plots",
            papers: [structured]
        )
        #expect(bodyResults.first?.text.contains("restored plots") == true)
    }

    @Test func semanticSearchStopsRawPageIndexingAtBibliographyHeading() {
        var unstructured = paper(
            title: "Unstructured Paper",
            text: "The publication body discusses coastal restoration.\n\nBibliography\nRare citation phrase zephyr quasar."
        )
        unstructured.allTextPageOffsets = [0]

        let results = SemanticSearchService.search(
            query: "rare citation phrase zephyr quasar",
            papers: [unstructured]
        )

        #expect(!results.contains { $0.text.localizedCaseInsensitiveContains("rare citation phrase") })
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

    @Test func citationGraphLinksReferencesByTitleAndYearWithoutDOI() {
        var source = paper(title: "Citing Work", text: "")
        source.sections = [PaperSection(
            kind: .references,
            title: "References",
            text: "[1] Smith, A. Local Research Systems. Research Tools. 2025.",
            order: 1,
            page: 8
        )]
        var target = paper(title: "Local Research Systems", text: "")
        target.year = "2025"

        let edges = CitationGraphService.edges(for: [source, target])

        #expect(edges.count == 1)
        #expect(edges[0].targetPaperID == target.id)
    }

    @Test func citationGraphRejectsFooterAddendumAndOrphanedAuthorFragments() {
        var source = paper(title: "Noisy PDF", text: "")
        source.sections = [PaperSection(
            kind: .references,
            title: "References",
            text: """
            [1] & Smith, Jones. Addendum and footer references. 2025.
            [2] Addendum, Editorial Office. Copyright and all rights reserved. 2024.
            [3] Smith, A. Local Research Systems. Research Tools. 2025.
            Footer [4] Jones, B. This marker is not at the beginning. 2023.
            """,
            order: 1,
            page: 8
        )]

        let references = CitationGraphService.extractReferences(from: source)

        #expect(references.count == 1)
        #expect(references.first?.title == "Local Research Systems")
    }

    @Test func citationGraphReconstructsWrappedReferencesAndKeepsTheFullPublicationTitle() throws {
        var source = paper(title: "Wrapped Bibliography", text: "")
        source.sections = [PaperSection(
            kind: .references,
            title: "References",
            text: """
            [1] Eloundou, T., Manning, S., Mishkin, P. & Rock, D. GPTs are GPTs: Labor market impact
            potential of LLMs. Science 384, 1306–1308 (2024).
            16
            [2] Goldfarb, A., Taska, B. & Teodoridis, F. Could machine learning be a general purpose
            technology? A comparison of emerging technologies using data from online job postings.
            Research Policy 52, 104653 (2023).
            """,
            order: 1,
            page: 8
        )]

        let references = CitationGraphService.extractReferences(from: source)

        #expect(references.count == 2)
        #expect(references[0].title == "GPTs are GPTs: Labor market impact potential of LLMs")
        #expect(references[0].authors.contains("& Rock, D"))
        #expect(references[0].venue.contains("Science 384"))
        #expect(references[1].title == "Could machine learning be a general purpose technology? A comparison of emerging technologies using data from online job postings")

        let externalPaper = DiscoveryPaper(title: references[1].title)
        let url = try #require(DiscoveryLinkService.onlineURL(for: externalPaper))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
        #expect(query == references[1].title)
    }

    @Test func citationGraphDoesNotPromoteAmpersandAuthorContinuationsToTitles() {
        var source = paper(title: "Split Authors", text: "")
        source.sections = [PaperSection(
            kind: .references,
            title: "References",
            text: """
            [1] Smith, A. & Jones, B. Forest Interfaces for Research Discovery. Ecology Tools. 2025.
            [2] & Footer, Name. A footer-shaped fragment with a year. 2024.
            """,
            order: 1,
            page: 9
        )]

        let references = CitationGraphService.extractReferences(from: source)

        #expect(references.count == 1)
        #expect(references.first?.authors == "Smith, A. & Jones, B")
        #expect(references.first?.title == "Forest Interfaces for Research Discovery")
    }

    @Test func citationGraphDoesNotTreatDocumentTailAsReferencesWithoutAHeading() {
        let source = paper(
            title: "No Reference Section",
            text: "Main text\n[1] & Name, Name. Addendum and footer references. 2025."
        )

        #expect(CitationGraphService.extractReferences(from: source).isEmpty)
    }

    @Test func discoveryFeedbackPersistsAndDefaultsForOlderState() throws {
        var state = ResearchState()
        state.discoveryFeedback["10.1/example"] = false
        let reloaded = try JSONDecoder().decode(ResearchState.self, from: JSONEncoder().encode(state))
        #expect(reloaded.discoveryFeedback["10.1/example"] == false)

        let legacy = try JSONDecoder().decode(ResearchState.self, from: Data(#"{}"#.utf8))
        #expect(legacy.discoveryFeedback.isEmpty)
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

    @Test func discoveryOnlineLinksResolveDOIsAndPopulateCrossRefSearch() throws {
        let doiPaper = DiscoveryPaper(title: "A DOI Paper", doi: "https://doi.org/10.1000/example")
        #expect(DiscoveryLinkService.onlineURL(for: doiPaper)?.absoluteString == "https://doi.org/10.1000/example")

        let titlePaper = DiscoveryPaper(title: "Ecological Interfaces for Local AI")
        let url = try #require(DiscoveryLinkService.onlineURL(for: titlePaper))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/search/works")
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == titlePaper.title)
        #expect(components.queryItems?.first(where: { $0.name == "from_ui" })?.value == "yes")
    }

    @Test @MainActor func recommendedPapersSaveOncePersistAndCanBeRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResearchPaperReaderDiscoveryTests-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recommendation = DiscoveryPaper(
            title: "Regenerative Research Interfaces",
            authors: "Rivera, Sam",
            year: "2026",
            venue: "Journal of Research Tools",
            doi: "10.1000/regenerative"
        )
        let store = PaperStore(baseDirectory: directory)

        #expect(store.saveDiscoveryCitation(recommendation))
        #expect(!store.saveDiscoveryCitation(recommendation))
        #expect(store.isDiscoveryCitationSaved(recommendation))
        #expect(store.savedDiscoveryPapers.count == 1)
        store.saveResearchState()

        let reloaded = PaperStore(baseDirectory: directory)
        #expect(reloaded.isDiscoveryCitationSaved(recommendation))
        #expect(reloaded.savedDiscoveryPapers.first?.title == recommendation.title)
        reloaded.removeDiscoveryCitation(recommendation)
        #expect(!reloaded.isDiscoveryCitationSaved(recommendation))
    }

    @Test @MainActor func alertsRejectInvalidDOIsAndDuplicateQueries() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PaperStore(baseDirectory: directory)

        #expect(!store.createAlert(name: "Bad DOI", kind: .citations, query: "not-a-doi"))
        #expect(store.createAlert(name: "First", kind: .query, query: "solarpunk interfaces"))
        #expect(!store.createAlert(name: "Duplicate", kind: .query, query: "Solarpunk Interfaces"))
        #expect(store.researchState.alerts.count == 1)
    }

    private func paper(title: String, text: String) -> Paper {
        Paper(title: title, authors: "", year: "", abstract: "", filePath: "/tmp/\(UUID()).pdf", allText: text)
    }
}
