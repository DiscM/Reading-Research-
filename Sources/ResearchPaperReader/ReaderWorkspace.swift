import SwiftUI

struct ReaderWorkspace: View {
    @EnvironmentObject private var store: PaperStore
    @AppStorage("resumeLastReadLocation") private var resumeLastReadLocation = true
    @Binding var paper: Paper
    @Binding var navigateToPage: Int?
    @State private var selectedText = ""
    @State private var selectedPage: Int?
    @State private var newNote = ""
    @State private var noteKind: HighlightKind = .highlight
    @State private var aiExtraction = ""
    @State private var aiExplanation = ""
    @State private var isInspectorCollapsed = false
    @State private var isGeneratingAI = false
    @State private var zoomFactor: CGFloat = 0
    @State private var zoomAction: ZoomAction?
    @State private var showGoToPage = false
    @State private var goToPageNumber = ""
    @State private var showFindBar = false
    @State private var findText = ""
    @State private var findMatchesCount = 0
    @State private var findCurrentIndex = 0
    @State private var summaryExpanded = true
    @State private var explanationExpanded = true
    @State private var pendingResumePage: Int?
    @State private var receivedInitialPage = false
    @State private var hoveredNoteID: UUID? = nil
    @State private var isCropModeActive = false
    @State private var cropResult: AreaNoteSelection? = nil
    @State private var tempImageFileName: String? = nil
    @State private var hoveredNotePoint: CGPoint = .zero
    @State private var navigateToRect: CGRect? = nil

