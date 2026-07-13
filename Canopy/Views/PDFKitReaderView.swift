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
    let annotations: [Annotation]
    let annotationNavigation: AnnotationNavigation?
    let onCreateAnnotations: ([AnnotationAnchor], HighlightColor, Bool) -> Void
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
        context.coordinator.showAnnotations(annotations, in: pdfView)
        context.coordinator.navigate(to: annotationNavigation, annotations: annotations, in: pdfView)
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
        private var lastAnnotationSignature: [AnnotationSignature] = []
        private var lastAnnotationNavigationID: UUID?
        private var overlayAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
        private var highlightPopover: NSPopover?
        private var isUpdatingSearchSelection = false
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
            observers.append(center.addObserver(
                forName: .PDFViewSelectionChanged,
                object: pdfView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.selectionChanged()
                }
            })
            for scrollView in scrollViews(in: pdfView) {
                scrollView.contentView.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.publishSnapshot()
                    }
                })
            }
        }

        func detach() {
            closeHighlightPopover()
            removeAnnotationOverlays()
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
                isUpdatingSearchSelection = true
                pdfView.setCurrentSelection(nil, animate: false)
                isUpdatingSearchSelection = false
                return
            }
            let selection = matches[selectedIndex]
            isUpdatingSearchSelection = true
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.go(to: selection)
            isUpdatingSearchSelection = false
        }

        func showAnnotations(_ annotations: [Annotation], in pdfView: PDFView) {
            let signature = annotations.map(AnnotationSignature.init)
            guard signature != lastAnnotationSignature else { return }
            lastAnnotationSignature = signature
            removeAnnotationOverlays()

            guard let document = pdfView.document else { return }
            for annotationModel in annotations {
                guard let anchor = annotationModel.anchor,
                      let page = document.page(at: anchor.pageIndex),
                      let overlay = makeOverlay(for: anchor, color: annotationModel.color) else { continue }
                page.addAnnotation(overlay)
                overlayAnnotations.append((page, overlay))
            }
        }

        func navigate(
            to navigation: AnnotationNavigation?,
            annotations: [Annotation],
            in pdfView: PDFView
        ) {
            guard let navigation,
                  navigation.id != lastAnnotationNavigationID,
                  let annotation = annotations.first(where: { $0.id == navigation.annotationID }),
                  let anchor = annotation.anchor,
                  let page = pdfView.document?.page(at: anchor.pageIndex),
                  let bounds = bounds(of: anchor.quadrilaterals) else { return }
            lastAnnotationNavigationID = navigation.id
            pdfView.go(to: bounds.insetBy(dx: -12, dy: -24), on: page)
        }

        private func selectionChanged() {
            guard !isUpdatingSearchSelection,
                  parent.matches.isEmpty,
                  let pdfView,
                  let selection = pdfView.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                closeHighlightPopover()
                return
            }

            let anchors = captureAnchors(from: selection, in: pdfView)
            guard !anchors.isEmpty,
                  let firstPage = selection.pages.first,
                  !selection.bounds(for: firstPage).isEmpty else {
                closeHighlightPopover()
                return
            }

            closeHighlightPopover()
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.contentSize = NSSize(width: 520, height: 126)
            popover.contentViewController = NSHostingController(rootView: HighlightPaletteView { [weak self] color, addNote in
                guard let self else { return }
                self.parent.onCreateAnnotations(anchors, color, addNote)
                self.closeHighlightPopover()
                self.isUpdatingSearchSelection = true
                pdfView.setCurrentSelection(nil, animate: false)
                self.isUpdatingSearchSelection = false
            })
            let selectionRect = pdfView.convert(selection.bounds(for: firstPage), from: firstPage)
            popover.show(relativeTo: selectionRect, of: pdfView, preferredEdge: .maxY)
            highlightPopover = popover
        }

        private func captureAnchors(from selection: PDFSelection, in pdfView: PDFView) -> [AnnotationAnchor] {
            guard let document = pdfView.document else { return [] }
            let lineSelections = selection.selectionsByLine()

            return selection.pages.compactMap { page in
                let pageIndex = document.index(for: page)
                guard pageIndex != NSNotFound,
                      let pageText = page.string else { return nil }
                let string = pageText as NSString
                let ranges = (0..<selection.numberOfTextRanges(on: page))
                    .map { selection.range(at: $0, on: page) }
                    .filter { $0.location != NSNotFound && NSMaxRange($0) <= string.length }
                guard let firstRange = ranges.first, let lastRange = ranges.last else { return nil }

                let pageSelection = PDFSelection(document: document)
                pageSelection.add(ranges.compactMap { page.selection(for: $0) })
                let selectedText = pageSelection.string ?? ""
                guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

                let quadrilaterals = lineSelections.compactMap { line -> AnnotationQuadrilateral? in
                    guard line.pages.contains(where: { $0 === page }) else { return nil }
                    let rect = line.bounds(for: page)
                    guard !rect.isNull, !rect.isEmpty else { return nil }
                    return AnnotationQuadrilateral(
                        upperLeft: AnnotationPoint(x: rect.minX, y: rect.maxY),
                        upperRight: AnnotationPoint(x: rect.maxX, y: rect.maxY),
                        lowerLeft: AnnotationPoint(x: rect.minX, y: rect.minY),
                        lowerRight: AnnotationPoint(x: rect.maxX, y: rect.minY)
                    )
                }
                guard !quadrilaterals.isEmpty else { return nil }

                let contextStart = max(firstRange.location - 48, 0)
                let contextEnd = min(NSMaxRange(lastRange) + 48, string.length)
                return AnnotationAnchor(
                    pageIndex: pageIndex,
                    quadrilaterals: quadrilaterals,
                    selectedText: selectedText,
                    contextBefore: string.substring(with: NSRange(
                        location: contextStart,
                        length: firstRange.location - contextStart
                    )),
                    contextAfter: string.substring(with: NSRange(
                        location: NSMaxRange(lastRange),
                        length: contextEnd - NSMaxRange(lastRange)
                    ))
                )
            }
        }

        private func makeOverlay(
            for anchor: AnnotationAnchor,
            color: HighlightColor
        ) -> PDFAnnotation? {
            guard let bounds = bounds(of: anchor.quadrilaterals) else { return nil }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color.nsColor.withAlphaComponent(0.42)
            annotation.markupType = .highlight
            annotation.quadrilateralPoints = anchor.quadrilaterals.flatMap { quadrilateral in
                [
                    quadrilateral.upperLeft,
                    quadrilateral.upperRight,
                    quadrilateral.lowerLeft,
                    quadrilateral.lowerRight
                ].map { point in
                    NSValue(point: NSPoint(x: point.x - bounds.minX, y: point.y - bounds.minY))
                }
            }
            return annotation
        }

        private func bounds(of quadrilaterals: [AnnotationQuadrilateral]) -> CGRect? {
            let points = quadrilaterals.flatMap {
                [$0.upperLeft, $0.upperRight, $0.lowerLeft, $0.lowerRight]
            }
            guard let first = points.first else { return nil }
            let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
            let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
            let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
            let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }

        private func removeAnnotationOverlays() {
            for overlay in overlayAnnotations {
                overlay.page.removeAnnotation(overlay.annotation)
            }
            overlayAnnotations.removeAll()
        }

        private func closeHighlightPopover() {
            highlightPopover?.close()
            highlightPopover = nil
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

        private func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { subview in
                if let scrollView = subview as? NSScrollView {
                    [scrollView] + scrollViews(in: scrollView)
                } else {
                    scrollViews(in: subview)
                }
            }
        }
    }
}

