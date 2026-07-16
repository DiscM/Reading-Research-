import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
@testable import CanopyCore

@Suite("Source PDF metadata parsing")
struct PDFDocumentAnalyzerTests {
    @Test("page count and selectable-text capability do not retain later-page text as metadata")
    func recordsDocumentCapabilitiesWithoutUsingLaterPagesForMetadata() throws {
        let fixture = try MultiPagePDFFixture(
            filename: "Filename Fallback.pdf",
            pages: [
                [],
                ["A Later Page Must Not Become the Paper Title"],
                ["Additional selectable body text"]
            ]
        )
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Filename Fallback")
        #expect(metadata.titleProvenance == .filenameFallback)
        #expect(metadata.pageCount == 3)
        #expect(metadata.hasSelectableText)
    }

    @Test("a PDF without a text layer records that text is not selectable")
    func recordsMissingSelectableText() throws {
        let fixture = try MultiPagePDFFixture(
            filename: "Scanned Research.pdf",
            pages: [[], []]
        )
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.pageCount == 2)
        #expect(!metadata.hasSelectableText)
    }

    @Test("prominent multiline first-page title is preferred over a running header")
    func extractsProminentMultilineTitleAndAuthors() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Proceedings of Testing 2026", size: 23, y: 740),
            .init("A Robust Title Across", size: 24, y: 680),
            .init("Multiple Lines", size: 24, y: 648),
            .init("Ada Lovelace and Alan Turing", size: 14, y: 610),
            .init("Department of Computer Science", size: 11, y: 586),
            .init("Abstract", size: 12, y: 540),
            .init("This paper tests metadata extraction.", size: 11, y: 516)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "A Robust Title Across Multiple Lines")
        #expect(metadata.titleProvenance == .firstPage)
        #expect(metadata.authors.map(\.displayName) == ["Ada Lovelace", "Alan Turing"])
        #expect(metadata.authors.allSatisfy { $0.provenance == .firstPage })
    }

    @Test("embedded title whitespace and unambiguous comma-separated authors are normalized")
    func normalizesEmbeddedTitleAndAuthors() throws {
        let fixture = try MetadataPDFFixture(
            lines: [.init("Body text", size: 11, y: 700)],
            title: "  A Study of\nRobust Metadata  ",
            author: "Ada Lovelace, Alan Turing"
        )
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "A Study of Robust Metadata")
        #expect(metadata.titleProvenance == .embeddedMetadata)
        #expect(metadata.authors.map(\.displayName) == ["Ada Lovelace", "Alan Turing"])
        #expect(metadata.authors.allSatisfy { $0.provenance == .embeddedMetadata })
    }

    @Test("generated source-filename metadata falls through to the first-page title")
    func ignoresGeneratedEmbeddedTitle() throws {
        let fixture = try MetadataPDFFixture(
            lines: [
                .init("Reliable Metadata for Research Papers", size: 22, y: 680),
                .init("Grace Hopper", size: 13, y: 640),
                .init("Abstract", size: 12, y: 590),
                .init("Metadata should describe the paper.", size: 11, y: 566)
            ],
            title: "Microsoft Word - manuscript.docx",
            author: "Google Docs"
        )
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Reliable Metadata for Research Papers")
        #expect(metadata.titleProvenance == .firstPage)
        #expect(metadata.authors.map(\.displayName) == ["Grace Hopper"])
        #expect(metadata.authors.allSatisfy { $0.provenance == .firstPage })
    }

    @Test("explicit first-page labels work without font-size contrast")
    func extractsLabeledFirstPageMetadata() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Title: A Labeled Research Paper", size: 12, y: 700),
            .init("Authors: Katherine Johnson and Dorothy Vaughan", size: 12, y: 676),
            .init("Abstract", size: 12, y: 630),
            .init("Labels provide deterministic metadata.", size: 12, y: 606)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "A Labeled Research Paper")
        #expect(metadata.titleProvenance == .firstPage)
        #expect(metadata.authors.map(\.displayName) == ["Katherine Johnson", "Dorothy Vaughan"])
    }

    @Test("a title beginning with Title hyphen is not mistaken for an explicit label")
    func preservesTitleHyphenPrefix() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Title-Based Metadata Extraction", size: 18, y: 700),
            .init("Mary Jackson", size: 12, y: 666),
            .init("Abstract", size: 10, y: 620)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Title-Based Metadata Extraction")
        #expect(metadata.authors.map(\.displayName) == ["Mary Jackson"])
    }

    @Test("a short first page still recognizes a title with clear font prominence")
    func extractsTitleFromShortFirstPage() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Concise Research", size: 18, y: 700),
            .init("Barbara Liskov", size: 12, y: 666),
            .init("Abstract", size: 12, y: 620)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Concise Research")
        #expect(metadata.titleProvenance == .firstPage)
        #expect(metadata.authors.map(\.displayName) == ["Barbara Liskov"])
    }

    @Test("a rotated arXiv margin header does not outrank the title or become an author")
    func ignoresRotatedArxivMarginHeader() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("arXiv:2504.19874v1 [cs.LG] 28 Apr 2025", size: 20, x: 18, y: 230, rotation: .pi / 2),
            .init("Turbo Metadata: Reliable Parsing with", size: 17, y: 680),
            .init("Layout-aware PDF Analysis", size: 17, y: 658),
            .init("Amir Zandieh", size: 12, x: 130, y: 620),
            .init("Canopy Research", size: 12, x: 120, y: 606),
            .init("amir@example.com", size: 12, x: 115, y: 592),
            .init("Majid Daliri", size: 12, x: 330, y: 620),
            .init("Example University", size: 12, x: 310, y: 606),
            .init("majid@example.com", size: 12, x: 305, y: 592),
            .init("Abstract", size: 10, y: 540)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Turbo Metadata: Reliable Parsing with Layout-aware PDF Analysis")
        #expect(metadata.titleProvenance == .firstPage)
        #expect(metadata.authors.map(\.displayName) == ["Amir Zandieh", "Majid Daliri"])
    }

    @Test("wrapped author lines are joined and ORCID markers are removed")
    func extractsWrappedAuthorsWithORCIDMarkers() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Natively Reliable Metadata Extraction", size: 18, y: 680),
            .init("Vittorio Fra[0000−0001−9175−2838], Benedetto Leto[0009−0007−8891−5051], Andrea", size: 10, y: 640),
            .init("Pignata[0009−0001−4278−8348], Enrico Macii[0000−0001−9046−5618], and Gianvito", size: 10, y: 628),
            .init("Urgese[0000−0003−2672−7593]", size: 10, y: 616),
            .init("Politecnico di Torino, Italy", size: 9, y: 590),
            .init("authors@example.com", size: 9, y: 578),
            .init("Abstract. This paper validates wrapped Author Credits.", size: 9, y: 540)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.authors.map(\.displayName) == [
            "Vittorio Fra",
            "Benedetto Leto",
            "Andrea Pignata",
            "Enrico Macii",
            "Gianvito Urgese"
        ])
        #expect(metadata.authors.allSatisfy { $0.provenance == .firstPage })
    }

    @Test("affiliations, footnote marks, and publication dates are excluded from authors")
    func excludesAuthorBlockNoise() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Clean Author Block Extraction", size: 18, y: 680),
            .init("Ali Safa", size: 12, x: 130, y: 640),
            .init("ESAT, KU Leuven, Belgium", size: 10, x: 125, y: 626),
            .init("ali@example.com", size: 10, x: 125, y: 612),
            .init("Insu Han∗", size: 12, x: 350, y: 640),
            .init("Adobe Research", size: 10, x: 345, y: 626),
            .init("insu@example.com", size: 10, x: 345, y: 612),
            .init("July 19, 2024", size: 12, x: 260, y: 570),
            .init("Abstract", size: 10, y: 530)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.authors.map(\.displayName) == ["Ali Safa", "Insu Han"])
    }

    @Test("a numbered section heading cannot replace a title when there is no abstract heading")
    func stopsTitleCandidatesAtNumberedSectionHeading() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("A Modest but Correct Paper Title", size: 14, y: 700),
            .init("Evelyn Boyd Granville", size: 11, y: 670),
            .init("1 Introduction", size: 18, y: 620),
            .init("The paper begins here.", size: 10, y: 596)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "A Modest but Correct Paper Title")
        #expect(metadata.authors.map(\.displayName) == ["Evelyn Boyd Granville"])
    }

    @Test("title words that resemble headings remain valid and em-dash abstracts end front matter")
    func distinguishesTitlesFromSectionHeadings() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Introduction to Reliable PDF Metadata", size: 18, y: 700),
            .init("Margaret Hamilton", size: 12, y: 666),
            .init("Abstract—This paper studies metadata parsing.", size: 10, y: 620),
            .init("2. Related Work", size: 16, y: 570)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Introduction to Reliable PDF Metadata")
        #expect(metadata.authors.map(\.displayName) == ["Margaret Hamilton"])
    }

    @Test("comma-bearing locations are not appended to a real author")
    func rejectsCommaBearingNonAuthorText() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("A Paper With One Listed Author", size: 18, y: 700),
            .init("Grace Hopper", size: 12, y: 660),
            .init("Google LLC, Mountain View, United States", size: 11, y: 640),
            .init("Abstract", size: 10, y: 620)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "A Paper With One Listed Author")
        #expect(metadata.authors.map(\.displayName) == ["Grace Hopper"])
    }

    @Test("a complete comma-separated author row starts after the preceding complete author")
    func separatesCompleteAuthorRows() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Reliable Author Row Boundaries", size: 18, y: 700),
            .init("Grace Hopper", size: 12, y: 660),
            .init("Ada Lovelace, Alan Turing", size: 12, y: 640),
            .init("Abstract", size: 10, y: 600)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.authors.map(\.displayName) == ["Grace Hopper", "Ada Lovelace", "Alan Turing"])
    }

    @Test("title-cased document labels are not inferred as authors")
    func rejectsDocumentLabelsAsAuthors() throws {
        let fixture = try MetadataPDFFixture(lines: [
            .init("Heal the Planet", size: 20, y: 700),
            .init("Game Design Document", size: 12, y: 662),
            .init("Earth Month Card Game Prototype", size: 12, y: 638),
            .init("Working Title", size: 12, y: 614),
            .init("Session Use", size: 12, y: 590),
            .init("Summary", size: 10, y: 550)
        ])
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "Heal the Planet")
        #expect(metadata.authors.isEmpty)
    }
}

