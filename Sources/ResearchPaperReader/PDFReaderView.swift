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

    func makeNSView(context: Context) -> CropPDFView {
        let pdfView = CropPDFView()
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
        return pdfView
    }

    func updateNSView(_ nsView: CropPDFView, context: Context) {
        context.coordinator.parent = self

        if nsView.document?.documentURL != url {
            context.coordinator.cleanupAnnotations(in: nsView)
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
        func cleanupAnnotations(in pdfView: PDFView) {
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

final class CropPDFView: PDFView {
    var isCropModeActive = false {
        didSet {
            window?.invalidateCursorRects(for: self)
            if !isCropModeActive {
                cropStartPoint = nil
                cropEndPoint = nil
            }
            needsDisplay = true
        }
    }
    
    var cropStartPoint: CGPoint?
    var cropEndPoint: CGPoint?
    var onCropCompleted: ((CGRect, PDFPage) -> Void)?
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
    
    override func mouseDown(with event: NSEvent) {
        guard isCropModeActive else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        cropStartPoint = point
        cropEndPoint = point
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isCropModeActive, cropStartPoint != nil else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        cropEndPoint = point
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isCropModeActive, let start = cropStartPoint, let end = cropEndPoint else {
            super.mouseUp(with: event)
            return
        }
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        )
        if rect.width > 5 && rect.height > 5 {
            if let page = page(for: start, nearest: true) {
                let pageRect = convert(rect, to: page)
                onCropCompleted?(pageRect, page)
            }
        }
        cropStartPoint = nil
        cropEndPoint = nil
        needsDisplay = true
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
    
    override func draw(_ rect: NSRect) {
        super.draw(rect)
        
        if isCropModeActive, let start = cropStartPoint, let end = cropEndPoint {
            let selectRect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(start.x - end.x),
                height: abs(start.y - end.y)
            )
            
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(selectRect)
            context.addPath(path)
            context.drawPath(using: .eoFill)
            
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.stroke(selectRect)
            
            let handleSize: CGFloat = 6
            context.setFillColor(NSColor.systemBlue.cgColor)
            let handles = [
                CGRect(x: selectRect.minX - handleSize/2, y: selectRect.minY - handleSize/2, width: handleSize, height: handleSize),
                CGRect(x: selectRect.maxX - handleSize/2, y: selectRect.minY - handleSize/2, width: handleSize, height: handleSize),
                CGRect(x: selectRect.minX - handleSize/2, y: selectRect.maxY - handleSize/2, width: handleSize, height: handleSize),
                CGRect(x: selectRect.maxX - handleSize/2, y: selectRect.maxY - handleSize/2, width: handleSize, height: handleSize)
            ]
            context.fill(handles)
        }
    }
}
