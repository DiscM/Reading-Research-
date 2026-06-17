import PDFKit
import SwiftUI

enum ZoomAction: Equatable {
    case `in`, out, fit
}

struct PDFReaderView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    @Binding var selectedPage: Int?
    var notes: [PaperNote]
    @Binding var navigateToPage: Int?
    @Binding var zoomFactor: CGFloat
    @Binding var zoomAction: ZoomAction?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = PDFDocument(url: url)
        let nc = NotificationCenter.default
        nc.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        nc.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        nc.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self

        if nsView.document?.documentURL != url {
            context.coordinator.cleanupAnnotations(in: nsView)
            nsView.document = PDFDocument(url: url)
            nsView.autoScales = true
        }

        context.coordinator.syncAnnotations(pdfView: nsView, notes: notes)

        if let action = zoomAction {
            switch action {
            case .in:  nsView.zoomIn(nil)
            case .out: nsView.zoomOut(nil)
            case .fit: nsView.autoScales = true; nsView.scaleFactor = nsView.scaleFactorForSizeToFit
            }
            DispatchQueue.main.async { context.coordinator.parent.zoomAction = nil }
        }

        let z = zoomFactor
        if z > 0, abs(nsView.scaleFactor - z) > 0.001 {
            nsView.scaleFactor = z
        }

        let page = navigateToPage
        if page != context.coordinator.lastNavigatedPage, let page {
            context.coordinator.lastNavigatedPage = page
            if let document = nsView.document, page > 0, page <= document.pageCount {
                let pdfPage = document.page(at: page - 1)
                if let pdfPage {
                    nsView.go(to: pdfPage)
                }
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFReaderView
        private var lastNotesHash: Int = 0
        var lastNavigatedPage: Int?
        private var lastPage: Int = 0
        private var lastZoom: CGFloat = 0
        weak var pdfView: PDFView?

        init(_ parent: PDFReaderView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        func cleanupAnnotations(in pdfView: PDFView) {
            guard let document = pdfView.document else { return }
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let toRemove = page.annotations.filter { annotation in
                    annotation.value(forAnnotationKey: .name) as? String == "ResearchPaperReader"
                }
                for annotation in toRemove {
                    page.removeAnnotation(annotation)
                }
            }
        }

        @MainActor
        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            let z = pdfView.scaleFactor
            guard abs(z - lastZoom) > 0.001 else { return }
            lastZoom = z
            parent.zoomFactor = z
        }

        @MainActor
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let document = pdfView.document,
                  let current = pdfView.currentPage else { return }
            let idx = document.index(for: current) + 1
            guard idx != lastPage else { return }
            lastPage = idx
            parent.selectedPage = idx
        }

        @MainActor
        @objc func selectionChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            let selection = pdfView.currentSelection
            parent.selectedText = selection?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if let page = selection?.pages.first,
               let document = pdfView.document {
                parent.selectedPage = document.index(for: page) + 1
            } else {
                parent.selectedPage = nil
            }
        }

        @MainActor
        func syncAnnotations(pdfView: PDFView, notes: [PaperNote]) {
            let hash = notes.reduce(0) { $0 &+ $1.id.hashValue }
            guard hash != lastNotesHash else { return }
            lastNotesHash = hash

            guard let document = pdfView.document else { return }

            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let toRemove = page.annotations.filter { annotation in
                    annotation.value(forAnnotationKey: .name) as? String == "ResearchPaperReader"
                }
                for annotation in toRemove {
                    page.removeAnnotation(annotation)
                }
            }

            for note in notes where !note.quote.isEmpty {
                let selections = document.findString(note.quote, withOptions: .caseInsensitive)
                guard !selections.isEmpty else { continue }

                for selection in selections {
                    for page in selection.pages {
                        let bounds = selection.bounds(for: page)
                        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                        annotation.color = note.kind.color
                        annotation.setValue("ResearchPaperReader", forAnnotationKey: .name)
                        page.addAnnotation(annotation)
                    }
                }
            }
        }
    }
}
