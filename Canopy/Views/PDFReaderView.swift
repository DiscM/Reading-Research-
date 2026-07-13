import CanopyCore
import PDFKit
import SwiftUI

struct PDFReaderView: View {
    let paper: Paper?
    @State private var documentSession: PDFDocumentSession?
    @State private var loadError: PDFReaderLoadError?

    var body: some View {
        Group {
            if paper == nil {
                ContentUnavailableView(
                    "Choose a Paper",
                    systemImage: "book.pages",
                    description: Text("Select a recent or library paper to begin reading.")
                )
            } else if let documentSession {
                PDFKitView(document: documentSession.document)
                    .id(documentSession.paperID)
            } else if let loadError {
                ContentUnavailableView(
                    loadError.title,
                    systemImage: loadError.systemImage,
                    description: Text(loadError.message)
                )
            } else {
                ProgressView("Opening Paper…")
            }
        }
        .task(id: paper?.id) {
            documentSession = nil
            loadError = nil
            guard let paper else { return }

            do {
                documentSession = try PDFDocumentSession(paper: paper)
            } catch let error as PDFReaderLoadError {
                loadError = error
            } catch {
                loadError = .cannotOpen
            }
        }
    }
}

private struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        guard pdfView.document !== document else { return }
        pdfView.document = document
        pdfView.autoScales = true
    }
}

@MainActor
private final class PDFDocumentSession {
    let paperID: UUID
    let document: PDFDocument
    private let sourceAccess: PaperSourceAccess

    init(paper: Paper) throws {
        paperID = paper.id
        do {
            sourceAccess = try PaperSourceAccess(paper: paper)
        } catch let error as PaperSourceAccessError {
            throw PDFReaderLoadError(error)
        }
        guard let document = PDFDocument(url: sourceAccess.url) else {
            throw PDFReaderLoadError.cannotOpen
        }
        self.document = document
    }
}

private enum PDFReaderLoadError: Error {
    case sourceUnavailable
    case sourceMissing
    case sourceChanged
    case libraryCopyMissing
    case cannotOpen

    init(_ sourceError: PaperSourceAccessError) {
        switch sourceError {
        case .sourceUnavailable: self = .sourceUnavailable
        case .sourceMissing: self = .sourceMissing
        case .sourceChanged: self = .sourceChanged
        case .libraryCopyMissing: self = .libraryCopyMissing
        }
    }

    var title: String {
        switch self {
        case .sourceUnavailable: "Source Unavailable"
        case .sourceMissing: "Source Missing"
        case .sourceChanged: "Source Changed"
        case .libraryCopyMissing: "Library Copy Missing"
        case .cannotOpen: "Couldn’t Open PDF"
        }
    }

    var systemImage: String {
        switch self {
        case .sourceUnavailable: "externaldrive.badge.exclamationmark"
        case .sourceMissing: "link.badge.plus"
        case .sourceChanged: "exclamationmark.triangle"
        case .libraryCopyMissing: "doc.badge.ellipsis"
        case .cannotOpen: "doc.badge.exclamationmark"
        }
    }

    var message: String {
        switch self {
        case .sourceUnavailable:
            "Canopy can’t currently access this Paper’s Source PDF."
        case .sourceMissing:
            "Canopy can’t find this Paper’s Source PDF."
        case .sourceChanged:
            "The Source PDF has changed since this Paper was added."
        case .libraryCopyMissing:
            "Canopy’s managed copy of this Paper is missing."
        case .cannotOpen:
            "The Source PDF could not be read."
        }
    }
}
