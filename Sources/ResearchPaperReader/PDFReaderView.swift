import PDFKit
import SwiftUI

enum ZoomAction: Equatable {
    case `in`, out, fit
}

struct AreaNoteSelection: Identifiable, Equatable {
    let id = UUID()
    let rect: CGRect
    let page: PDFPage
}

struct PDFReaderView: NSViewRepresentable {
    let url: URL
    @Binding var selectedText: String
    @Binding var selectedPage: Int?
    var notes: [PaperNote]
    @Binding var navigateToPage: Int?
    @Binding var navigateToRect: CGRect?
    @Binding var zoomFactor: CGFloat
    @Binding var zoomAction: ZoomAction?
    @Binding var findText: String
    @Binding var findCurrentIndex: Int
    @Binding var findMatchesCount: Int
    
    @Binding var isCropModeActive: Bool
    @Binding var cropResult: AreaNoteSelection?
    @Binding var hoveredNoteID: UUID?
    @Binding var hoveredNotePoint: CGPoint

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CropPDFContainerView {
        let containerView = CropPDFContainerView()
        let pdfView = containerView.pdfView
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = PDFDocument(url: url)
        
        pdfView.onCropCompleted = { rect, page in
            DispatchQueue.main.async {
                self.cropResult = AreaNoteSelection(rect: rect, page: page)
                self.isCropModeActive = false
            }
        }
        
        pdfView.onNoteHovered = { noteID, point in
            DispatchQueue.main.async {
                self.hoveredNoteID = noteID
                self.hoveredNotePoint = point
            }
        }
        
        pdfView.onNoteHoverEnded = {
            DispatchQueue.main.async {
                if self.hoveredNoteID != nil {
                    self.hoveredNoteID = nil
                }
            }
        }
        
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
        return containerView
    }

    func updateNSView(_ containerView: CropPDFContainerView, context: Context) {
        context.coordinator.parent = self
        let nsView = containerView.pdfView

        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
            nsView.autoScales = true
        }

        if nsView.isCropModeActive != isCropModeActive {
            nsView.isCropModeActive = isCropModeActive
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
        let rect = navigateToRect
        let pageChanged = page != context.coordinator.lastNavigatedPage
        let rectChanged = rect != context.coordinator.lastNavigatedRect
        if (pageChanged || rectChanged), let page {
            context.coordinator.lastNavigatedPage = page
            context.coordinator.lastNavigatedRect = rect
            if let document = nsView.document, page > 0, page <= document.pageCount {
                let pdfPage = document.page(at: page - 1)
                if let pdfPage {
                    if let rect {
                        nsView.go(to: rect, on: pdfPage)
                        DispatchQueue.main.async {
                            self.navigateToRect = nil
                        }
                    } else {
                        nsView.go(to: pdfPage)
                    }
                }
            }
        }

        let searchText = findText
        if searchText != context.coordinator.lastSearchedText {
            context.coordinator.lastSearchedText = searchText
            if !searchText.isEmpty, let document = nsView.document {
                let selections = document.findString(searchText, withOptions: .caseInsensitive)
                if findMatchesCount != selections.count {
                    DispatchQueue.main.async {
                        self.findMatchesCount = selections.count
                    }
                }
                if findCurrentIndex >= 0 && findCurrentIndex < selections.count {
                    let selection = selections[findCurrentIndex]
                    if nsView.currentSelection != selection {
                        nsView.currentSelection = selection
                        nsView.go(to: selection)
                    }
                }
            } else {
                if findMatchesCount != 0 {
                    DispatchQueue.main.async {
                        self.findMatchesCount = 0
                    }
                    nsView.clearSelection()
                }
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: PDFReaderView
        private var lastNotesHash: Int = 0
        var lastNavigatedPage: Int?
        var lastNavigatedRect: CGRect?
        private var lastPage: Int = 0
        private var lastZoom: CGFloat = 0
        var lastSearchedText: String = ""
        weak var pdfView: PDFView?

        init(_ parent: PDFReaderView) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
                    let name = annotation.value(forAnnotationKey: .name) as? String
                    return name == "ResearchPaperReader" || name.flatMap(UUID.init(uuidString:)) != nil
                }
                for annotation in toRemove {
                    page.removeAnnotation(annotation)
                }
            }

            for note in notes {
                if note.isAreaNote {
                    guard let pageIndex = note.page,
                          pageIndex > 0, pageIndex <= document.pageCount,
                          let page = document.page(at: pageIndex - 1),
                          let x = note.rectX,
                          let y = note.rectY,
                          let w = note.rectWidth,
                          let h = note.rectHeight else {
                        continue
                    }
                    
                    let bounds = CGRect(x: x, y: y, width: w, height: h)
                    let annotation = PDFAnnotation(bounds: bounds, forType: .square, withProperties: nil)
                    annotation.color = note.kind.color
                    annotation.interiorColor = note.kind.color.withAlphaComponent(0.15)
                    annotation.setValue(note.id.uuidString, forAnnotationKey: .name)
                    page.addAnnotation(annotation)
                } else if !note.quote.isEmpty {
                    let selections = document.findString(note.quote, withOptions: .caseInsensitive)
                    guard !selections.isEmpty else { continue }

                    for selection in selections {
                        for page in selection.pages {
                            let bounds = selection.bounds(for: page)
                            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                            annotation.color = note.kind.color
                            annotation.setValue(note.id.uuidString, forAnnotationKey: .name)
                            page.addAnnotation(annotation)
                        }
                    }
                }
            }
        }
    }
}

