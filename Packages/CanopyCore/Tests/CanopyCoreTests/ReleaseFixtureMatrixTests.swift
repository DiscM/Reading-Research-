import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
@testable import CanopyCore

@Suite("Bounded v1 release fixture matrix")
struct ReleaseFixtureMatrixTests {
    @Test("representative large PDF remains bounded and reports pages and selectable text")
    func largePDF() throws {
        let fixture = try ReleasePDFFixture.large()
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)
        let byteCount = try fixture.fileSize()

        #expect(metadata.pageCount == 24)
        #expect(metadata.hasSelectableText)
        #expect(byteCount >= 4 * 1_024 * 1_024)
        #expect(byteCount <= 20 * 1_024 * 1_024)
    }

    @Test("scanned PDF is readable without enabling text-dependent behavior")
    func scannedPDF() throws {
        let fixture = try ReleasePDFFixture.scanned()
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.pageCount == 3)
        #expect(!metadata.hasSelectableText)
        #expect(metadata.title == "scanned fixture")
        #expect(metadata.titleProvenance == .filenameFallback)
    }

    @Test("malformed embedded metadata falls back without retaining producer noise")
    func malformedMetadataPDF() throws {
        let fixture = try ReleasePDFFixture.malformedMetadata()
        defer { fixture.remove() }

        let metadata = try PDFDocumentAnalyzer().analyze(fixture.url)

        #expect(metadata.title == "malformed metadata fallback")
        #expect(metadata.titleProvenance == .filenameFallback)
        #expect(metadata.authors.isEmpty)
        #expect(metadata.hasSelectableText)
    }

    @Test("missing, damaged, and password-protected PDFs report distinct Add Papers failures")
    func addPapersFailures() throws {
        let directory = try ReleasePDFFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingURL = directory.appendingPathComponent("missing-source.pdf")
        let damagedURL = directory.appendingPathComponent("damaged.pdf")
        try Data("not a PDF".utf8).write(to: damagedURL)
        let protectedFixture = try ReleasePDFFixture.passwordProtected(in: directory)

        let result = try AddBatchPreflight(analyzer: PDFDocumentAnalyzer()).run(
            urls: [missingURL, damagedURL, protectedFixture.url],
            existingPapers: []
        )

        let failures = Dictionary(uniqueKeysWithValues: result.failures.map {
            ($0.url.lastPathComponent, $0.message)
        })
        #expect(failures["missing-source.pdf"] == "The selected PDF could not be found.")
        #expect(failures["damaged.pdf"] == "The selected file is not a readable PDF.")
        #expect(failures["password-protected.pdf"] == "Password-protected PDFs are not supported in Canopy v1.")
    }

    @Test("modified managed source is rejected before reader state or annotations can apply")
    func modifiedSourcePDF() throws {
        let fixture = try ReleasePDFFixture.text(
            filename: "modified-source.pdf",
            pageTexts: ["Original research content"]
        )
        defer { fixture.remove() }
        let managedStore = ManagedPaperStore(
            rootURL: fixture.directory.appendingPathComponent("Managed", isDirectory: true)
        )
        let relativePath = try managedStore.copy(fixture.url)
        let managedURL = managedStore.rootURL.appendingPathComponent(relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: managedURL.path)
        let originalSize = try #require((attributes[.size] as? NSNumber)?.int64Value)
        let originalModificationDate = attributes[.modificationDate] as? Date
        let originalFingerprint = try DocumentFingerprint.sha256(of: managedURL)
        let paper = Paper(
            fingerprint: originalFingerprint,
            title: "Modified Source Fixture",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: originalSize,
            sourceModificationDate: originalModificationDate,
            pageCount: 1,
            hasSelectableText: true
        )

        let replacement = try ReleasePDFFixture.text(
            in: fixture.directory,
            filename: "replacement.pdf",
            pageTexts: ["Different research content with a different length"]
        )
        try FileManager.default.removeItem(at: managedURL)
        try FileManager.default.copyItem(at: replacement.url, to: managedURL)

        #expect(throws: PaperSourceAccessError.sourceChanged) {
            _ = try PaperSourceAccess(paper: paper, managedStore: managedStore)
        }
    }

    @Test("a previously added managed source reports Library Copy Missing after disappearance")
    func missingPersistedSourcePDF() throws {
        let fixture = try ReleasePDFFixture.text(
            filename: "persisted-source.pdf",
            pageTexts: ["Research content that was added successfully"]
        )
        defer { fixture.remove() }
        let managedStore = ManagedPaperStore(
            rootURL: fixture.directory.appendingPathComponent("Managed", isDirectory: true)
        )
        let relativePath = try managedStore.copy(fixture.url)
        let managedURL = managedStore.rootURL.appendingPathComponent(relativePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: managedURL.path)
        let paper = Paper(
            fingerprint: try DocumentFingerprint.sha256(of: managedURL),
            title: "Missing Persisted Source Fixture",
            storageMode: .managedCopy,
            managedRelativePath: relativePath,
            sourceFilename: fixture.url.lastPathComponent,
            sourceFileSize: try #require((attributes[.size] as? NSNumber)?.int64Value),
            sourceModificationDate: attributes[.modificationDate] as? Date,
            pageCount: 1,
            hasSelectableText: true
        )

        try FileManager.default.removeItem(at: managedURL)

        #expect(throws: PaperSourceAccessError.libraryCopyMissing) {
            _ = try PaperSourceAccess(paper: paper, managedStore: managedStore)
        }
    }
}

