import CanopyCore
import PDFKit
import SwiftUI

struct PDFReaderSnapshot: Equatable {
    var pageIndex: Int
    var viewport: PaperViewport?
    var zoomScale: Double
}

struct PDFPageAreaSelection: Equatable {
    let pageIndex: Int
    let rectangle: CGRect
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides

    let document: PDFDocument
    let restoredState: PaperReaderState?
    let command: PDFReaderCommand?
    let matches: [PDFSelection]
    let matchesVersion: UUID
    let selectedMatchIndex: Int?
    let allowsTextAnnotations: Bool
    let isAreaAnnotationMode: Bool
    let pdfInteractionResetID: UUID
    let annotations: [Annotation]
    let annotationNavigation: AnnotationNavigation?
    let onCreateAnnotations: ([TextAnnotationAnchor], HighlightColor, Bool) -> Void
    let onCreateAreaAnnotation: (PDFPageAreaSelection, HighlightColor, Bool) -> Void
    let onAreaAnnotationModeEnded: () -> Void
    let onTextSelectionRejected: (String) -> Void
    let onSnapshotChange: (PDFReaderSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = AreaSelectionPDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.autoScales = restoredState == nil
        pdfView.setAccessibilityIdentifier("paper-pdf-view")
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
        context.coordinator.resetPDFInteraction(
            ifNeeded: pdfInteractionResetID,
            in: pdfView
        )
        context.coordinator.perform(command, in: pdfView)
        context.coordinator.updateAreaAnnotationMode(isAreaAnnotationMode, in: pdfView)
        context.coordinator.showMatches(matches, selectedIndex: selectedMatchIndex, in: pdfView)
        context.coordinator.showAnnotations(
            annotations,
            appearance: appearance,
            differentiatesWithoutColor: accessibilityOverrides.differentiatesWithoutColor(
                system: differentiateWithoutColor
            ),
            in: pdfView
        )
        context.coordinator.navigate(to: annotationNavigation, annotations: annotations, in: pdfView)
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.document?.cancelFindString()
        nsView.document = nil
    }

    private var appearance: HighlightAppearancePreferences {
        HighlightAppearancePreferences(
            increasedContrast: accessibilityOverrides.usesIncreasedContrast(
                system: colorSchemeContrast == .increased
            )
        )
    }

    @MainActor
    final class Coordinator {
        var parent: PDFKitReaderView
        private weak var pdfView: PDFView?
        private var observers: [NSObjectProtocol] = []
        private var lastPDFInteractionResetID: UUID?
        private var lastCommandID: UUID?
        private var lastSelectedMatchIndex: Int?
        private var lastMatchesVersion: UUID?
        private var lastAnnotationSignature: [AnnotationSignature] = []
        private var lastAnnotationAppearance: HighlightAppearancePreferences?
        private var lastDifferentiatesWithoutColor: Bool?
        private var lastAnnotationNavigationID: UUID?
        private var overlayAnnotations: [(page: PDFPage, annotation: PDFAnnotation)] = []
        private var highlightPopover: NSPopover?
        private var pendingHighlightPresentation: Task<Void, Never>?
        private var presentedSelectionSignature: PDFSelectionSignature?
        private var isUpdatingSearchSelection = false
        private var isRestoring = false

        init(parent: PDFKitReaderView) {
            self.parent = parent
        }

        func attach(to pdfView: PDFView) {
            detach()
            self.pdfView = pdfView
            if let areaSelectionView = pdfView as? AreaSelectionPDFView {
                areaSelectionView.onAreaSelectionCompleted = { [weak self, weak areaSelectionView] selection, viewRectangle in
                    guard let self, let areaSelectionView else { return }
                    self.areaSelectionCompleted(selection, viewRectangle: viewRectangle, in: areaSelectionView)
                }
                areaSelectionView.onAreaSelectionCancelled = { [weak self] in
                    self?.parent.onAreaAnnotationModeEnded()
                }
            }
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
            pdfView?.setCurrentSelection(nil, animate: false)
            lastAnnotationSignature = []
            lastAnnotationAppearance = nil
            lastDifferentiatesWithoutColor = nil
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            if let areaSelectionView = pdfView as? AreaSelectionPDFView {
                areaSelectionView.onAreaSelectionCompleted = nil
                areaSelectionView.onAreaSelectionCancelled = nil
                areaSelectionView.setAreaSelectionEnabled(false)
            }
            pdfView = nil
        }