final class CropPDFContainerView: NSView {
    let pdfView = CropPDFView()
    private let selectionOverlay = CropSelectionOverlayView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installSubviews()
    }

    private func installSubviews() {
        pdfView.frame = bounds
        pdfView.autoresizingMask = [.width, .height]
        addSubview(pdfView)

        selectionOverlay.frame = bounds
        selectionOverlay.autoresizingMask = [.width, .height]
        selectionOverlay.wantsLayer = true
        addSubview(selectionOverlay, positioned: .above, relativeTo: pdfView)
        selectionOverlay.pdfView = pdfView

        pdfView.onCropModeChanged = { [weak self] isActive in
            self?.selectionOverlay.isCropModeActive = isActive
        }
    }
}

final class CropPDFView: PDFView {
    var isCropModeActive = false {
        didSet {
            window?.invalidateCursorRects(for: self)
            onCropModeChanged?(isCropModeActive)
        }
    }
    
    var onCropCompleted: ((CGRect, PDFPage) -> Void)?
    var onCropModeChanged: ((Bool) -> Void)?
    var onNoteHovered: ((UUID, CGPoint) -> Void)?
    var onNoteHoverEnded: (() -> Void)?
    
    private var trackingArea: NSTrackingArea?
    private var hoverTimer: Timer?
    private var currentHoveredNoteID: UUID?
    private var hoverPoint: CGPoint = .zero
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }
    
    override func resetCursorRects() {
        if isCropModeActive {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            super.resetCursorRects()
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !isCropModeActive else {
            cancelHoverTimer()
            return
        }
        
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: false) else {
            cancelHoverTimer()
            return
        }
        
        let pagePoint = convert(viewPoint, to: page)
        
        if let annotation = page.annotation(at: pagePoint),
           let noteIDString = annotation.value(forAnnotationKey: .name) as? String,
           let noteID = UUID(uuidString: noteIDString) {
            
            let swiftPoint = CGPoint(x: viewPoint.x, y: bounds.height - viewPoint.y)
            handleHover(for: noteID, at: swiftPoint)
            return
        }
        
        cancelHoverTimer()
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        cancelHoverTimer()
    }
    
    private func handleHover(for noteID: UUID, at point: CGPoint) {
        if currentHoveredNoteID == noteID {
            hoverPoint = point
            return
        }
        
        cancelHoverTimer()
        currentHoveredNoteID = noteID
        hoverPoint = point
        
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, self.currentHoveredNoteID == noteID else { return }
                self.onNoteHovered?(noteID, self.hoverPoint)
            }
        }
    }
    
    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        if currentHoveredNoteID != nil {
            currentHoveredNoteID = nil
            onNoteHoverEnded?()
        }
    }
}

private final class CropSelectionOverlayView: NSView {
    weak var pdfView: CropPDFView?
    var isCropModeActive = false {
        didSet {
            window?.invalidateCursorRects(for: self)
            if !isCropModeActive {
                clearSelection()
            }
        }
    }

    private var selectionStart: CGPoint?
    private var selectionEnd: CGPoint?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isCropModeActive ? self : nil
    }

    override func resetCursorRects() {
        if isCropModeActive {
            addCursorRect(bounds, cursor: .crosshair)
        } else {
            super.resetCursorRects()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isCropModeActive else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionStart = point
        selectionEnd = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isCropModeActive, selectionStart != nil else { return }
        selectionEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isCropModeActive,
              let start = selectionStart,
              let end = selectionEnd,
              let pdfView else {
            clearSelection()
            return
        }

        let selectionRect = normalizedSelectionRect(from: start, to: end)
        if selectionRect.width > 5, selectionRect.height > 5 {
            let startInPDFView = pdfView.convert(start, from: self)
            let rectInPDFView = pdfView.convert(selectionRect, from: self)
            if let page = pdfView.page(for: startInPDFView, nearest: true) {
                let pageRect = pdfView.convert(rectInPDFView, to: page)
                pdfView.onCropCompleted?(pageRect, page)
            }
        }

        clearSelection()
    }

    private func clearSelection() {
        selectionStart = nil
        selectionEnd = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let start = selectionStart,
              let end = selectionEnd,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let selectionRect = normalizedSelectionRect(from: start, to: end)

        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        let dimmingPath = CGMutablePath()
        dimmingPath.addRect(bounds)
        dimmingPath.addRect(selectionRect)
        context.addPath(dimmingPath)
        context.drawPath(using: .eoFill)

        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(2)
        context.stroke(selectionRect)

        let handleSize: CGFloat = 6
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill([
            CGRect(x: selectionRect.minX - handleSize / 2, y: selectionRect.minY - handleSize / 2, width: handleSize, height: handleSize),
            CGRect(x: selectionRect.maxX - handleSize / 2, y: selectionRect.minY - handleSize / 2, width: handleSize, height: handleSize),
            CGRect(x: selectionRect.minX - handleSize / 2, y: selectionRect.maxY - handleSize / 2, width: handleSize, height: handleSize),
            CGRect(x: selectionRect.maxX - handleSize / 2, y: selectionRect.maxY - handleSize / 2, width: handleSize, height: handleSize)
        ])
    }

    private func normalizedSelectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
    }
}