private struct ReleasePDFFixture {
    let directory: URL
    let url: URL

    static func large() throws -> Self {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("large-fixture.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let image = try deterministicNoiseImage(width: 1_536, height: 1_536)
        for pageIndex in 0..<24 {
            context.beginPDFPage(nil)
            if pageIndex == 0 {
                context.draw(image, in: CGRect(x: 72, y: 170, width: 468, height: 468))
            }
            draw("Bounded Large Fixture — Page \(pageIndex + 1)", size: 16, at: CGPoint(x: 72, y: 700), in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return Self(directory: directory, url: url)
    }

    static func scanned() throws -> Self {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("scanned-fixture.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for pageIndex in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(gray: CGFloat(pageIndex + 1) * 0.15, alpha: 1)
            context.fill(CGRect(x: 72, y: 120, width: 468, height: 552))
            context.setStrokeColor(gray: 0.9, alpha: 1)
            context.stroke(CGRect(x: 92, y: 140, width: 428, height: 512), width: 4)
            context.endPDFPage()
        }
        context.closePDF()
        return Self(directory: directory, url: url)
    }

    static func malformedMetadata() throws -> Self {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("malformed-metadata-fallback.pdf")
        let metadata: [CFString: Any] = [
            kCGPDFContextTitle: "10.1000/not-a-human-title",
            kCGPDFContextAuthor: "Microsoft Word"
        ]
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, metadata as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.beginPDFPage(nil)
        draw("ordinary body copy", size: 11, at: CGPoint(x: 72, y: 680), in: context)
        draw("with no prominent title block", size: 11, at: CGPoint(x: 72, y: 654), in: context)
        context.endPDFPage()
        context.closePDF()
        return Self(directory: directory, url: url)
    }

    static func passwordProtected(in directory: URL) throws -> Self {
        let source = try text(
            in: directory,
            filename: "unprotected-source.pdf",
            pageTexts: ["Protected research content"]
        )
        guard let document = PDFDocument(url: source.url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let protectedURL = directory.appendingPathComponent("password-protected.pdf")
        guard document.write(
            to: protectedURL,
            withOptions: [
                .ownerPasswordOption: "owner-password",
                .userPasswordOption: "reader-password"
            ]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return Self(directory: directory, url: protectedURL)
    }

    static func text(
        in directory: URL? = nil,
        filename: String,
        pageTexts: [String]
    ) throws -> Self {
        let directory = try directory ?? makeDirectory()
        let url = directory.appendingPathComponent(filename)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for text in pageTexts {
            context.beginPDFPage(nil)
            draw(text, size: 18, at: CGPoint(x: 72, y: 700), in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return Self(directory: directory, url: url)
    }

    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanopyReleaseFixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func fileSize() throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try #require((attributes[.size] as? NSNumber)?.int64Value)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func draw(_ text: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private static func deterministicNoiseImage(width: Int, height: Int) throws -> CGImage {
        var state: UInt32 = 0xC4A0_9E11
        var pixels = Data(count: width * height * 3)
        pixels.withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<(width * height * 3) {
                state = state &* 1_664_525 &+ 1_013_904_223
                bytes[index] = UInt8(truncatingIfNeeded: state >> 16)
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: width * 3,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return image
    }
}