        func updateAreaAnnotationMode(_ enabled: Bool, in pdfView: PDFView) {
            guard let areaSelectionView = pdfView as? AreaSelectionPDFView else { return }
            if enabled {
                closeHighlightPopover()
                isUpdatingSearchSelection = true
                pdfView.setCurrentSelection(nil, animate: false)
                isUpdatingSearchSelection = false
            }
            areaSelectionView.setAreaSelectionEnabled(enabled)
        }

        func resetPDFInteraction(ifNeeded resetID: UUID, in pdfView: PDFView) {
            guard resetID != lastPDFInteractionResetID else { return }
            lastPDFInteractionResetID = resetID
            closeHighlightPopover()
            lastSelectedMatchIndex = nil
            lastMatchesVersion = nil
            isUpdatingSearchSelection = true
            pdfView.highlightedSelections = []
            pdfView.setCurrentSelection(nil, animate: false)
            isUpdatingSearchSelection = false
            (pdfView as? AreaSelectionPDFView)?.setAreaSelectionEnabled(false)
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
            // Streaming Find updates the highlighted result set for every match.
            // Keep the reader stationary unless the selected result itself changed.
            guard selectionChanged else { return }
            let selection = matches[selectedIndex]
            isUpdatingSearchSelection = true
            pdfView.setCurrentSelection(selection, animate: true)
            pdfView.go(to: selection)
            isUpdatingSearchSelection = false
        }

        func showAnnotations(
            _ annotations: [Annotation],
            appearance: HighlightAppearancePreferences,
            differentiatesWithoutColor: Bool,
            in pdfView: PDFView
        ) {
            let signature = annotations.map(AnnotationSignature.init)
            guard signature != lastAnnotationSignature
                    || appearance != lastAnnotationAppearance
                    || differentiatesWithoutColor != lastDifferentiatesWithoutColor else { return }
            lastAnnotationSignature = signature
            lastAnnotationAppearance = appearance
            lastDifferentiatesWithoutColor = differentiatesWithoutColor
            removeAnnotationOverlays()

            guard let document = pdfView.document else { return }
            for annotationModel in annotations {
                switch annotationModel.kind {
                case .textHighlight:
                    guard let anchor = annotationModel.textAnchor,
                          let page = document.page(at: anchor.pageIndex),
                          let overlay = makeTextOverlay(
                            for: anchor,
                            color: annotationModel.color,
                            opacity: appearance.overlayOpacity
                          ) else { continue }
                    page.addAnnotation(overlay)
                    overlayAnnotations.append((page, overlay))
                case .area:
                    guard let anchor = annotationModel.areaAnchor,
                          let page = document.page(at: anchor.pageIndex) else { continue }
                    let overlays = makeAreaOverlays(
                        for: anchor,
                        color: annotationModel.color,
                        appearance: appearance,
                        differentiatesWithoutColor: differentiatesWithoutColor
                    )
                    for overlay in overlays {
                        page.addAnnotation(overlay)
                        overlayAnnotations.append((page, overlay))
                    }
                }
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
                  let page = pdfView.document?.page(at: annotation.pageIndex) else { return }
            lastAnnotationNavigationID = navigation.id
            switch annotation.kind {
            case .textHighlight:
                guard let anchor = annotation.textAnchor,
                      let bounds = bounds(of: anchor.quadrilaterals) else { return }
                pdfView.go(to: bounds.insetBy(dx: -12, dy: -24), on: page)
            case .area:
                guard let anchor = annotation.areaAnchor else { return }
                navigate(to: cgRect(anchor.rect), on: page, in: pdfView)
            }
        }

        private func selectionChanged() {
            pendingHighlightPresentation?.cancel()
            pendingHighlightPresentation = nil

            guard !isUpdatingSearchSelection,
                  parent.allowsTextAnnotations,
                  parent.matches.isEmpty,
                  let pdfView,
                  let document = pdfView.document,
                  let selection = pdfView.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                closeHighlightPopover()
                return
            }

            guard selection.pages.count == 1 else {
                closeHighlightPopover()
                parent.onTextSelectionRejected(
                    "A text highlight can belong to only one page. Select text on one page at a time."
                )
                isUpdatingSearchSelection = true
                pdfView.setCurrentSelection(nil, animate: false)
                isUpdatingSearchSelection = false
                return
            }

            guard let signature = selectionSignature(selection, in: document) else {
                closeHighlightPopover()
                return
            }
            if signature == presentedSelectionSignature, highlightPopover?.isShown == true {
                return
            }

            dismissHighlightPopover()
            pendingHighlightPresentation = Task { @MainActor [weak self, weak pdfView] in
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
                guard let self,
                      let pdfView,
                      self.pdfView === pdfView,
                      pdfView.document === document,
                      let currentSelection = pdfView.currentSelection,
                      self.selectionSignature(currentSelection, in: document) == signature else { return }
                self.pendingHighlightPresentation = nil
                self.presentHighlightPopover(
                    for: currentSelection,
                    signature: signature,
                    in: pdfView
                )
            }
        }

