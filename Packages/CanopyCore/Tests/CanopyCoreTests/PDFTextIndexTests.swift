import AppKit
import CoreText
import Foundation
import Testing
@testable import CanopyCore

@Suite("Offline PDF text index")
struct PDFTextIndexTests {
    @Test("indexed page text returns a page-linked search snippet")
    func indexesAndSearchesPageText() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let key = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xA1, count: 32),
            formatVersion: 1
        )

        _ = try await index.prepare(key, totalPageCount: 2)
        _ = try await index.storePageText(
            "The cambium carries nutrients through the tree.",
            pageIndex: 1,
            for: key
        )
        _ = try await index.storePageText("A cover page", pageIndex: 0, for: key)
        _ = try await index.markReady(key)

        let matches = try await index.search(
            "cambium nutrients",
            formatVersion: 1,
            fingerprints: [key.fingerprint]
        )

        let match = try #require(matches.first)
        #expect(match.key == key)
        #expect(match.pageIndex == 1)
        #expect(match.pageNumber == 2)
        #expect(match.snippet.localizedCaseInsensitiveContains("cambium carries nutrients"))
    }

    @Test("an exact duplicate reuses a completed fingerprint and version index")
    func exactDuplicateReusesCompletedIndex() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let key = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xB2, count: 32),
            formatVersion: 3
        )

        let firstPreparation = try await index.prepare(key, totalPageCount: 1)
        _ = try await index.storePageText("Shared exact-duplicate text", pageIndex: 0, for: key)
        _ = try await index.markReady(key)
        let duplicatePreparation = try await index.prepare(key, totalPageCount: 1)

        #expect(firstPreparation.disposition == .created)
        #expect(duplicatePreparation.disposition == .reused)
        #expect(duplicatePreparation.status.lifecycle == .ready)
        #expect(duplicatePreparation.status.indexedPageCount == 1)
    }

    @Test("incomplete page progress resumes after reopening the durable store")
    func resumesIncompleteProgressAfterReopen() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let key = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xC3, count: 32),
            formatVersion: 1
        )
        let firstProcess = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        _ = try await firstProcess.prepare(key, totalPageCount: 3)
        _ = try await firstProcess.storePageText("Second page first", pageIndex: 1, for: key)

        let relaunchedProcess = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let preparation = try await relaunchedProcess.prepare(key, totalPageCount: 3)

        #expect(preparation.disposition == .resumable)
        #expect(preparation.status.lifecycle == .indexing)
        #expect(preparation.status.indexedPageCount == 1)
        #expect(preparation.status.nextPageIndex == 0)
    }

    @Test("rebuilding a format clears its pages and returns it to pending")
    func rebuildClearsOnlyRequestedFormat() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let fingerprint = Data(repeating: 0xD4, count: 32)
        let oldFormat = try PDFTextIndexKey(fingerprint: fingerprint, formatVersion: 1)
        let newFormat = try PDFTextIndexKey(fingerprint: fingerprint, formatVersion: 2)
        _ = try await index.prepare(oldFormat, totalPageCount: 1)
        _ = try await index.storePageText("legacy tokenizer result", pageIndex: 0, for: oldFormat)
        _ = try await index.markReady(oldFormat)
        _ = try await index.prepare(newFormat, totalPageCount: 1)
        _ = try await index.storePageText("current tokenizer result", pageIndex: 0, for: newFormat)
        _ = try await index.markReady(newFormat)

        let rebuilt = try await index.rebuild(newFormat, totalPageCount: 2)

        #expect(rebuilt.lifecycle == .pending)
        #expect(rebuilt.totalPageCount == 2)
        #expect(rebuilt.indexedPageCount == 0)
        #expect(rebuilt.nextPageIndex == 0)
        #expect(try await index.search("current", formatVersion: 2).isEmpty)
        #expect(try await index.search("legacy", formatVersion: 1).count == 1)
    }

    @Test("source unavailability retains completed searchable page text")
    func unavailableSourceRetainsSearchableText() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let key = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xE5, count: 32),
            formatVersion: 1
        )
        _ = try await index.prepare(key, totalPageCount: 1)
        _ = try await index.storePageText(
            "Offline external drive lecture content",
            pageIndex: 0,
            for: key
        )
        _ = try await index.markReady(key)

        let unavailable = try await index.markNeedsSource(key)
        let matches = try await index.search(
            "external drive",
            formatVersion: 1,
            fingerprints: [key.fingerprint]
        )

        #expect(unavailable.lifecycle == .needsSource)
        #expect(unavailable.indexedPageCount == 1)
        #expect(matches.map(\.pageIndex) == [0])
    }

    @Test("a ready older format remains searchable until the replacement is ready")
    func searchesReadyFallbackDuringVersionCutover() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let fingerprint = Data(repeating: 0xE6, count: 32)
        let oldKey = try PDFTextIndexKey(fingerprint: fingerprint, formatVersion: 1)
        let replacementKey = try PDFTextIndexKey(fingerprint: fingerprint, formatVersion: 2)
        _ = try await index.prepare(oldKey, totalPageCount: 1)
        _ = try await index.storePageText("retained offline syllabus", pageIndex: 0, for: oldKey)
        _ = try await index.markReady(oldKey)
        _ = try await index.prepare(replacementKey, totalPageCount: 1)
        _ = try await index.markNeedsSource(replacementKey)

        let matches = try await index.search(
            "offline syllabus",
            formatVersion: 2,
            fingerprints: [fingerprint]
        )

        #expect(matches.map(\.key) == [oldKey])
    }

    @Test("body search caps each fingerprint before applying the global limit")
    func searchLimitIsFairAcrossFingerprints() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let first = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xE7, count: 32),
            formatVersion: 1
        )
        let second = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0xE8, count: 32),
            formatVersion: 1
        )
        _ = try await index.prepare(first, totalPageCount: 8)
        for pageIndex in 0..<8 {
            _ = try await index.storePageText(
                "shared search phrase on page \(pageIndex)",
                pageIndex: pageIndex,
                for: first
            )
        }
        _ = try await index.markReady(first)
        _ = try await index.prepare(second, totalPageCount: 1)
        _ = try await index.storePageText("shared search phrase in another document", pageIndex: 0, for: second)
        _ = try await index.markReady(second)

        let matches = try await index.search(
            "shared search phrase",
            formatVersion: 1,
            limit: 4,
            perFingerprintLimit: 2
        )

        #expect(Set(matches.map { $0.key.fingerprint }) == [first.fingerprint, second.fingerprint])
        #expect(matches.count <= 4)
    }

    @Test("a deletion tombstone survives reopening until index data is removed")
    func deletionQueueIsDurable() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let fingerprint = Data(repeating: 0xE9, count: 32)
        let firstProcess = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        try await firstProcess.enqueueDeletion(forFingerprint: fingerprint)

        let relaunchedProcess = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        #expect(try await relaunchedProcess.pendingDeletionFingerprints() == [fingerprint])
        try await relaunchedProcess.deleteAllIndexData(forFingerprint: fingerprint)
        #expect(try await relaunchedProcess.pendingDeletionFingerprints().isEmpty)
    }

    @Test("removing the final fingerprint deletes every format while preserving other sources")
    func deletingFinalFingerprintRemovesAllVersions() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let removedFingerprint = Data(repeating: 0xF6, count: 32)
        let retainedFingerprint = Data(repeating: 0x17, count: 32)
        let removedV1 = try PDFTextIndexKey(fingerprint: removedFingerprint, formatVersion: 1)
        let removedV2 = try PDFTextIndexKey(fingerprint: removedFingerprint, formatVersion: 2)
        let retained = try PDFTextIndexKey(fingerprint: retainedFingerprint, formatVersion: 2)
        for (key, text) in [
            (removedV1, "first private corpus"),
            (removedV2, "second private corpus"),
            (retained, "retained private corpus")
        ] {
            _ = try await index.prepare(key, totalPageCount: 1)
            _ = try await index.storePageText(text, pageIndex: 0, for: key)
            _ = try await index.markReady(key)
        }

        try await index.deleteAllIndexData(forFingerprint: removedFingerprint)

        #expect(try await index.status(for: removedV1) == nil)
        #expect(try await index.status(for: removedV2) == nil)
        #expect(try await index.search("first", formatVersion: 1).isEmpty)
        #expect(try await index.search("second", formatVersion: 2).isEmpty)
        #expect(try await index.search("retained", formatVersion: 2).count == 1)
    }

    @Test("a failed job preserves progress and exposes its recovery reason")
    func failedJobRetainsProgressAndReason() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let key = try PDFTextIndexKey(
            fingerprint: Data(repeating: 0x28, count: 32),
            formatVersion: 1
        )
        _ = try await index.prepare(key, totalPageCount: 2)
        _ = try await index.storePageText("completed before failure", pageIndex: 0, for: key)

        let failed = try await index.markFailed(key, reason: "Page 2 could not be decoded")

        #expect(failed.lifecycle == .failed)
        #expect(failed.indexedPageCount == 1)
        #expect(failed.nextPageIndex == 1)
        #expect(failed.failureDescription == "Page 2 could not be decoded")
    }

    @Test("activity status can be listed for only the current index format")
    func listsCurrentFormatStatuses() async throws {
        let fixture = try TextIndexFixture()
        defer { fixture.remove() }
        let index = try PDFTextIndexStore(databaseURL: fixture.databaseURL)
        let currentVersion = PDFTextIndexFormat.currentVersion
        let fingerprint = Data(repeating: 0x39, count: 32)
        let oldKey = try PDFTextIndexKey(
            fingerprint: fingerprint,
            formatVersion: currentVersion + 1
        )
        let currentKey = try PDFTextIndexKey(
            fingerprint: fingerprint,
            formatVersion: currentVersion
        )
        _ = try await index.prepare(oldKey, totalPageCount: 4)
        _ = try await index.prepare(currentKey, totalPageCount: 2)

        let statuses = try await index.statuses(formatVersion: currentVersion)

        #expect(currentVersion > 0)
        #expect(statuses.map(\.key) == [currentKey])
        #expect(statuses.first?.lifecycle == .pending)
    }

    @Test("PDFKit extraction returns selectable text with its zero-based page link")
    func extractsPageLinkedPDFText() async throws {
        let fixture = try TextLayerPDFFixture(pages: [
            "Lecture opening concepts",
            "Lecture conclusion about vascular cambium"
        ])
        defer { fixture.remove() }
        let extractor = try PDFKitPageTextExtractor(url: fixture.url)

        let pageCount = await extractor.pageCount
        let page = try await extractor.extractPage(at: 1)

        #expect(pageCount == 2)
        #expect(page.pageIndex == 1)
        #expect(page.text.localizedCaseInsensitiveContains("vascular cambium"))
    }
}

private struct TextIndexFixture {
    let directory: URL
    let databaseURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        databaseURL = directory.appendingPathComponent("PDFTextIndex.sqlite")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct TextLayerPDFFixture {
    let directory: URL
    let url: URL

    init(pages: [String]) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("Lecture.pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for text in pages {
            context.beginPDFPage(nil)
            let font = NSFont.systemFont(ofSize: 18)
            let attributedText = NSAttributedString(string: text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attributedText)
            context.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
