import CanopyCore
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
                        description: Text("Select text in the Paper to add a highlight and optional note.")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(annotationSession.annotations) { annotation in
                                AnnotationRow(
                                    annotation: annotation,
                                    repository: repository,
                                    annotationUndoTarget: annotationUndoTarget,
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
}

private struct AnnotationRow: View {
    let annotation: Annotation
    let repository: LibraryRepository
    let annotationUndoTarget: AnnotationUndoTarget
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
        focusRequested: Bool,
        onNavigate: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onDidChange: @escaping () -> Void,
        onSaveError: @escaping (Error) -> Void
    ) {
        self.annotation = annotation
        self.repository = repository
        self.annotationUndoTarget = annotationUndoTarget
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
                Label("Page \(annotation.pageIndex + 1)", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                Spacer()
                HighlightColorLabel(color: annotation.color, selected: true)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Highlight", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete Highlight")
            }

            Button(action: onNavigate) {
                Text(annotation.selectedText)
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
            .accessibilityLabel("Go to highlight on page \(annotation.pageIndex + 1)")

            TextField("Add a note", text: $draftNote, axis: .vertical)
                .lineLimit(2...7)
                .textFieldStyle(.roundedBorder)
                .focused($noteFocused)
                .accessibilityLabel("Note for highlight on page \(annotation.pageIndex + 1)")
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
            Text(color.displayName)
            if selected {
                Image(systemName: "checkmark")
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityValue(selected ? "Selected" : "Not selected")
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