        private func presentHighlightPopover(
            for selection: PDFSelection,
            signature: PDFSelectionSignature,
            in pdfView: PDFView
        ) {
            let anchors = captureAnchors(from: selection, in: pdfView)
            guard !anchors.isEmpty,
                  let firstPage = selection.pages.first,
                  !selection.bounds(for: firstPage).isEmpty else {
                closeHighlightPopover()
                return
            }

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = NSSize(width: 520, height: 126)
            let palette = AnnotationPaletteView(kind: .textHighlight) { [weak self] color, addNote in
                guard let self else { return }
                self.parent.onCreateAnnotations(anchors, color, addNote)
                self.closeHighlightPopover()
                self.isUpdatingSearchSelection = true
                pdfView.setCurrentSelection(nil, animate: false)
                self.isUpdatingSearchSelection = false
            }
            .environment(\.canopyAccessibilityOverrides, parent.accessibilityOverrides)
            .environment(\.colorScheme, parent.colorScheme)
            popover.contentViewController = NSHostingController(rootView: palette)
            let selectionRect = pdfView.convert(selection.bounds(for: firstPage), from: firstPage)
            popover.show(relativeTo: selectionRect, of: pdfView, preferredEdge: .maxY)
            highlightPopover = popover
            presentedSelectionSignature = signature
        }

        private func areaSelectionCompleted(
            _ selection: PDFPageAreaSelection,
            viewRectangle: CGRect,
            in pdfView: AreaSelectionPDFView
        ) {
            parent.onAreaAnnotationModeEnded()
            closeHighlightPopover()

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = NSSize(width: 520, height: 126)
            let palette = AnnotationPaletteView(kind: .area) { [weak self] color, addNote in
                guard let self else { return }
                self.parent.onCreateAreaAnnotation(selection, color, addNote)
                self.closeHighlightPopover()
            }
            .environment(\.canopyAccessibilityOverrides, parent.accessibilityOverrides)
            .environment(\.colorScheme, parent.colorScheme)
            popover.contentViewController = NSHostingController(rootView: palette)
            popover.show(relativeTo: viewRectangle, of: pdfView, preferredEdge: .maxY)
            highlightPopover = popover
        }

        private func selectionSignature(
            _ selection: PDFSelection,
            in document: PDFDocument
        ) -> PDFSelectionSignature? {
            let ranges = selection.pages.flatMap { page -> [PDFSelectionRange] in
                let pageIndex = document.index(for: page)
                guard pageIndex != NSNotFound else { return [] }
                return (0..<selection.numberOfTextRanges(on: page)).compactMap { rangeIndex in
                    let range = selection.range(at: rangeIndex, on: page)
                    guard range.location != NSNotFound, range.length > 0 else { return nil }
                    return PDFSelectionRange(
                        pageIndex: pageIndex,
                        location: range.location,
                        length: range.length
                    )
                }
            }
            guard !ranges.isEmpty else { return nil }
            return PDFSelectionSignature(ranges: ranges)
        }

        private func captureAnchors(from selection: PDFSelection, in pdfView: PDFView) -> [TextAnnotationAnchor] {
            guard let document = pdfView.document,
                  selection.pages.count == 1,
                  let page = selection.pages.first else { return [] }
            let lineSelections = selection.selectionsByLine()
            let pageIndex = document.index(for: page)
            guard pageIndex != NSNotFound,
                  let selectedText = selection.string,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }

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
            guard !quadrilaterals.isEmpty else { return [] }

            return [TextAnnotationAnchor(
                pageIndex: pageIndex,
                quadrilaterals: quadrilaterals,
                selectedText: selectedText
            )]
        }

