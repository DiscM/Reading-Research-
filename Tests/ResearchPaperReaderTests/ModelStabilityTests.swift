import Foundation
import Testing
@testable import ResearchPaperReader

struct ModelStabilityTests {
    @Test func legacyLibraryEntriesDefaultToResearchPaper() throws {
        let paper = makePaper(title: "Legacy Paper")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(paper)) as? [String: Any]
        )
        object.removeValue(forKey: "documentKind")

        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Paper.self, from: data)

        #expect(decoded.documentKind == .researchPaper)
        #expect(decoded.title == "Legacy Paper")
    }

    @Test func documentKindSurvivesPersistenceRoundTrip() throws {
        var notes = makePaper(title: "Week 4 Notes")
        notes.documentKind = .studyNotes

        let data = try JSONEncoder().encode(notes)
        let decoded = try JSONDecoder().decode(Paper.self, from: data)

        #expect(decoded.documentKind == .studyNotes)
    }

    @Test func pendingFullTextDebounceDoesNotMatchEveryDocument() {
        let papers = [
            makePaper(title: "Climate Systems", text: "atmospheric circulation"),
            makePaper(title: "Linear Algebra", text: "matrix decomposition"),
        ]

        let results = papers.filtered(searchText: "climate", debouncedSearch: "", status: nil)

        #expect(results.map(\.title) == ["Climate Systems"])
    }

    @Test func markdownResultsParseIntoStructuredBlocks() {
        let document = MarkdownDocument("""
        ## Key ideas

        - **First** item
        - Second item

        > Supporting context

        ```swift
        let value = 1
        ```
        """)

        #expect(document.blocks == [
            .heading(level: 2, text: "Key ideas"),
            .unorderedList(["**First** item", "Second item"]),
            .quote("Supporting context"),
            .code("let value = 1"),
        ])
    }

    @Test func readingProgressIsBackwardCompatibleAndMarksWorkInProgress() throws {
        var paper = makePaper(title: "Reading Fixture")
        paper.allTextPageOffsets = [0, 100, 200, 300]
        let date = Date(timeIntervalSince1970: 1_000)

        #expect(paper.lastReadPage == nil)
        #expect(!paper.canResumeReading)

        paper.recordReadingProgress(page: 3, at: date)

        #expect(paper.lastReadPage == 3)
        #expect(paper.lastReadAt == date)
        #expect(paper.status == .reading)
        #expect(paper.canResumeReading)
        #expect(paper.readingProgress == 0.75)
    }

    @Test func paperTagsAndNotesModificationWorks() throws {
        var paper = makePaper(title: "Test Paper")
        paper.tags = ["ai", "swift"]
        
        let note = PaperNote(kind: .claim, quote: "a quote", body: "a body", page: 1)
        paper.notes = [note]
        
        #expect(paper.tags.count == 2)
        #expect(paper.notes.count == 1)
        
        paper.notes.remove(at: 0)
        #expect(paper.notes.isEmpty)
        
        let data = try JSONEncoder().encode(paper)
        let decoded = try JSONDecoder().decode(Paper.self, from: data)
        #expect(decoded.tags == ["ai", "swift"])
        #expect(decoded.notes.isEmpty)
    }

    @Test func areaNotesSurviveSerializationRoundTrip() throws {
        var paper = makePaper(title: "Area Note Paper")
        let note = PaperNote(
            kind: .evidence,
            quote: "",
            body: "Extracted area note body",
            page: 2,
            isAreaNote: true,
            rectX: 100.0,
            rectY: 200.0,
            rectWidth: 150.0,
            rectHeight: 80.0,
            imageFileName: "crop_123.png"
        )
        paper.notes = [note]
        
        let data = try JSONEncoder().encode(paper)
        let decoded = try JSONDecoder().decode(Paper.self, from: data)
        
        #expect(decoded.notes.count == 1)
        let decodedNote = decoded.notes[0]
        #expect(decodedNote.isAreaNote)
        #expect(decodedNote.rectX == 100.0)
        #expect(decodedNote.rectY == 200.0)
        #expect(decodedNote.rectWidth == 150.0)
        #expect(decodedNote.rectHeight == 80.0)
        #expect(decodedNote.imageFileName == "crop_123.png")
    }

    private func makePaper(title: String, text: String = "") -> Paper {
        Paper(
            title: title,
            authors: "",
            year: "",
            abstract: "",
            filePath: "/tmp/fixture.pdf",
            allText: text
        )
    }
}
