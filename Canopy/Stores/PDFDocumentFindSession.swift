@preconcurrency import Foundation
import Observation
@preconcurrency import PDFKit

@MainActor
@Observable
final class PDFDocumentFindSession {
    private(set) var matches: [PDFSelection] = []
    private(set) var isFinding = false
    private(set) var resultsVersion = UUID()

    @ObservationIgnored private weak var document: PDFDocument?
    @ObservationIgnored private let observerBag = PDFDocumentFindObserverBag()
    @ObservationIgnored private var generation = UUID()

    func start(query: String, in document: PDFDocument) {
        cancel(clearResults: true)

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        let generation = UUID()
        self.generation = generation
        self.document = document
        isFinding = true

        let center = NotificationCenter.default
        observerBag.observers.append(center.addObserver(
            forName: .PDFDocumentDidFindMatch,
            object: document,
            queue: .main
        ) { [weak self] notification in
            guard let selection = notification.userInfo?[PDFDocumentFoundSelectionKey] as? PDFSelection,
                  selection.string?.range(of: query, options: .caseInsensitive) != nil else {
                return
            }
            let transferredSelection = PDFDocumentFindSelectionTransfer(selection)
            MainActor.assumeIsolated {
                guard let self,
                      self.generation == generation else {
                    return
                }
                self.matches.append(transferredSelection.value)
                self.resultsVersion = UUID()
            }
        })
        observerBag.observers.append(center.addObserver(
            forName: .PDFDocumentDidEndFind,
            object: document,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.finish()
            }
        })

        document.beginFindString(query, withOptions: .caseInsensitive)
    }

    func cancel(clearResults: Bool = false) {
        generation = UUID()
        removeObservers()
        document?.cancelFindString()
        document = nil
        isFinding = false
        if clearResults {
            matches = []
            resultsVersion = UUID()
        }
    }

    private func finish() {
        removeObservers()
        document = nil
        isFinding = false
    }

    private func removeObservers() {
        for observer in observerBag.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observerBag.observers.removeAll()
    }
}

private struct PDFDocumentFindSelectionTransfer: @unchecked Sendable {
    let value: PDFSelection

    init(_ value: PDFSelection) {
        self.value = value
    }
}

private final class PDFDocumentFindObserverBag: @unchecked Sendable {
    var observers: [NSObjectProtocol] = []

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