private struct AnnotationSignature: Equatable {
    let id: UUID
    let pageIndex: Int
    let quadrilaterals: Data
    let color: HighlightColor

    init(_ annotation: Annotation) {
        id = annotation.id
        pageIndex = annotation.pageIndex
        quadrilaterals = annotation.quadrilaterals
        color = annotation.color
    }
}

private struct HighlightPaletteView: View {
    let onCreate: (HighlightColor, Bool) -> Void

    @State private var selectedColor = HighlightColor.yellow
    @State private var addNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Highlight Selection")
                .font(.headline)

            HStack(spacing: 6) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        HighlightColorLabel(color: color, selected: selectedColor == color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(color.swiftUIColor.opacity(selectedColor == color ? 0.2 : 0.08))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(selectedColor == color ? Color.accentColor : .clear, lineWidth: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color.displayName) highlight")
                    .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                }
            }

            HStack {
                Toggle("Add Note", isOn: $addNote)
                    .toggleStyle(.checkbox)
                Spacer()
                Button(addNote ? "Highlight and Add Note" : "Add Highlight") {
                    onCreate(selectedColor, addNote)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 520)
    }
}

private extension HighlightColor {
    var nsColor: NSColor {
        switch self {
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .pink: .systemPink
        case .purple: .systemPurple
        }
    }
}
