import AppKit
import CoreText
import XCTest

@MainActor
final class CanopyRelaunchUITests: XCTestCase {
    private let paperTitle = "Canopy UI Journey"
    private let highlightedText = "CanopySentinel"
    private let note = "Persists through a full relaunch"
    private var libraryID = UUID()
    private var pdfData = Data()
    private var app: XCUIApplication!

    func testAddReadHighlightNoteAndResumeAfterRelaunch() throws {
        continueAfterFailure = false
        libraryID = UUID()
        pdfData = try UIJourneyPDFFixture.make(
            title: paperTitle,
            pages: [
                "Opening page for the Canopy UI journey",
                highlightedText,
                "Closing page for the Canopy UI journey"
            ]
        )
        app = XCUIApplication()
        defer {
            cleanupTestLibraryThroughIsolatedLaunch()
        }
        launch(resetLibrary: true)

        let addPapers = app.buttons["add-papers-button"]
        XCTAssertTrue(addPapers.waitForExistence(timeout: 10))
        addPapers.click()

        let confirmAdd = app.buttons["confirm-add-papers-button"]
        XCTAssertTrue(confirmAdd.waitForExistence(timeout: 5))
        confirmAdd.click()

        let paperRow = app.descendants(matching: .any)["paper-row"].firstMatch
        XCTAssertTrue(paperRow.waitForExistence(timeout: 15))
        paperRow.click()

        let pageField = app.descendants(matching: .any)["reader-page-field"]
        XCTAssertTrue(pageField.waitForExistence(timeout: 10))
        replaceText(in: pageField, with: "2")
        pageField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue("2", in: pageField, timeout: 5))

        let zoomScale = app.descendants(matching: .any)["reader-zoom-scale"]
        XCTAssertTrue(zoomScale.waitForExistence(timeout: 5))
        let initialZoom = try XCTUnwrap(zoomScale.value as? String)
        let zoomIn = app.descendants(matching: .any)["reader-zoom-in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 2))
        zoomIn.click()
        XCTAssertTrue(waitForValueChange(from: initialZoom, in: zoomScale, timeout: 5))
        let expectedZoom = try XCTUnwrap(zoomScale.value as? String)

        selectTextOnCurrentPage()

        let addNote = app.descendants(matching: .any)["annotation-palette-add-note"]
        XCTAssertTrue(addNote.waitForExistence(timeout: 5))
        addNote.click()
        let create = app.descendants(matching: .any)["annotation-palette-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 2))
        create.click()

        let noteField = app.descendants(matching: .any)["annotation-note-field"].firstMatch
        XCTAssertTrue(noteField.waitForExistence(timeout: 8))
        replaceText(in: noteField, with: note)
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForValue(note, in: noteField, timeout: 5))

        let viewportY = app.descendants(matching: .any)["reader-viewport-y"]
        XCTAssertTrue(viewportY.waitForExistence(timeout: 5))
        let initialViewportY = try XCTUnwrap(viewportY.value as? String)
        let pdfView = app.descendants(matching: .any)["paper-pdf-view"]
        XCTAssertTrue(pdfView.waitForExistence(timeout: 3))
        pdfView.scroll(byDeltaX: 0, deltaY: 140)
        let initialViewportNumber = Double(initialViewportY)
        let expectedViewportY: Double
        if let settledViewportY = waitForStableNumericValue(
            in: viewportY,
            timeout: 2,
            accepting: { value in
                initialViewportNumber.map { abs(value - $0) > 0.5 } ?? true
            }
        ) {
            expectedViewportY = settledViewportY
        } else {
            pdfView.scroll(byDeltaX: 0, deltaY: -280)
            expectedViewportY = try XCTUnwrap(waitForStableNumericValue(
                in: viewportY,
                timeout: 5,
                accepting: { value in
                    initialViewportNumber.map { abs(value - $0) > 0.5 } ?? true
                }
            ))
        }
        XCTAssertTrue(waitForValue("2", in: pageField, timeout: 5))

        // Closing the window exercises the production onDisappear flush instead
        // of racing the reader-state debounce with a fixed delay.
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(app.windows["Canopy"], timeout: 5))
        app.terminate()

        launch(resetLibrary: false)
        let relaunchedPaperRow = app.descendants(matching: .any)["paper-row"].firstMatch
        XCTAssertTrue(relaunchedPaperRow.waitForExistence(timeout: 10))
        relaunchedPaperRow.click()

