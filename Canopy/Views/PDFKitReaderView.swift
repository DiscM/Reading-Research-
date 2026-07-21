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
    let adjustmentRequest: AnnotationAdjustmentRequest?
    let adjustmentCommand: AnnotationAdjustmentCommand?
    let onCreateAnnotations: ([TextAnnotationAnchor], HighlightColor, Bool) -> Void
    let onCreateAreaAnnotation: (PDFPageAreaSelection, HighlightColor, Bool) -> Void
    let onRequestAnnotationAdjustment: (UUID) -> Void
    let onDeleteAnnotation: (UUID) -> Void
    let onCommitAnnotationAdjustment: (UUID, AnnotationAnchorValue) -> Bool
    let onCancelAnnotationAdjustment: () -> Void
    let onAreaAnnotationModeEnded: () -> Void
    let onTextSelectionRejected: (String) -> Void
    let onSnapshotChange: (PDFReaderSnapshot) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = AreaSelectionPDFView()
        pdfView.backgroundColor = CanopySemanticColors.resolved(
            .underPageBackgroundColor,
            for: colorScheme
        )
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
        pdfView.backgroundColor = CanopySemanticColors.resolved(
            .underPageBackgroundColor,
            for: colorScheme
        )
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
        let displayedAnnotations = annotations.filter {
            $0.id != adjustmentRequest?.annotationID
        }
        context.coordinator.showAnnotations(
            displayedAnnotations,
            appearance: appearance,
            differentiatesWithoutColor: accessibilityOverrides.differentiatesWithoutColor(
                system: differentiateWithoutColor
            ),
            in: pdfView
        )
        context.coordinator.configureAnnotationContextMenu(annotations, in: pdfView)
        context.coordinator.navigate(to: annotationNavigation, annotations: annotations, in: pdfView)
        context.coordinator.updateAdjustment(
            request: adjustmentRequest,
            command: adjustmentCommand,
            annotations: annotations,
            in: pdfView
        )
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
        private var lastAdjustmentRequestID: UUID?
        private var lastAdjustmentCommandID: UUID?
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
                areaSelectionView.onAdjustmentCommitted = { [weak self] annotationID, anchor in
                    self?.parent.onCommitAnnotationAdjustment(annotationID, anchor) ?? false
                }
                areaSelectionView.onAdjustmentCancelled = { [weak self] in
                    self?.parent.onCancelAnnotationAdjustment()
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
                areaSelectionView.onAdjustmentCommitted = nil
                areaSelectionView.onAdjustmentCancelled = nil
                areaSelectionView.setAreaSelectionEnabled(false)
                areaSelectionView.endAdjustmentSilently()
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

        func configureAnnotationContextMenu(_ annotations: [Annotation], in pdfView: PDFView) {
            guard let areaSelectionView = pdfView as? AreaSelectionPDFView else { return }
            areaSelectionView.configureAnnotationContextMenu(
                annotations: annotations,
                onAdjust: parent.onRequestAnnotationAdjustment,
                onDelete: parent.onDeleteAnnotation
            )
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

        func updateAdjustment(
            request: AnnotationAdjustmentRequest?,
            command: AnnotationAdjustmentCommand?,
            annotations: [Annotation],
            in pdfView: PDFView
        ) {
            guard let adjustmentView = pdfView as? AreaSelectionPDFView else { return }

            if request?.requestID != lastAdjustmentRequestID {
                lastAdjustmentRequestID = request?.requestID
                lastAdjustmentCommandID = nil
                adjustmentView.endAdjustmentSilently()
                if let request,
                   let annotation = annotations.first(where: { $0.id == request.annotationID }),
                   let page = pdfView.document?.page(at: annotation.pageIndex),
                   let anchor = AnnotationAnchorValue(annotation: annotation) {
                    closeHighlightPopover()
                    isUpdatingSearchSelection = true
                    pdfView.setCurrentSelection(nil, animate: false)
                    isUpdatingSearchSelection = false
                    pdfView.go(to: page)
                    if !adjustmentView.beginAdjustment(
                        annotationID: annotation.id,
                        anchor: anchor,
                        page: page
                    ) {
                        parent.onCancelAnnotationAdjustment()
                    }
                }
            }

            guard let command, command.id != lastAdjustmentCommandID else { return }
            lastAdjustmentCommandID = command.id
            switch command.action {
            case .commit:
                adjustmentView.commitAdjustment()
            case .cancel:
                adjustmentView.cancelAdjustment()
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
            (pdfView as? AreaSelectionPDFView)?.refreshAdjustmentOverlay()
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
    var onAdjustmentCommitted: ((UUID, AnnotationAnchorValue) -> Bool)?
    var onAdjustmentCancelled: (() -> Void)?

    private var areaSelectionEnabled = false
    private weak var dragPage: PDFPage?
    private var dragStart: CGPoint?
    private let selectionOverlay = AreaSelectionOverlayView(frame: .zero)
    private var adjustmentSession: PDFAnnotationAdjustmentSession?
    private var annotationContextTargets: [PDFAnnotationContextTarget] = []
    private var onContextAdjust: ((UUID) -> Void)?
    private var onContextDelete: ((UUID) -> Void)?
    private var activeContextMenuActionTarget: AnnotationContextMenuActionTarget?

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
        refreshAdjustmentOverlay()
    }

    func configureAnnotationContextMenu(
        annotations: [Annotation],
        onAdjust: @escaping (UUID) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        annotationContextTargets = annotations.compactMap { annotation in
            switch annotation.kind {
            case .textHighlight:
                guard let anchor = annotation.textAnchor else { return nil }
                return PDFAnnotationContextTarget(
                    annotationID: annotation.id,
                    pageIndex: anchor.pageIndex,
                    regions: anchor.quadrilaterals.map(quadrilateralRect)
                )
            case .area:
                guard let anchor = annotation.areaAnchor else { return nil }
                return PDFAnnotationContextTarget(
                    annotationID: annotation.id,
                    pageIndex: anchor.pageIndex,
                    regions: [cgRect(anchor.rect)]
                )
            }
        }
        onContextAdjust = onAdjust
        onContextDelete = onDelete
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard adjustmentSession == nil,
              let document,
              let page = page(for: convert(event.locationInWindow, from: nil), nearest: false) else {
            return super.menu(for: event)
        }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return super.menu(for: event) }
        let pagePoint = convert(convert(event.locationInWindow, from: nil), to: page)
        guard let target = annotationContextTargets.last(where: { target in
            target.pageIndex == pageIndex && target.regions.contains { region in
                region.insetBy(dx: -3, dy: -3).contains(pagePoint)
            }
        }) else {
            return super.menu(for: event)
        }

        let actions = AnnotationContextMenuActionTarget(
            onAdjust: { [weak self] in self?.onContextAdjust?(target.annotationID) },
            onDelete: { [weak self] in self?.onContextDelete?(target.annotationID) }
        )
        activeContextMenuActionTarget = actions
        let menu = NSMenu()
        let adjustItem = NSMenuItem(
            title: "Adjust Annotation",
            action: #selector(AnnotationContextMenuActionTarget.adjustAnnotation(_:)),
            keyEquivalent: ""
        )
        adjustItem.target = actions
        menu.addItem(adjustItem)
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(
            title: "Delete Annotation",
            action: #selector(AnnotationContextMenuActionTarget.deleteAnnotation(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = actions
        menu.addItem(deleteItem)
        return menu
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

    @discardableResult
    func beginAdjustment(
        annotationID: UUID,
        anchor: AnnotationAnchorValue,
        page: PDFPage
    ) -> Bool {
        guard let document else { return false }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound else { return false }

        let textRange: NSRange?
        switch anchor {
        case let .text(textAnchor):
            guard textAnchor.pageIndex == pageIndex,
                  let range = locateTextRange(for: textAnchor, on: page) else { return false }
            textRange = range
        case let .area(areaAnchor):
            guard areaAnchor.pageIndex == pageIndex else { return false }
            textRange = nil
        }

        areaSelectionEnabled = false
        cancelCurrentDrag()
        adjustmentSession = PDFAnnotationAdjustmentSession(
            annotationID: annotationID,
            pageIndex: pageIndex,
            page: page,
            anchor: anchor,
            textRange: textRange
        )
        refreshAdjustmentOverlay()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        setAccessibilityHelp("Adjust Annotation mode. Drag a handle or use the arrow keys. Press Return to save or Escape to cancel.")
        announce("Adjust Annotation mode. Press Return to save or Escape to cancel.")
        return true
    }

    func commitAdjustment() {
        guard let adjustmentSession else { return }
        let annotationID = adjustmentSession.annotationID
        let anchor = adjustmentSession.anchor
        guard onAdjustmentCommitted?(annotationID, anchor) == true else {
            announce("The annotation could not be saved. Adjustment mode remains open.")
            return
        }
        endAdjustmentSilently()
        announce("Annotation adjusted.")
    }

    func cancelAdjustment() {
        guard adjustmentSession != nil else { return }
        endAdjustmentSilently()
        announce("Annotation adjustment cancelled.")
        onAdjustmentCancelled?()
    }

    func endAdjustmentSilently() {
        adjustmentSession = nil
        selectionOverlay.adjustmentRegions = []
        selectionOverlay.adjustmentHandles = []
        selectionOverlay.selectedAdjustmentHandleIndex = nil
        setAccessibilityHelp(areaSelectionEnabled
            ? "Area Annotation mode. Drag a rectangle on one page. Press Escape to cancel."
            : nil)
        window?.invalidateCursorRects(for: self)
    }

    func refreshAdjustmentOverlay() {
        guard let session = adjustmentSession, let page = session.page else {
            selectionOverlay.adjustmentRegions = []
            selectionOverlay.adjustmentHandles = []
            return
        }
        switch session.anchor {
        case let .text(anchor):
            selectionOverlay.adjustmentRegions = anchor.quadrilaterals.map { quadrilateral in
                convert(quadrilateralRect(quadrilateral), from: page).standardized
            }
            selectionOverlay.adjustmentHandles = textHandleRects(anchor: anchor, page: page).map(\.rect)
        case let .area(anchor):
            let viewRect = convert(cgRect(anchor.rect), from: page).standardized
            selectionOverlay.adjustmentRegions = [viewRect]
            selectionOverlay.adjustmentHandles = areaHandleRects(viewRect: viewRect).map(\.rect)
        }
        selectionOverlay.selectedAdjustmentHandleIndex = selectedHandleIndex()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if areaSelectionEnabled {
            addCursorRect(bounds, cursor: .crosshair)
        } else if adjustmentSession != nil {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if adjustmentSession != nil {
            beginAdjustmentDrag(with: event)
            return
        }
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
        if adjustmentSession != nil {
            continueAdjustmentDrag(with: event)
            return
        }
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
        if let session = adjustmentSession {
            session.dragStartPagePoint = nil
            session.dragStartAreaRect = nil
            refreshAdjustmentOverlay()
            return
        }
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
        if adjustmentSession != nil {
            if handleAdjustmentKey(event) { return }
        }
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

    private func beginAdjustmentDrag(with event: NSEvent) {
        guard let session = adjustmentSession, let page = session.page else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = clipped(convert(viewPoint, to: page), to: page.bounds(for: .cropBox))

        switch session.anchor {
        case let .area(anchor):
            let viewRect = convert(cgRect(anchor.rect), from: page).standardized
            if let hit = areaHandleRects(viewRect: viewRect).first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(viewPoint) }) {
                session.selectedHandle = .area(hit.handle)
            } else if viewRect.contains(viewPoint) {
                session.selectedHandle = .area(.move)
            } else {
                NSSound.beep()
                return
            }
            session.dragStartPagePoint = pagePoint
            session.dragStartAreaRect = cgRect(anchor.rect)
        case let .text(anchor):
            guard let hit = textHandleRects(anchor: anchor, page: page)
                .first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(viewPoint) }) else {
                NSSound.beep()
                return
            }
            session.selectedHandle = hit.handle
            session.dragStartPagePoint = pagePoint
        }
        window?.makeFirstResponder(self)
        refreshAdjustmentOverlay()
    }

    private func continueAdjustmentDrag(with event: NSEvent) {
        guard let session = adjustmentSession,
              let page = session.page,
              let selectedHandle = session.selectedHandle else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let pagePoint = clipped(convert(viewPoint, to: page), to: page.bounds(for: .cropBox))
        switch selectedHandle {
        case let .area(handle):
            guard let startPoint = session.dragStartPagePoint,
                  let startRect = session.dragStartAreaRect else { return }
            let delta = CGPoint(x: pagePoint.x - startPoint.x, y: pagePoint.y - startPoint.y)
            let rect = adjustedAreaRect(
                startRect,
                handle: handle,
                pagePoint: pagePoint,
                delta: delta,
                pageBounds: page.bounds(for: .cropBox)
            )
            session.anchor = .area(AreaAnnotationAnchor(
                pageIndex: session.pageIndex,
                rect: AnnotationRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            ))
        case .textStart, .textEnd:
            updateTextRange(at: pagePoint, boundary: selectedHandle, session: session, page: page)
        }
        refreshAdjustmentOverlay()
    }

    private func handleAdjustmentKey(_ event: NSEvent) -> Bool {
        guard let session = adjustmentSession else { return false }
        if event.keyCode == 53 || event.charactersIgnoringModifiers == "\u{1b}" {
            cancelAdjustment()
            return true
        }
        if event.keyCode == 36 || event.charactersIgnoringModifiers == "\r" {
            commitAdjustment()
            return true
        }
        if event.keyCode == 48 {
            selectNextAdjustmentHandle(
                reverse: event.modifierFlags.contains(.shift),
                session: session
            )
            refreshAdjustmentOverlay()
            return true
        }
        guard [123, 124, 125, 126].contains(event.keyCode) else { return false }

        switch session.anchor {
        case .area:
            nudgeAreaAdjustment(event: event, session: session)
        case .text:
            nudgeTextAdjustment(event: event, session: session)
        }
        refreshAdjustmentOverlay()
        return true
    }

    private func selectNextAdjustmentHandle(
        reverse: Bool,
        session: PDFAnnotationAdjustmentSession
    ) {
        let handles: [AnnotationAdjustmentHandle]
        switch session.anchor {
        case .text:
            handles = [.textStart, .textEnd]
        case .area:
            handles = AreaAdjustmentHandle.allCases.map(AnnotationAdjustmentHandle.area)
        }
        let currentIndex = session.selectedHandle.flatMap { handles.firstIndex(of: $0) }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = (currentIndex + (reverse ? handles.count - 1 : 1)) % handles.count
        } else {
            nextIndex = reverse ? handles.count - 1 : 0
        }
        session.selectedHandle = handles[nextIndex]
        announce("\(handles[nextIndex].accessibilityName) selected. Use the arrow keys to adjust.")
    }

    private func nudgeAreaAdjustment(event: NSEvent, session: PDFAnnotationAdjustmentSession) {
        guard case let .area(anchor) = session.anchor, let page = session.page else { return }
        let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        let delta = switch event.keyCode {
        case 123: CGPoint(x: -amount, y: 0)
        case 124: CGPoint(x: amount, y: 0)
        case 125: CGPoint(x: 0, y: -amount)
        default: CGPoint(x: 0, y: amount)
        }
        let handle: AreaAdjustmentHandle
        if case let .area(selected)? = session.selectedHandle {
            handle = selected
        } else {
            handle = .move
            session.selectedHandle = .area(.move)
        }
        let startRect = cgRect(anchor.rect)
        let referencePoint = CGPoint(
            x: handle.affectsMaximumX ? startRect.maxX + delta.x : startRect.minX + delta.x,
            y: handle.affectsMaximumY ? startRect.maxY + delta.y : startRect.minY + delta.y
        )
        let rect = adjustedAreaRect(
            startRect,
            handle: handle,
            pagePoint: referencePoint,
            delta: delta,
            pageBounds: page.bounds(for: .cropBox)
        )
        session.anchor = .area(AreaAnnotationAnchor(
            pageIndex: session.pageIndex,
            rect: AnnotationRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        ))
    }

    private func nudgeTextAdjustment(event: NSEvent, session: PDFAnnotationAdjustmentSession) {
        guard let page = session.page, let range = session.textRange else { return }
        guard event.keyCode == 123 || event.keyCode == 124 else {
            NSSound.beep()
            return
        }
        let direction = event.keyCode == 123 ? -1 : 1
        let boundary = session.selectedHandle ?? .textEnd
        session.selectedHandle = boundary
        let currentIndex = boundary == .textStart ? range.location : NSMaxRange(range) - 1
        let proposed: Int
        if event.modifierFlags.contains(.option) {
            proposed = wordBoundary(from: currentIndex, direction: direction, on: page)
        } else {
            proposed = currentIndex + direction
        }
        updateTextIndex(proposed, boundary: boundary, session: session, page: page)
    }

    private func updateTextRange(
        at pagePoint: CGPoint,
        boundary: AnnotationAdjustmentHandle,
        session: PDFAnnotationAdjustmentSession,
        page: PDFPage
    ) {
        let index = page.characterIndex(at: pagePoint)
        guard index != NSNotFound else { return }
        updateTextIndex(index, boundary: boundary, session: session, page: page)
    }

    private func updateTextIndex(
        _ proposedIndex: Int,
        boundary: AnnotationAdjustmentHandle,
        session: PDFAnnotationAdjustmentSession,
        page: PDFPage
    ) {
        guard let range = session.textRange else { return }
        let lastCharacter = max(Int(page.numberOfCharacters) - 1, 0)
        let index = min(max(proposedIndex, 0), lastCharacter)
        let newRange: NSRange
        switch boundary {
        case .textStart:
            let end = NSMaxRange(range)
            newRange = NSRange(location: min(index, end - 1), length: end - min(index, end - 1))
        case .textEnd:
            let end = max(index + 1, range.location + 1)
            newRange = NSRange(location: range.location, length: end - range.location)
        case .area:
            return
        }
        guard let selection = page.selection(for: newRange),
              let anchor = textAnchor(from: selection, page: page, pageIndex: session.pageIndex) else { return }
        session.textRange = newRange
        session.anchor = .text(anchor)
    }

    private func adjustedAreaRect(
        _ startRect: CGRect,
        handle: AreaAdjustmentHandle,
        pagePoint: CGPoint,
        delta: CGPoint,
        pageBounds: CGRect
    ) -> CGRect {
        let adjusted = AreaAnnotationGeometry.adjustedRect(
            AnnotationRect(
                x: startRect.minX,
                y: startRect.minY,
                width: startRect.width,
                height: startRect.height
            ),
            handle: handle,
            pagePoint: AnnotationPoint(x: pagePoint.x, y: pagePoint.y),
            delta: AnnotationPoint(x: delta.x, y: delta.y),
            pageBounds: AnnotationRect(
                x: pageBounds.minX,
                y: pageBounds.minY,
                width: pageBounds.width,
                height: pageBounds.height
            )
        )
        return cgRect(adjusted)
    }

    private func locateTextRange(for anchor: TextAnnotationAnchor, on page: PDFPage) -> NSRange? {
        guard let pageText = page.string, !anchor.selectedText.isEmpty else { return nil }
        let haystack = pageText as NSString
        let needle = anchor.selectedText as NSString
        var searchRange = NSRange(location: 0, length: haystack.length)
        var best: (range: NSRange, distance: CGFloat)?
        let target = quadrilateralBounds(anchor.quadrilaterals)

        while searchRange.length > 0 {
            let found = haystack.range(of: needle as String, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            if let selection = page.selection(for: found) {
                let bounds = selection.bounds(for: page)
                let distance = abs(bounds.midX - target.midX) + abs(bounds.midY - target.midY)
                if best == nil || distance < best!.distance {
                    best = (found, distance)
                }
            }
            let next = NSMaxRange(found)
            guard next < haystack.length else { break }
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return best?.range
    }

    private func textAnchor(
        from selection: PDFSelection,
        page: PDFPage,
        pageIndex: Int
    ) -> TextAnnotationAnchor? {
        guard let selectedText = selection.string,
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let quadrilaterals = selection.selectionsByLine().compactMap { line -> AnnotationQuadrilateral? in
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
        return TextAnnotationAnchor(
            pageIndex: pageIndex,
            quadrilaterals: quadrilaterals,
            selectedText: selectedText
        )
    }

    private func wordBoundary(from index: Int, direction: Int, on page: PDFPage) -> Int {
        guard let string = page.string else { return index }
        let text = string as NSString
        guard text.length > 0 else { return index }
        var cursor = min(max(index + direction, 0), text.length - 1)
        let whitespace = CharacterSet.whitespacesAndNewlines
        func isWhitespace(_ offset: Int) -> Bool {
            guard let scalar = UnicodeScalar(text.character(at: offset)) else { return false }
            return whitespace.contains(scalar)
        }
        while cursor > 0, cursor < text.length - 1, isWhitespace(cursor) {
            cursor += direction
        }
        while cursor > 0, cursor < text.length - 1, !isWhitespace(cursor) {
            cursor += direction
        }
        return min(max(cursor, 0), text.length - 1)
    }

    private func selectedHandleIndex() -> Int? {
        guard let session = adjustmentSession, let selected = session.selectedHandle else { return nil }
        switch session.anchor {
        case .text:
            return selected == .textStart ? 0 : selected == .textEnd ? 1 : nil
        case let .area(anchor):
            guard case let .area(handle) = selected, handle != .move, let page = session.page else { return nil }
            let viewRect = convert(cgRect(anchor.rect), from: page).standardized
            return areaHandleRects(viewRect: viewRect).firstIndex(where: { $0.handle == handle })
        }
    }

    private func textHandleRects(
        anchor: TextAnnotationAnchor,
        page: PDFPage
    ) -> [(handle: AnnotationAdjustmentHandle, rect: CGRect)] {
        guard let first = anchor.quadrilaterals.first,
              let last = anchor.quadrilaterals.last else { return [] }
        let start = convert(CGPoint(x: first.lowerLeft.x, y: first.lowerLeft.y), from: page)
        let end = convert(CGPoint(x: last.lowerRight.x, y: last.lowerRight.y), from: page)
        return [
            (.textStart, handleRect(center: start, size: 12)),
            (.textEnd, handleRect(center: end, size: 12))
        ]
    }

    private func areaHandleRects(
        viewRect: CGRect
    ) -> [(handle: AreaAdjustmentHandle, rect: CGRect)] {
        let centers: [(AreaAdjustmentHandle, CGPoint)] = [
            (.bottomLeft, CGPoint(x: viewRect.minX, y: viewRect.minY)),
            (.bottom, CGPoint(x: viewRect.midX, y: viewRect.minY)),
            (.bottomRight, CGPoint(x: viewRect.maxX, y: viewRect.minY)),
            (.right, CGPoint(x: viewRect.maxX, y: viewRect.midY)),
            (.topRight, CGPoint(x: viewRect.maxX, y: viewRect.maxY)),
            (.top, CGPoint(x: viewRect.midX, y: viewRect.maxY)),
            (.topLeft, CGPoint(x: viewRect.minX, y: viewRect.maxY)),
            (.left, CGPoint(x: viewRect.minX, y: viewRect.midY))
        ]
        return centers.map { ($0.0, handleRect(center: $0.1, size: 10)) }
    }

    private func handleRect(center: CGPoint, size: CGFloat) -> CGRect {
        CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    private func cgRect(_ rectangle: AnnotationRect) -> CGRect {
        CGRect(x: rectangle.x, y: rectangle.y, width: rectangle.width, height: rectangle.height)
    }

    private func quadrilateralRect(_ quadrilateral: AnnotationQuadrilateral) -> CGRect {
        let points = [
            quadrilateral.upperLeft,
            quadrilateral.upperRight,
            quadrilateral.lowerLeft,
            quadrilateral.lowerRight
        ]
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return CGRect(
            x: xs.min() ?? 0,
            y: ys.min() ?? 0,
            width: (xs.max() ?? 0) - (xs.min() ?? 0),
            height: (ys.max() ?? 0) - (ys.min() ?? 0)
        )
    }

    private func quadrilateralBounds(_ quadrilaterals: [AnnotationQuadrilateral]) -> CGRect {
        quadrilaterals.map(quadrilateralRect).reduce(.null) { $0.union($1) }
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
    var adjustmentRegions: [CGRect] = [] {
        didSet { needsDisplay = true }
    }
    var adjustmentHandles: [CGRect] = [] {
        didSet { needsDisplay = true }
    }
    var selectedAdjustmentHandleIndex: Int? {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let selectionRectangle, !selectionRectangle.isEmpty {
            drawRegion(selectionRectangle)
        }
        drawAdjustments()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    private func drawRegion(_ rectangle: CGRect) {
        let path = NSBezierPath(rect: rectangle)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.setLineDash([6, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func drawAdjustments() {
        for region in adjustmentRegions where !region.isEmpty {
            drawRegion(region)
        }
        for (index, handle) in adjustmentHandles.enumerated() {
            let path = NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2)
            if selectedAdjustmentHandleIndex == index {
                NSColor.controlAccentColor.setFill()
            } else {
                NSColor.controlBackgroundColor.setFill()
            }
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}

private final class PDFAnnotationAdjustmentSession {
    let annotationID: UUID
    let pageIndex: Int
    weak var page: PDFPage?
    var anchor: AnnotationAnchorValue
    var textRange: NSRange?
    var selectedHandle: AnnotationAdjustmentHandle?
    var dragStartPagePoint: CGPoint?
    var dragStartAreaRect: CGRect?

    init(
        annotationID: UUID,
        pageIndex: Int,
        page: PDFPage,
        anchor: AnnotationAnchorValue,
        textRange: NSRange?
    ) {
        self.annotationID = annotationID
        self.pageIndex = pageIndex
        self.page = page
        self.anchor = anchor
        self.textRange = textRange
    }
}

private struct PDFAnnotationContextTarget {
    let annotationID: UUID
    let pageIndex: Int
    let regions: [CGRect]
}

private final class AnnotationContextMenuActionTarget: NSObject {
    private let onAdjust: () -> Void
    private let onDelete: () -> Void

    init(onAdjust: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.onAdjust = onAdjust
        self.onDelete = onDelete
    }

    @objc func adjustAnnotation(_ sender: Any?) {
        onAdjust()
    }

    @objc func deleteAnnotation(_ sender: Any?) {
        onDelete()
    }
}

private enum AnnotationAdjustmentHandle: Equatable {
    case textStart
    case textEnd
    case area(AreaAdjustmentHandle)

    var accessibilityName: String {
        switch self {
        case .textStart: "Start boundary"
        case .textEnd: "End boundary"
        case let .area(handle): handle.accessibilityName
        }
    }
}

private typealias AreaAdjustmentHandle = AreaAnnotationAdjustmentHandle

private extension AreaAnnotationAdjustmentHandle {
    var accessibilityName: String {
        switch self {
        case .move: "Move"
        case .bottomLeft: "Bottom-left resize handle"
        case .bottom: "Bottom resize handle"
        case .bottomRight: "Bottom-right resize handle"
        case .right: "Right resize handle"
        case .topRight: "Top-right resize handle"
        case .top: "Top resize handle"
        case .topLeft: "Top-left resize handle"
        case .left: "Left resize handle"
        }
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
