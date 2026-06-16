import PDFKit
import SwiftUI

struct PDFReaderView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    @Binding var selectedPage: Int?
    var notes: [PaperNote]

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

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        context.coordinator.parent = self

        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
            nsView.autoScales = true
        }

        context.coordinator.syncAnnotations(pdfView: nsView, notes: notes)
    }

    final class Coordinator: NSObject {
        var parent: PDFReaderView
        private var lastNotesHash: Int = 0

        init(_ parent: PDFReaderView) {
            self.parent = parent
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