    private var extractionKinds: [HighlightKind] {
        switch paper.documentKind {
        case .researchPaper:
            [.claim, .method, .evidence, .limitation]
        case .lectureSlides, .studyNotes:
            [.highlight, .definition, .question, .evidence]
        case .bookChapter, .generalPDF:
            [.highlight, .claim, .evidence, .definition]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showFindBar {
                findBar
            }

            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PDFReaderView(
                        url: paper.fileURL,
                        selectedText: $selectedText,
                        selectedPage: $selectedPage,
                        notes: paper.notes,
                        navigateToPage: $navigateToPage,
                        navigateToRect: $navigateToRect,
                        zoomFactor: $zoomFactor,
                        zoomAction: $zoomAction,
                        findText: $findText,
                        findCurrentIndex: $findCurrentIndex,
                        findMatchesCount: $findMatchesCount,
                        isCropModeActive: $isCropModeActive,
                        cropResult: $cropResult,
                        hoveredNoteID: $hoveredNoteID,
                        hoveredNotePoint: $hoveredNotePoint
                    )
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)

                    // Floating hover popover
                    if let noteID = hoveredNoteID,
                       let note = paper.notes.first(where: { $0.id == noteID }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(nsColor: note.kind.color))
                                    .frame(width: 8, height: 8)
                                Text(note.kind.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(note.body)
                                .font(.callout)
                                .foregroundStyle(.primary)
                        }
                        .padding(12)
                        .background(.background)
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, lineWidth: 1))
                        .frame(maxWidth: 260)
                        .position(x: hoveredNotePoint.x + 10, y: hoveredNotePoint.y + 20)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .onChange(of: navigateToPage) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        navigateToPage = nil
                    }
                }

                if !isInspectorCollapsed {
                    Divider()

                    VStack(spacing: 0) {
                        PaperInspectorHeader(paper: $paper)

                        TabView {
                            notesPanel
                                .tabItem {
                                    Label("Notes", systemImage: "note.text")
                                }

                            aiPanel
                                .tabItem {
                                    Label("AI", systemImage: "sparkles")
                                }
                        }
                    }
                    .frame(width: 360)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .navigationTitle(paper.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    zoomAction = .out
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                if zoomFactor > 0 {
                    Text("\(Int(zoomFactor * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44)
                }

                Button {
                    zoomAction = .in
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In")

                Divider()
                    .frame(height: 16)

                Text("p. \(selectedPage ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    isCropModeActive.toggle()
                } label: {
                    Image(systemName: isCropModeActive ? "square.dashed.inset.filled" : "square.dashed")
                        .foregroundStyle(isCropModeActive ? .blue : .primary)
                }
                .help("Area Note (Drag to select area)")

                Button {
                    showGoToPage = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .help("Go to Page…")
                .keyboardShortcut("g", modifiers: .command)
            }

            ToolbarItem {
                Button {
                    withAnimation {
                        isInspectorCollapsed.toggle()
                    }
                } label: {
                    Label(isInspectorCollapsed ? "Show Inspector" : "Hide Inspector", systemImage: "sidebar.right")
                }
                .help(isInspectorCollapsed ? "Show Inspector" : "Hide Inspector")
            }
        }
        .sheet(isPresented: $showGoToPage) {
            goToPageSheet
        }
        .onAppear {
            prepareReadingPosition()
        }
        .onDisappear {
            cleanupTempImage()
        }
        .onChange(of: paper.id) { _, _ in
            cleanupTempImage()
            tempImageFileName = nil
            cropResult = nil
            selectedPage = nil
            prepareReadingPosition()
        }
        .onChange(of: selectedPage) { _, newPage in
            handlePageChange(newPage)
        }
        .onChange(of: cropResult) { _, newResult in
            if let newResult {
                cleanupTempImage()
                tempImageFileName = store.saveAreaNoteImage(from: newResult.page, rect: newResult.rect)
                if let pageIndex = newResult.page.document?.index(for: newResult.page) {
                    selectedPage = pageIndex + 1
                }
            }
        }
        .onChange(of: showFindBar) { _, newValue in
            if !newValue {
                findText = ""
                findCurrentIndex = 0
                findMatchesCount = 0
            }
        }
        .background {
            Button("") { showFindBar.toggle() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    private func prepareReadingPosition() {
        pendingResumePage = nil
        receivedInitialPage = false

        guard resumeLastReadLocation,
              let savedPage = paper.lastReadPage,
              savedPage > 1 else { return }

        let targetPage = paper.pageCount > 0 ? min(savedPage, paper.pageCount) : savedPage
        guard targetPage > 1 else { return }

        pendingResumePage = targetPage
        DispatchQueue.main.async {
            navigateToPage = targetPage
        }
    }

    private func handlePageChange(_ page: Int?) {
        guard let page, page > 0 else { return }

        if let targetPage = pendingResumePage {
            if page == targetPage {
                pendingResumePage = nil
                receivedInitialPage = true
                paper.recordReadingProgress(page: page)
            }
            return
        }

        if !receivedInitialPage {
            receivedInitialPage = true
            if paper.lastReadPage == nil {
                paper.recordReadingProgress(page: page)
            }
            return
        }

        paper.recordReadingProgress(page: page)
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Color(nsColor: noteKind.color)
                        .frame(width: 14, height: 14)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.quaternary, lineWidth: 1))

                    Picker("Type", selection: $noteKind) {
                        ForEach(HighlightKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }

                    Spacer()

                    if let selectedPage {
                        Text("Page \(selectedPage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let tempFile = tempImageFileName {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Area Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        let fileURL = store.imageUrl(for: tempFile)
                        if let nsImage = NSImage(contentsOf: fileURL) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 120)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))
                        }
                        
                        Button("Cancel Selection", role: .destructive) {
                            if let oldFile = tempImageFileName {
                                let fileURL = store.imageUrl(for: oldFile)
                                try? FileManager.default.removeItem(at: fileURL)
                            }
                            tempImageFileName = nil
                            cropResult = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                } else {
                    if selectedText.isEmpty {
                        Text("Select text or click the Area Note tool (toolbar) to select a visual area.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(selectedText)
                            .font(.callout)
                            .lineLimit(4)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                TextEditor(text: $newNote)
                    .frame(height: 92)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )

                Button {
                    if let tempFile = tempImageFileName, let crop = cropResult {
                        store.addNote(
                            to: paper,
                            kind: noteKind,
                            quote: "",
                            body: newNote,
                            page: selectedPage,
                            isAreaNote: true,
                            rectX: Double(crop.rect.origin.x),
                            rectY: Double(crop.rect.origin.y),
                            rectWidth: Double(crop.rect.width),
                            rectHeight: Double(crop.rect.height),
                            imageFileName: tempFile
                        )
                        tempImageFileName = nil
                        cropResult = nil
                    } else {
                        store.addNote(
                            to: paper,
                            kind: noteKind,
                            quote: selectedText,
                            body: newNote,
                            page: selectedPage
                        )
                    }
                    newNote = ""
                } label: {
                    Label("Save Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (tempImageFileName == nil && selectedText.isEmpty) ||
                    newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding()

            Divider()

            List {
                ForEach(paper.notes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: note.kind.color))
                                .frame(width: 8, height: 8)

                            Text(note.kind.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let page = note.page {
                                Text("p. \(page)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                withAnimation {
                                    store.deleteNote(note, from: paper)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(hoveredNoteID == note.id ? 1.0 : 0.4))
                            }
                            .buttonStyle(.plain)
                            .help("Delete Note")
                        }

                        if note.isAreaNote {
                            if let imgFile = note.imageFileName {
                                let fileURL = store.imageUrl(for: imgFile)
                                if let nsImage = NSImage(contentsOf: fileURL) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 100)
                                        .cornerRadius(4)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary, lineWidth: 1))
                                }
                            }
                        } else if !note.quote.isEmpty {
                            Text(note.quote)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(.leading, 8)
                                .overlay(
                                    Rectangle()
                                        .fill(Color(nsColor: note.kind.color).opacity(0.5))
                                        .frame(width: 2),
                                    alignment: .leading
                                )
                        }

                        Text(note.body)
                            .font(.body)
                    }
                    .padding(8)
                    .background(hoveredNoteID == note.id ? Color.secondary.opacity(0.08) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let page = note.page {
                            if note.isAreaNote,
                               let x = note.rectX, let y = note.rectY,
                               let w = note.rectWidth, let h = note.rectHeight {
                                navigateToRect = CGRect(x: x, y: y, width: w, height: h)
                            }
                            navigateToPage = page
                        }
                    }
                    .onHover { isHovered in
                        if isHovered {
                            hoveredNoteID = note.id
                        } else if hoveredNoteID == note.id {
                            hoveredNoteID = nil
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var aiPanel: some View {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Button {
                            runAIAction {
                                await store.generateSummary(for: paper)
                                explanationExpanded = false
                                summaryExpanded = true
                            }
                        } label: {
                            Label("Summarize", systemImage: "text.badge.checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(isGeneratingAI)

                        Menu {
                            ForEach(extractionKinds) { kind in
                                Button {
                                    runAIAction {
                                        aiExplanation = ""
                                        aiExtraction = await store.generateExtraction(for: paper, kind: kind)
                                        summaryExpanded = false
                                        explanationExpanded = true
                                    }
                                } label: {
                                    Label(kind.rawValue, systemImage: "circle.fill")
                                }
                            }
                        } label: {
                            Label("Extract", systemImage: "line.3.horizontal.decrease.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isGeneratingAI)
                    }

                    GridRow {
                        Button {
                            let textToExplain = selectedText
                            runAIAction {
                                aiExtraction = ""
                                aiExplanation = await LocalPaperAI.explainSelection(textToExplain, in: paper)
                                summaryExpanded = false
                                explanationExpanded = true
                            }
                        } label: {
                            Label("Explain Selection", systemImage: "questionmark.bubble")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isGeneratingAI || selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            store.exportMarkdown(for: paper)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                AIStatusBadge()

                CollapsibleSection(title: "Summary", isExpanded: $summaryExpanded) {
                    if let summary = paper.aiSummary {
                        AIResultBody(bodyText: summary)
                    } else {
                        Text("Run Summarize to generate a summary.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                }

                CollapsibleSection(title: "Explanation", isExpanded: $explanationExpanded) {
                    if aiExtraction.isEmpty && aiExplanation.isEmpty {
                        Text("Run Extract or Explain Selection to see results.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if !aiExtraction.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Extraction")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    AIResultBody(bodyText: aiExtraction)
                                }
                            }
                            if !aiExplanation.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Selection Explanation")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    AIResultBody(bodyText: aiExplanation)
                                }
                            }
                        }
                    }
                }

            }
            .padding()
        }
    }

    private func cleanupTempImage() {
        guard let oldFile = tempImageFileName else { return }
        try? FileManager.default.removeItem(at: store.imageUrl(for: oldFile))
    }

    private func runAIAction(_ action: @escaping () async -> Void) {
        guard !isGeneratingAI else { return }
        isGeneratingAI = true
        Task {
            await action()
            isGeneratingAI = false
        }
    }

        private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .imageScale(.small)

            TextField("Find in document", text: $findText)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: findText) { _, _ in
                    findCurrentIndex = 0
                }

            if findMatchesCount > 0 {
                Text("\(findCurrentIndex + 1) of \(findMatchesCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    findCurrentIndex = max(0, findCurrentIndex - 1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(findCurrentIndex <= 0)

                Button {
                    findCurrentIndex = min(findMatchesCount - 1, findCurrentIndex + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(findCurrentIndex >= findMatchesCount - 1)
            }

            Button {
                showFindBar = false
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var goToPageSheet: some View {
        VStack(spacing: 16) {
            Text("Go to Page")
                .font(.headline)

            TextField("Page number", text: $goToPageNumber)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .labelsHidden()

            HStack(spacing: 12) {
                Button("Cancel") {
                    showGoToPage = false
                    goToPageNumber = ""
                }
                .keyboardShortcut(.escape)

                Button("Go") {
                    if let page = Int(goToPageNumber), page > 0 {
                        navigateToPage = page
                    }
                    showGoToPage = false
                    goToPageNumber = ""
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(Int(goToPageNumber) == nil)
            }
        }
        .padding(24)
        .frame(width: 200)
    }
}

private struct PaperInspectorHeader: View {
    @Binding var paper: Paper
    @State private var showEditMetadata = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                Button {
                    showEditMetadata = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit Details")
            }

            HStack {
                Picker("Document Type", selection: $paper.documentKind) {
                    ForEach(DocumentKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                if !paper.authors.isEmpty {
                    Text(paper.authors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
        .sheet(isPresented: $showEditMetadata) {
            MetadataEditView(paper: $paper)
        }
    }
}

private struct AIStatusBadge: View {
    @AppStorage("aiMode") private var aiMode = "Private Local"
    @AppStorage("aiProvider") private var aiProvider = "Apple Foundation Models"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("\(aiMode) - \(aiProvider)")
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .help(LocalPaperAI.statusText)
    }
}

private struct AIResultBody: View {
    let bodyText: String

    var body: some View {
        MarkdownResultView(markdown: bodyText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetadataEditView: View {
    @Binding var paper: Paper
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var authors: String = ""
    @State private var year: String = ""
    @State private var venue: String = ""
    @State private var abstract: String = ""
    @State private var tags: [String] = []
    @State private var newTag: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Document Details")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                Form {
                    Section("Metadata") {
                        TextField("Title", text: $title)
                        TextField("Authors", text: $authors)
                        HStack {
                            TextField("Year", text: $year)
                            TextField("Venue", text: $venue)
                        }
                    }

                    Section("Abstract") {
                        TextEditor(text: $abstract)
                            .frame(minHeight: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(.quaternary, lineWidth: 1)
                            )
                    }

                    Section("Tags") {
                        VStack(alignment: .leading, spacing: 10) {
                            if !tags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.caption)
                                            Button {
                                                tags.removeAll { $0 == tag }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.secondary.opacity(0.15), in: Capsule())
                                    }
                                }
                            } else {
                                Text("No tags. Add some below.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                TextField("Add tag...", text: $newTag)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        addTag()
                                    }
                                Button(action: addTag) {
                                    Image(systemName: "plus")
                                }
                                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .padding(.bottom)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Save Changes") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding()
            .background(.bar)
        }
        .frame(width: 480, height: 560)
        .onAppear {
            title = paper.title
            authors = paper.authors
            year = paper.year
            venue = paper.venue
            abstract = paper.abstract
            tags = paper.tags
        }
    }

    private func addTag() {
        let cleaned = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if !tags.contains(cleaned) {
            tags.append(cleaned)
        }
        newTag = ""
    }

    private func save() {
        paper.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.authors = authors.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.year = year.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.venue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.abstract = abstract.trimmingCharacters(in: .whitespacesAndNewlines)
        paper.tags = tags
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? 400
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for size in sizes {
            if currentX + size.width > width {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
        height = currentY + rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
