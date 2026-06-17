import SwiftUI

struct ReaderWorkspace: View {
    @EnvironmentObject private var store: PaperStore
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
    @State private var findMatches: [String] = []
    @State private var findCurrentIndex = 0
    @State private var summaryExpanded = true
    @State private var explanationExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if showFindBar {
                findBar
            }

            HSplitView {
            PDFReaderView(
                url: paper.fileURL,
                selectedText: $selectedText,
                selectedPage: $selectedPage,
                notes: paper.notes,
                navigateToPage: $navigateToPage,
                zoomFactor: $zoomFactor,
                zoomAction: $zoomAction
            )
            .frame(minWidth: 420)
            .onChange(of: navigateToPage) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    navigateToPage = nil
                }
            }

            if !isInspectorCollapsed {
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
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
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
        .onChange(of: showFindBar) { _, _ in if !showFindBar { findText = ""; findMatches = [] } }
        .background {
            Button("") { showFindBar.toggle() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
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

                if selectedText.isEmpty {
                    Text("Select text in the PDF to anchor a note.")
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

                TextEditor(text: $newNote)
                    .frame(height: 92)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary)
                    )

                Button {
                    store.addNote(
                        to: paper,
                        kind: noteKind,
                        quote: selectedText,
                        body: newNote,
                        page: selectedPage
                    )
                    newNote = ""
                } label: {
                    Label("Save Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedText.isEmpty || newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("n", modifiers: .command)
            }
            .padding()

            Divider()

            List {
                ForEach(paper.notes) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(note.kind.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let page = note.page {
                                Text("p. \(page)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !note.quote.isEmpty {
                            Text(note.quote)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        Text(note.body)
                            .font(.body)
                    }
                    .padding(.vertical, 6)
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
                            ForEach([HighlightKind.claim, .method, .evidence, .limitation]) { kind in
                                Button {
                                    runAIAction {
                                        aiExtraction = await store.generateExtraction(for: paper, kind: kind)
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
                                aiExplanation = await LocalPaperAI.explainSelection(textToExplain, in: paper)
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
                                    Text("Selection Context")
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

            TextField("Find in paper", text: $findText)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: findText) { _, newValue in
                    guard newValue.count >= 2 else { findMatches = []; return }
                    findMatches = LocalPaperAI.sentenceCandidates(from: paper.allText)
                        .filter { $0.localizedCaseInsensitiveContains(newValue) }
                    findCurrentIndex = 0
                }

            if !findMatches.isEmpty {
                Text("\(findCurrentIndex + 1) of \(findMatches.count)")
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
                    findCurrentIndex = min(findMatches.count - 1, findCurrentIndex + 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(findCurrentIndex >= findMatches.count - 1)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(2)

            Text(paper.authors)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
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
        Text(bodyText)
            .font(.body)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
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
