import AppKit
import CanopyCore
import PDFKit
import SwiftUI

struct AnnotationInspectorView: View {
    let paper: Paper?
    let repository: LibraryRepository
    @Binding var focusedAnnotationID: UUID?
    let annotationUndoTarget: AnnotationUndoTarget
    let annotationSession: AnnotationSession
    let onRetrySource: () -> Void
    let onNavigate: (UUID) -> Void

    @Environment(\.undoManager) private var undoManager
    @State private var persistenceErrorMessage: String?
    @State private var previewDocumentSession: AnnotationPreviewDocumentSession?

    var body: some View {
        Group {
            if paper == nil {
                ContentUnavailableView(
                    "Annotations",
                    systemImage: "sidebar.right",
                    description: Text("Choose a Paper to inspect its highlights and notes.")
                )
            } else if let paper, annotationSession.paperID != paper.id {
                ProgressView("Verifying Source PDF…")
            } else if let paper, paper.sourceState != .available {
                ContentUnavailableView(
                    "Annotations Unavailable",
                    systemImage: "exclamationmark.shield",
                    description: Text("Canopy must verify this Paper’s original Source PDF before showing or editing its annotations.")
                )
            } else if let verificationErrorMessage = annotationSession.verificationErrorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Verify Source PDF", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verificationErrorMessage)
                } actions: {
                    Button("Retry", action: onRetrySource)
                }
            } else if !annotationSession.isSourceVerified {
                ProgressView("Verifying Source PDF…")
            } else if let loadErrorMessage = annotationSession.loadErrorMessage {
                ContentUnavailableView {
                    Label("Couldn’t Load Annotations", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    Button("Retry") {
                        annotationSession.reload(repository: repository)
                    }
                }
            } else {
                if annotationSession.annotations.isEmpty {
                    ContentUnavailableView(
                        "No Annotations",
                        systemImage: "highlighter",
                        description: Text("Select text for a highlight, or draw an Area Annotation for a figure, table, equation, or scanned passage.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(annotationSession.annotations) { annotation in
                                AnnotationRow(
                                    annotation: annotation,
                                    repository: repository,
                                    annotationUndoTarget: annotationUndoTarget,
                                    previewDocument: previewDocumentSession?.document,
                                    focusRequested: focusedAnnotationID == annotation.id,
                                    onNavigate: { onNavigate(annotation.id) },
                                    onDelete: { delete(annotation) },
                                    onDidChange: reloadAnnotations,
                                    onSaveError: showPersistenceError
                                )
                                .id(annotation.id)
                            }
                        }
                        .listStyle(.inset)
                        .onChange(of: focusedAnnotationID) { _, annotationID in
                            guard let annotationID else { return }
                            withAnimation {
                                proxy.scrollTo(annotationID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Annotations")
        .task(id: previewTaskID) {
            loadPreviewDocument()
        }
        .alert(
            "Couldn’t Save Annotation",
            isPresented: Binding(
                get: { persistenceErrorMessage != nil },
                set: { if !$0 { persistenceErrorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage ?? "Canopy could not save this annotation.")
        }
    }

    private func delete(_ annotation: Annotation) {
        do {
            let snapshot = try repository.deleteAnnotation(annotationID: annotation.id)
            if focusedAnnotationID == annotation.id {
                focusedAnnotationID = nil
            }
            AnnotationUndo.registerUndoForDeletion(
                snapshot: snapshot,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: reloadAnnotations,
                onError: showPersistenceError
            )
            reloadAnnotations()
        } catch {
            showPersistenceError(error)
        }
    }

    private func showPersistenceError(_ error: Error) {
        persistenceErrorMessage = error.localizedDescription
    }

    private func reloadAnnotations() {
        annotationSession.reload(repository: repository)
    }

    private var previewTaskID: String {
        let paperID = paper?.id.uuidString ?? "none"
        let verified = annotationSession.isSourceVerified ? "verified" : "unverified"
        let hasAreas = annotationSession.annotations.contains { $0.kind == .area } ? "areas" : "text"
        return "\(paperID):\(verified):\(hasAreas)"
    }

    private func loadPreviewDocument() {
        previewDocumentSession = nil
        guard let paper,
              annotationSession.paperID == paper.id,
              annotationSession.isSourceVerified,
              paper.sourceState == .available,
              annotationSession.annotations.contains(where: { $0.kind == .area }) else {
            return
        }
        do {
            previewDocumentSession = try AnnotationPreviewDocumentSession(
                sourceAccess: repository.sourceAccess(paperID: paper.id)
            )
        } catch {
            // The reader and annotation session remain the authoritative source-state
            // surfaces. A preview can retry when either is reloaded.
        }
    }
}

private struct AnnotationRow: View {
    let annotation: Annotation
    let repository: LibraryRepository
    let annotationUndoTarget: AnnotationUndoTarget
    let previewDocument: PDFDocument?
    let focusRequested: Bool
    let onNavigate: () -> Void
    let onDelete: () -> Void
    let onDidChange: () -> Void
    let onSaveError: (Error) -> Void

    @Environment(\.undoManager) private var undoManager
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides
    @State private var draftNote: String
    @State private var savedNote: String
    @FocusState private var noteFocused: Bool

    init(
        annotation: Annotation,
        repository: LibraryRepository,
        annotationUndoTarget: AnnotationUndoTarget,
        previewDocument: PDFDocument?,
        focusRequested: Bool,
        onNavigate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDidChange: @escaping () -> Void,
        onSaveError: @escaping (Error) -> Void
    ) {
        self.annotation = annotation
        self.repository = repository
        self.annotationUndoTarget = annotationUndoTarget
        self.previewDocument = previewDocument
        self.focusRequested = focusRequested
        self.onNavigate = onNavigate
        self.onDelete = onDelete
        self.onDidChange = onDidChange
        self.onSaveError = onSaveError
        _draftNote = State(initialValue: annotation.note)
        _savedNote = State(initialValue: annotation.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    "\(annotationKindName) · Page \(annotation.pageIndex + 1)",
                    systemImage: annotation.kind == .area ? "rectangle.dashed" : "highlighter"
                )
                    .font(.caption.weight(.semibold))
                Spacer()
                Menu {
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button {
                            changeColor(to: color)
                        } label: {
                            HighlightColorLabel(color: color, selected: annotation.color == color)
                        }
                    }
                } label: {
                    HighlightColorLabel(color: annotation.color, selected: true)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Annotation color")
                .accessibilityValue(annotation.color.displayName)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Annotation", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete Annotation")
            }

            annotationContent

            TextField("Add a note", text: $draftNote, axis: .vertical)
                .lineLimit(2...7)
                .textFieldStyle(.roundedBorder)
                .focused($noteFocused)
                .accessibilityIdentifier("annotation-note-field")
                .accessibilityLabel("Note for \(annotationKindName.lowercased()) on page \(annotation.pageIndex + 1)")
                .onSubmit { saveNote() }
        }
        .padding(.vertical, 6)
        .task(id: draftNote) {
            guard draftNote != savedNote else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            saveNote()
        }
        .onChange(of: noteFocused) { _, focused in
            if !focused { saveNote() }
        }
        .onChange(of: focusRequested) { _, requested in
            if requested { noteFocused = true }
        }
        .onChange(of: annotation.note) { _, note in
            guard note != savedNote else { return }
            if !noteFocused || draftNote == savedNote {
                draftNote = note
                savedNote = note
            }
        }
        .onAppear {
            if focusRequested { noteFocused = true }
        }
        .onDisappear {
            saveNote()
        }
    }

    private var appearance: HighlightAppearancePreferences {
        HighlightAppearancePreferences(increasedContrast: usesIncreasedContrast)
    }

    @ViewBuilder
    private var annotationContent: some View {
        switch annotation.kind {
        case .textHighlight:
            Button(action: onNavigate) {
                Text(annotation.textAnchor?.selectedText ?? "Text highlight")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        annotation.color.swiftUIColor.opacity(appearance.inspectorFillOpacity),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("text-highlight-quotation")
            .accessibilityLabel("Go to text highlight on page \(annotation.pageIndex + 1)")
            .accessibilityValue(annotation.textAnchor?.selectedText ?? "")
        case .area:
            Button(action: onNavigate) {
                if let previewDocument, let anchor = annotation.areaAnchor {
                    AreaAnnotationPreview(
                        annotationID: annotation.id,
                        document: previewDocument,
                        anchor: anchor,
                        color: annotation.color
                    )
                } else {
                    Label("Area preview unavailable", systemImage: "rectangle.dashed")
                        .frame(maxWidth: .infinity, minHeight: 92)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to Area Annotation on page \(annotation.pageIndex + 1)")
            .accessibilityHint("Centers and zooms the annotated region in the reader.")
        }
    }

    private var annotationKindName: String {
        annotation.kind == .area ? "Area Annotation" : "Text Highlight"
    }

    private var usesIncreasedContrast: Bool {
        accessibilityOverrides.usesIncreasedContrast(system: colorSchemeContrast == .increased)
    }

    private func saveNote() {
        guard draftNote != savedNote else { return }
        let oldNote = savedNote
        do {
            try repository.updateAnnotationNote(annotationID: annotation.id, note: draftNote)
            savedNote = draftNote
            AnnotationUndo.registerUndoForNoteChange(
                annotationID: annotation.id,
                previousNote: oldNote,
                currentNote: draftNote,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: onDidChange,
                onError: onSaveError
            )
            onDidChange()
        } catch {
            onSaveError(error)
        }
    }

    private func changeColor(to color: HighlightColor) {
        let previousColor = annotation.color
        guard color != previousColor else { return }
        do {
            try repository.updateAnnotationColor(annotationID: annotation.id, color: color)
            AnnotationUndo.registerUndoForColorChange(
                annotationID: annotation.id,
                previousColor: previousColor,
                currentColor: color,
                repository: repository,
                target: annotationUndoTarget,
                undoManager: undoManager,
                onChange: onDidChange,
                onError: onSaveError
            )
            onDidChange()
        } catch {
            onSaveError(error)
        }
    }
}

@MainActor
private final class AnnotationPreviewDocumentSession {
    let document: PDFDocument
    private let sourceAccess: PaperSourceAccess

    init(sourceAccess: PaperSourceAccess) throws {
        self.sourceAccess = sourceAccess
        guard let document = PDFDocument(url: sourceAccess.url) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.document = document
    }
}

private struct AreaAnnotationPreview: View {
    let annotationID: UUID
    let document: PDFDocument
    let anchor: AreaAnnotationAnchor
    let color: HighlightColor

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 150)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        color.swiftUIColor.opacity(appearance.areaBorderOpacity),
                        lineWidth: appearance.areaBorderWidth
                    )
            }

            if usesDifferentiateWithoutColor {
                Image(systemName: color.differentiateWithoutColorSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(usesIncreasedContrast ? Color.primary : color.swiftUIColor)
                    .padding(7)
                    .background(.regularMaterial, in: Circle())
                    .padding(6)
            }
        }
        .task(id: annotationID) {
            image = AreaAnnotationPreviewRenderer.render(document: document, anchor: anchor)
        }
        .accessibilityHidden(true)
    }

    private var appearance: HighlightAppearancePreferences {
        HighlightAppearancePreferences(increasedContrast: usesIncreasedContrast)
    }

    private var usesIncreasedContrast: Bool {
        accessibilityOverrides.usesIncreasedContrast(system: colorSchemeContrast == .increased)
    }

    private var usesDifferentiateWithoutColor: Bool {
        accessibilityOverrides.differentiatesWithoutColor(system: differentiateWithoutColor)
    }
}

@MainActor
private enum AreaAnnotationPreviewRenderer {
    static func render(document: PDFDocument, anchor: AreaAnnotationAnchor) -> NSImage? {
        guard let page = document.page(at: anchor.pageIndex) else { return nil }
        let pageBounds = page.bounds(for: .cropBox)
        let rectangle = CGRect(
            x: anchor.rect.x,
            y: anchor.rect.y,
            width: anchor.rect.width,
            height: anchor.rect.height
        )
        let contextX = max(rectangle.width * 0.22, 18)
        let contextY = max(rectangle.height * 0.22, 18)
        let sourceRectangle = rectangle
            .insetBy(dx: -contextX, dy: -contextY)
            .intersection(pageBounds)
        guard !sourceRectangle.isNull, !sourceRectangle.isEmpty else { return nil }

        let targetSize = NSSize(width: 480, height: 150)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.textBackgroundColor.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return nil }

        let scale = min(
            targetSize.width / sourceRectangle.width,
            targetSize.height / sourceRectangle.height
        )
        let drawnSize = CGSize(
            width: sourceRectangle.width * scale,
            height: sourceRectangle.height * scale
        )
        let drawnOrigin = CGPoint(
            x: (targetSize.width - drawnSize.width) / 2,
            y: (targetSize.height - drawnSize.height) / 2
        )

        context.saveGState()
        context.clip(to: CGRect(origin: drawnOrigin, size: drawnSize))
        context.translateBy(
            x: drawnOrigin.x - sourceRectangle.minX * scale,
            y: drawnOrigin.y - sourceRectangle.minY * scale
        )
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
        return image
    }
}

struct HighlightColorLabel: View {
    let color: HighlightColor
    var selected = false

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.canopyAccessibilityOverrides) private var accessibilityOverrides

    var body: some View {
        HStack(spacing: 4) {
            if usesDifferentiateWithoutColor {
                Image(systemName: color.differentiateWithoutColorSymbol)
                    .foregroundStyle(
                        usesIncreasedContrast ? Color.primary : color.swiftUIColor
                    )
                    .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(color.swiftUIColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().stroke(
                            .primary.opacity(usesIncreasedContrast ? 0.8 : 0.45),
                            lineWidth: appearance.swatchBorderWidth
                        )
                    )
            }
            Text(presentation.name)
            if let checkmarkSystemImage = presentation.checkmarkSystemImage {
                Image(systemName: checkmarkSystemImage)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    Color.primary.opacity(selected ? (usesIncreasedContrast ? 0.9 : 0.6) : 0),
                    lineWidth: presentation.borderWidth
                )
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
    }

    private var presentation: HighlightColorLabelPresentation {
        HighlightColorLabelPresentation(
            color: color,
            selected: selected,
            increasedContrast: usesIncreasedContrast
        )
    }

    private var appearance: HighlightAppearancePreferences {
        HighlightAppearancePreferences(increasedContrast: usesIncreasedContrast)
    }

    private var usesIncreasedContrast: Bool {
        accessibilityOverrides.usesIncreasedContrast(system: colorSchemeContrast == .increased)
    }

    private var usesDifferentiateWithoutColor: Bool {
        accessibilityOverrides.differentiatesWithoutColor(system: differentiateWithoutColor)
    }
}
