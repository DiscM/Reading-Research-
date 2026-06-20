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

    @Test func legacyTextNotesDefaultAreaFields() throws {
        let json = """
        {
          "id": "4D36E96E-7B6A-4E8A-9B2A-1D0D760741A1",
          "kind": "Claim",
          "quote": "Legacy quote",
          "body": "Legacy body",
          "page": 3,
          "createdAt": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let note = try decoder.decode(PaperNote.self, from: Data(json.utf8))

        #expect(!note.isAreaNote)
        #expect(note.rectX == nil)
        #expect(note.imageFileName == nil)
        #expect(note.body == "Legacy body")
    }

    @Test func documentKindInferenceWorks() {
        // DOI/arXiv present
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "", doi: "10.1234/test", arxivId: "") == .researchPaper)
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "", doi: "", arxivId: "arXiv:2101.12345") == .researchPaper)
        
        // Slides keywords in name/text
        #expect(PaperStore.inferDocumentKind(filename: "lecture-1.pdf", text: "", doi: "", arxivId: "") == .lectureSlides)
        #expect(PaperStore.inferDocumentKind(filename: "week-3_slides.pdf", text: "", doi: "", arxivId: "") == .lectureSlides)
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "learning objectives: understand swift development", doi: "", arxivId: "") == .lectureSlides)
        
        // Notes keywords in name/text
        #expect(PaperStore.inferDocumentKind(filename: "my-handout.pdf", text: "", doi: "", arxivId: "") == .studyNotes)
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "this is class notes for week 1", doi: "", arxivId: "") == .studyNotes)
        
        // Book chapter keywords
        #expect(PaperStore.inferDocumentKind(filename: "textbook-ch1.pdf", text: "", doi: "", arxivId: "") == .bookChapter)
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "see chapter 4 for details", doi: "", arxivId: "") == .bookChapter)
        
        // Academic signals >= 2
        #expect(PaperStore.inferDocumentKind(filename: "doc", text: "abstract introduction references", doi: "", arxivId: "") == .researchPaper)
        
        // General fallback
        #expect(PaperStore.inferDocumentKind(filename: "doc.pdf", text: "some generic text content", doi: "", arxivId: "") == .generalPDF)
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