        private func makeTextOverlay(
            for anchor: TextAnnotationAnchor,
            color: HighlightColor,
            opacity: CGFloat
        ) -> PDFAnnotation? {
            guard let bounds = bounds(of: anchor.quadrilaterals) else { return nil }
            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color.nsColor.withAlphaComponent(opacity)
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

        private func makeAreaOverlays(
            for anchor: AreaAnnotationAnchor,
            color: HighlightColor,
            appearance: HighlightAppearancePreferences,
            differentiatesWithoutColor: Bool
        ) -> [PDFAnnotation] {
            let rectangle = cgRect(anchor.rect)
            guard !rectangle.isNull, !rectangle.isEmpty else { return [] }

            let outline = PDFAnnotation(bounds: rectangle, forType: .square, withProperties: nil)
            outline.color = color.nsColor.withAlphaComponent(appearance.areaBorderOpacity)
            outline.interiorColor = color.nsColor.withAlphaComponent(appearance.areaFillOpacity)
            let border = PDFBorder()
            border.lineWidth = appearance.areaBorderWidth
            outline.border = border

            guard differentiatesWithoutColor else { return [outline] }

            let symbolSize = min(max(min(rectangle.width, rectangle.height) * 0.22, 14), 32)
            let symbolBounds = CGRect(
                x: rectangle.midX - symbolSize / 2,
                y: rectangle.midY - symbolSize / 2,
                width: symbolSize,
                height: symbolSize
            )
            let symbol = PDFAnnotation(bounds: symbolBounds, forType: .freeText, withProperties: nil)
            symbol.contents = color.differentiateWithoutColorGlyph
            symbol.font = .boldSystemFont(ofSize: symbolSize * 0.72)
            symbol.fontColor = appearance.increasedContrast ? .labelColor : color.nsColor
            symbol.alignment = .center
            symbol.color = .clear
            return [outline, symbol]
        }

        private func navigate(to rectangle: CGRect, on page: PDFPage, in pdfView: PDFView) {
            let pageBounds = page.bounds(for: .cropBox)
            let horizontalContext = max(rectangle.width * 0.45, 36)
            let verticalContext = max(rectangle.height * 0.45, 48)
            let target = rectangle
                .insetBy(dx: -horizontalContext, dy: -verticalContext)
                .intersection(pageBounds)
            guard !target.isNull, !target.isEmpty else { return }

            let visibleSize = pdfView.enclosingScrollView?.contentSize ?? pdfView.bounds.size
            if visibleSize.width > 0, visibleSize.height > 0 {
                let targetScale = min(visibleSize.width / target.width, visibleSize.height / target.height) * 0.88
                pdfView.autoScales = false
                pdfView.scaleFactor = min(max(targetScale, pdfView.minScaleFactor), pdfView.maxScaleFactor)
            }
            pdfView.go(to: target, on: page)
        }

        private func cgRect(_ rectangle: AnnotationRect) -> CGRect {
            CGRect(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height)
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
            pendingHighlightPresentation?.cancel()
            pendingHighlightPresentation = nil
            dismissHighlightPopover()
        }

        private func dismissHighlightPopover() {
            highlightPopover?.close()
            highlightPopover = nil
            presentedSelectionSignature = nil
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

private final class AreaSelectionPDFView: PDFView {
    var onAreaSelectionCompleted: ((PDFPageAreaSelection, CGRect) -> Void)?
    var onAreaSelectionCancelled: (() -> Void)?

    private var areaSelectionEnabled = false
    private weak var dragPage: PDFPage?
    private var dragStart: CGPoint?
    private let selectionOverlay = AreaSelectionOverlayView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installSelectionOverlay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installSelectionOverlay()
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        selectionOverlay.frame = bounds
    }

    func setAreaSelectionEnabled(_ enabled: Bool) {
        guard enabled != areaSelectionEnabled else { return }
        areaSelectionEnabled = enabled
        cancelCurrentDrag()
        setAccessibilityHelp(enabled
            ? "Area Annotation mode. Drag a rectangle on one page. Press Escape to cancel."
            : nil)
        window?.invalidateCursorRects(for: self)
        if enabled {
            window?.makeFirstResponder(self)
            announce("Area Annotation mode. Drag one rectangle on a PDF page. Press Escape to cancel.")
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if areaSelectionEnabled {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard areaSelectionEnabled else {
            super.mouseDown(with: event)
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: false) else {
            NSSound.beep()
            return
        }
        let pagePoint = clipped(convert(viewPoint, to: page), to: page.bounds(for: .cropBox))
        dragPage = page
        dragStart = pagePoint
        selectionOverlay.selectionRectangle = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard areaSelectionEnabled,
              let page = dragPage,
              let dragStart else {
            super.mouseDragged(with: event)
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = clipped(convert(viewPoint, to: page), to: page.bounds(for: .cropBox))
        let pageRectangle = rectangle(from: dragStart, to: pagePoint)
        selectionOverlay.selectionRectangle = convert(pageRectangle, from: page)
    }

    override func mouseUp(with event: NSEvent) {
        guard areaSelectionEnabled,
              let document,
              let page = dragPage,
              let dragStart else {
            super.mouseUp(with: event)
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = clipped(convert(viewPoint, to: page), to: page.bounds(for: .cropBox))
        let pageRectangle = rectangle(from: dragStart, to: pagePoint)
        let pageIndex = document.index(for: page)
        cancelCurrentDrag()

        guard pageIndex != NSNotFound,
              pageRectangle.width >= 4,
              pageRectangle.height >= 4 else {
            NSSound.beep()
            return
        }

        areaSelectionEnabled = false
        window?.invalidateCursorRects(for: self)
        let viewRectangle = convert(pageRectangle, from: page)
        announce("Area selected. Choose an annotation color and whether to add a note.")
        onAreaSelectionCompleted?(
            PDFPageAreaSelection(pageIndex: pageIndex, rectangle: pageRectangle),
            viewRectangle
        )
    }

    override func keyDown(with event: NSEvent) {
        if areaSelectionEnabled,
           event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            areaSelectionEnabled = false
            cancelCurrentDrag()
            window?.invalidateCursorRects(for: self)
            announce("Area Annotation cancelled.")
            onAreaSelectionCancelled?()
            return
        }
        super.keyDown(with: event)
    }

    private func installSelectionOverlay() {
        selectionOverlay.autoresizingMask = [.width, .height]
        selectionOverlay.frame = bounds
        addSubview(selectionOverlay, positioned: .above, relativeTo: nil)
    }

    private func cancelCurrentDrag() {
        dragPage = nil
        dragStart = nil
        selectionOverlay.selectionRectangle = nil
    }

    private func clipped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func rectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSNumber(value: NSAccessibilityPriorityLevel.medium.rawValue)
            ]
        )
    }
}

private final class AreaSelectionOverlayView: NSView {
    var selectionRectangle: CGRect? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let selectionRectangle, !selectionRectangle.isEmpty else { return }
        let path = NSBezierPath(rect: selectionRectangle)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 3], count: 2, phase: 0)
        path.stroke()
    }
}