        let restoredPageField = app.descendants(matching: .any)["reader-page-field"]
        XCTAssertTrue(restoredPageField.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue("2", in: restoredPageField, timeout: 8))
        let restoredZoom = app.descendants(matching: .any)["reader-zoom-scale"]
        XCTAssertTrue(restoredZoom.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(expectedZoom, in: restoredZoom, timeout: 8))
        let restoredViewportY = app.descendants(matching: .any)["reader-viewport-y"]
        XCTAssertTrue(restoredViewportY.waitForExistence(timeout: 5))
        XCTAssertNotNil(waitForStableNumericValue(
            in: restoredViewportY,
            timeout: 8,
            accepting: { abs($0 - expectedViewportY) <= 1 }
        ))

        let quotation = app.descendants(matching: .any)["text-highlight-quotation"].firstMatch
        XCTAssertTrue(quotation.waitForExistence(timeout: 10))
        XCTAssertEqual(quotation.value as? String, highlightedText)
        let restoredNote = app.descendants(matching: .any)["annotation-note-field"].firstMatch
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(note, in: restoredNote, timeout: 5))
    }

    private func cleanupTestLibraryThroughIsolatedLaunch() {
        app.terminate()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment = launchEnvironment(
            resetLibrary: false,
            cleansLibrary: true
        )
        app.launch()
        _ = app.windows["Canopy"].waitForExistence(timeout: 5)
        app.terminate()
    }

    private func launch(resetLibrary: Bool) {
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment = launchEnvironment(resetLibrary: resetLibrary)
        app.launch()
        XCTAssertTrue(app.windows["Canopy"].waitForExistence(timeout: 10))
    }

    private func launchEnvironment(
        resetLibrary: Bool,
        cleansLibrary: Bool = false
    ) -> [String: String] {
        [
            "CANOPY_UI_TEST_MODE": "1",
            "CANOPY_UI_TEST_LIBRARY_ID": libraryID.uuidString,
            "CANOPY_UI_TEST_RESET_LIBRARY": resetLibrary ? "1" : "0",
            "CANOPY_UI_TEST_CLEANUP_LIBRARY": cleansLibrary ? "1" : "0",
            "CANOPY_UI_TEST_PDF_BASE64": pdfData.base64EncodedString()
        ]
    }

    private func selectTextOnCurrentPage() {
        let nativePDFText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", highlightedText)
        ).firstMatch
        if nativePDFText.waitForExistence(timeout: 3) {
            nativePDFText.doubleClick()
            return
        }

        let pdfView = app.descendants(matching: .any)["paper-pdf-view"]
        XCTAssertTrue(pdfView.waitForExistence(timeout: 3))
        let point = pdfView.coordinate(withNormalizedOffset: CGVector(dx: 0.34, dy: 0.13))
        point.doubleClick()
    }

    private func replaceText(in element: XCUIElement, with value: String) {
        element.click()
        element.typeKey("a", modifierFlags: .command)
        element.typeText(value)
    }

    private func waitForValue(_ expected: String, in element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return (element.value as? String) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForValueChange(
        from priorValue: String,
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let value = element.value as? String else { return false }
            return value != priorValue
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func waitForStableNumericValue(
        in element: XCUIElement,
        timeout: TimeInterval,
        stableFor: TimeInterval = 0.4,
        accepting: @escaping (Double) -> Bool
    ) -> Double? {
        var lastValue: Double?
        var stableSince = ProcessInfo.processInfo.systemUptime
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let rawValue = element.value as? String,
                  let value = Double(rawValue) else {
                return false
            }

            let now = ProcessInfo.processInfo.systemUptime
            if lastValue.map({ abs($0 - value) > 0.01 }) ?? true {
                lastValue = value
                stableSince = now
            }
            return accepting(value) && now - stableSince >= stableFor
        }
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        )
        return result == .completed ? lastValue : nil
    }

    private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }
}

private enum UIJourneyPDFFixture {
    static func make(title: String, pages: [String]) throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journey.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let metadata = [kCGPDFContextTitle: title] as CFDictionary
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, metadata) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (index, text) in pages.enumerated() {
            context.beginPDFPage(nil)
            draw(text, size: 18, at: CGPoint(x: 72, y: 700), in: context)
            draw("Page \(index + 1)", size: 11, at: CGPoint(x: 72, y: 60), in: context)
            context.endPDFPage()
        }
        context.closePDF()
        return try Data(contentsOf: url)
    }

    private static func draw(_ text: String, size: CGFloat, at point: CGPoint, in context: CGContext) {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let value = NSAttributedString(string: text, attributes: [.font: font])
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(value), context)
    }
}