private struct MultiPagePDFFixture {
    let directory: URL
    let url: URL

    init(filename: String, pages: [[String]]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for lines in pages {
            context.beginPDFPage(nil)
            for (index, text) in lines.enumerated() {
                let font = NSFont(name: "Times New Roman", size: 18) ?? .systemFont(ofSize: 18)
                let value = NSAttributedString(string: text, attributes: [.font: font])
                context.textPosition = CGPoint(x: 72, y: 700 - CGFloat(index * 28))
                CTLineDraw(CTLineCreateWithAttributedString(value), context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct MetadataPDFFixture {
    struct Line {
        let text: String
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let rotation: CGFloat

        init(
            _ text: String,
            size: CGFloat,
            x: CGFloat = 72,
            y: CGFloat,
            rotation: CGFloat = 0
        ) {
            self.text = text
            self.size = size
            self.x = x
            self.y = y
            self.rotation = rotation
        }
    }

    let directory: URL
    let url: URL

    init(lines: [Line], title: String? = nil, author: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("metadata.pdf")
        let renderedURL = directory.appendingPathComponent("rendered.pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(renderedURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.beginPDFPage(nil)
        for line in lines {
            let font = NSFont(name: "Times New Roman", size: line.size) ?? .systemFont(ofSize: line.size)
            let value = NSAttributedString(string: line.text, attributes: [.font: font])
            context.saveGState()
            context.translateBy(x: line.x, y: line.y)
            context.rotate(by: line.rotation)
            context.textPosition = .zero
            CTLineDraw(CTLineCreateWithAttributedString(value), context)
            context.restoreGState()
        }
        context.endPDFPage()
        context.closePDF()

        if title != nil || author != nil {
            guard let document = PDFDocument(url: renderedURL) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var attributes: [PDFDocumentAttribute: Any] = [:]
            attributes[.titleAttribute] = title
            attributes[.authorAttribute] = author
            document.documentAttributes = attributes
            guard document.write(to: url) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try FileManager.default.removeItem(at: renderedURL)
        } else {
            try FileManager.default.moveItem(at: renderedURL, to: url)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