private struct PDFSelectionSignature: Equatable {
    let ranges: [PDFSelectionRange]
}

private struct PDFSelectionRange: Equatable {
    let pageIndex: Int
    let location: Int
    let length: Int
}

private struct AnnotationSignature: Equatable {
    let id: UUID
    let kind: AnnotationKind
    let pageIndex: Int
    let geometry: Data
    let color: HighlightColor

    init(_ annotation: Annotation) {
        id = annotation.id
        kind = annotation.kind
        pageIndex = annotation.pageIndex
        geometry = annotation.quadrilaterals ?? annotation.areaRect ?? Data()
        color = annotation.color
    }
}

private struct AnnotationPaletteView: View {
    enum Kind {
        case textHighlight
        case area

        var title: String {
            switch self {
            case .textHighlight: "Highlight Selection"
            case .area: "Area Annotation"
            }
        }

        var actionTitle: String {
            switch self {
            case .textHighlight: "Add Highlight"
            case .area: "Add Area Annotation"
            }
        }
    }

    let kind: Kind
    let onCreate: (HighlightColor, Bool) -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides
    @State private var selectedColor = HighlightColor.yellow
    @State private var addNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.title)
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
                                    .fill(color.swiftUIColor.opacity(
                                        selectedColor == color
                                            ? appearance.selectedPaletteFillOpacity
                                            : appearance.unselectedPaletteFillOpacity
                                    ))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        selectedColor == color ? Color.accentColor : .clear,
                                        lineWidth: appearance.selectedBorderWidth
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(color.displayName) annotation color")
                    .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                    .accessibilityValue(selectedColor == color ? "Selected" : "Not selected")
                }
            }

            HStack {
                Toggle("Add Note", isOn: $addNote)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("annotation-palette-add-note")
                Spacer()
                Button(addNote ? "\(kind.actionTitle) and Add Note" : kind.actionTitle) {
                    onCreate(selectedColor, addNote)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("annotation-palette-create")
            }
        }
        .padding(12)
        .frame(width: 520)
        .accessibilityIdentifier("annotation-palette")
    }

    private var appearance: HighlightAppearancePreferences {
        HighlightAppearancePreferences(
            increasedContrast: accessibilityOverrides.usesIncreasedContrast(
                system: colorSchemeContrast == .increased
            )
        )
    }
}
