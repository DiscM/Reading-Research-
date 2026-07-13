import CanopyCore
import PDFKit
import SwiftUI

struct PDFReaderSnapshot: Equatable {
    var pageIndex: Int
    var viewport: PaperViewport?
    var zoomScale: Double
}

struct PDFReaderCommand: Equatable {
    enum Action: Equatable {
        case goToPage(Int)
        case zoomIn
        case zoomOut
        case fitWidth
        case actualSize
    }

    let id = UUID()
    let action: Action
}

struct PDFKitReaderView: NSViewRepresentable {
    let document: PDFDocument
    let restoredState: PaperReaderState?
    let command: PDFReaderCommand?
    let matches: [PDFSelection]
    let matchesVersion: UUID
    let selectedMatchIndex: Int?
    let onSnapshotChange: (PDFReaderSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = restoredState == nil
        pdfView.document = document
        context.coordinator.attach(to: pdfView)
        context.coordinator.restore(restoredState, in: pdfView)
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        if pdfView.document !== document {
            pdfView.document = document
            context.coordinator.attach(to: pdfView)
            context.coordinator.restore(restoredState, in: pdfView)
        }
        context.coordinator.perform(command, in: pdfView)
        context.coordinator.showMatches(matches, selectedIndex: selectedMatchIndex, in: pdfView)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.document?.cancelFindString()
        nsView.document = nil
    }

    @MainActor
    final class Coordinator {
        var parent: PDFKitReaderView
        private weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []
        private var lastCommandID: UUID?
        private var lastSelectedMatchIndex: Int?
        private var lastMatchesVersion: UUID?
        private var isRestoring = false

        init(parent: PDFKitReaderView) {
            self.parent = parent
        }

        func attach(to pdfView: PDFView) {
            detach()
            self.pdfView = pdfView
            let center = NotificationCenter.default
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged, .PDFViewVisiblePagesChanged] {
                observers.append(center.addObserver(forName: name, object: pdfView, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publishSnapshot()
                    }
                })
            }
        }

        func detach() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            pdfView = nil
        }

        func restore(_ state: PaperReaderState?, in pdfView: PDFView) {
            isRestoring = true
            defer {
                isRestoring = false
                publishSnapshot()
            }

            guard let state,
                  let document = pdfView.document,
                  let page = document.page(at: min(max(state.pageIndex, 0), max(document.pageCount - 1, 0))) else {
                return
            }
            pdfView.autoScales = false
            pdfView.scaleFactor = CGFloat(state.zoomScale)
            if let viewport = state.viewport {
                pdfView.go(
                    to: CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height),
                    on: page
                )
            } else {
                pdfView.go(to: page)
            }
        }

        func perform(_ command: PDFReaderCommand?, in pdfView: PDFView) {
            guard let command, command.id != lastCommandID else { return }
            lastCommandID = command.id
            switch command.action {
            case let .goToPage(index):
                guard let document = pdfView.document,
                      let page = document.page(at: min(max(index, 0), max(document.pageCount - 1, 0))) else { return }
                pdfView.go(to: page)
            case .zoomIn:
                pdfView.autoScales = false
                pdfView.zoomIn(nil)
            case .zoomOut:
                pdfView.autoScales = false
                pdfView.zoomOut(nil)
            case .fitWidth:
                guard let page = pdfView.currentPage else { return }
                let pageWidth = page.bounds(for: .cropBox).width
                let availableWidth = pdfView.enclosingScrollView?.contentSize.width ?? pdfView.bounds.width
                guard pageWidth > 0, availableWidth > 0 else { return }
                pdfView.autoScales = false
                pdfView.scaleFactor = min(max((availableWidth - 24) / pageWidth, pdfView.minScaleFactor), pdfView.maxScaleFactor)
            case .actualSize:
                pdfView.autoScales = false
                pdfView.scaleFactor = min(max(1, pdfView.minScaleFactor), pdfView.maxScaleFactor)
            }
            publishSnapshot()
        }

        func showMatches(_ matches: [PDFSelection], selectedIndex: Int?, in pdfView: PDFView) {
            let selectionChanged = selectedIndex != lastSelectedMatchIndex
            guard parent.matchesVersion != lastMatchesVersion || selectionChanged else { return }
            lastMatchesVersion = parent.matchesVersion
            lastSelectedMatchIndex = selectedIndex
            pdfView.highlightedSelections = matches

            guard let selectedIndex, matches.indices.contains(selectedIndex) else {
                pdfView.setCurrentSelection(nil, animate: false)
                return
            }
            let selection = matches[selectedIndex]
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.go(to: selection)
        }

        private func publishSnapshot() {
            guard !isRestoring,
                  let pdfView,
                  let document = pdfView.document,
                  let page = pdfView.currentPage else { return }
            let pageIndex = document.index(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            let visibleRect = pdfView.convert(pdfView.bounds, to: page).intersection(pageBounds)
            let viewport: PaperViewport? = visibleRect.isNull || visibleRect.isEmpty
                ? nil
                : PaperViewport(
                    x: visibleRect.origin.x,
                    y: visibleRect.origin.y,
                    width: visibleRect.width,
                    height: visibleRect.height
                )
            parent.onSnapshotChange(PDFReaderSnapshot(
                pageIndex: pageIndex,
                viewport: viewport,
                zoomScale: pdfView.scaleFactor
            ))
        }
    }
}
