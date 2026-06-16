import SwiftUI

struct ReaderWorkspace: View {
    @EnvironmentObject private var store: PaperStore
    @Binding var paper: Paper
    @State private var selectedText = ""
    @State private var selectedPage: Int?
    @State private var newNote = ""
    @State private var noteKind: HighlightKind = .highlight
    @State private var aiExtraction = ""
    @State private var aiExplanation = ""

    var body: some View {
        HSplitView {
            PDFReaderView(
                url: paper.fileURL,
                selectedText: $selectedText,
                selectedPage: $selectedPage,
                notes: paper.notes
            )
            .frame(minWidth: 520)

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

                    metadataPanel
                        .tabItem {
                            Label("Details", systemImage: "info.circle")
                        }
                }
            }
            .frame(minWidth: 360, idealWidth: 430, maxWidth: 540)
        }
        .navigationTitle(paper.title)
    }

    private var notesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
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
                HStack {
                    Button {
                        store.generateSummary(for: paper)
                    } label: {
                        Label("Summarize", systemImage: "text.badge.checkmark")
                    }
                    .buttonStyle(.borderedProminent)

                    Menu {
                        ForEach([HighlightKind.claim, .method, .evidence, .limitation]) { kind in
                            Button(kind.rawValue) {
                                aiExtraction = store.generateExtraction(for: paper, kind: kind)
                            }
                        }
                    } label: {
                        Label("Extract", systemImage: "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        aiExplanation = LocalPaperAI.explainSelection(selectedText, in: paper)
                    } label: {
                        Label("Explain Selection", systemImage: "questionmark.bubble")
                    }
                    .disabled(selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        store.exportMarkdown(for: paper)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                AIStatusBadge()

                if let summary = paper.aiSummary {
                    AIResultView(title: "Paper Summary", bodyText: summary)
                }

                if !aiExtraction.isEmpty {
                    AIResultView(title: "Extraction", bodyText: aiExtraction)
                }

                if !aiExplanation.isEmpty {
                    AIResultView(title: "Selection Context", bodyText: aiExplanation)
                }

                if paper.aiSummary == nil && aiExtraction.isEmpty && aiExplanation.isEmpty {
                    Text("Use local AI actions to summarize the paper, extract claims, or explain selected text. This MVP keeps all processing on device.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
    }

    private var metadataPanel: some View {
        Form {
            TextField("Title", text: $paper.title, axis: .vertical)
            TextField("Authors", text: $paper.authors, axis: .vertical)
            TextField("Year", text: $paper.year)

            Picker("Status", selection: $paper.status) {
                ForEach(ReadingStatus.allCases) { status in
                    Text(status.rawValue).tag(status)
                }
            }

            Section("Abstract") {
                TextEditor(text: $paper.abstract)
                    .frame(minHeight: 140)
            }

            Section("File") {
                Text(paper.filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
            Text("\(aiMode) mode")
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AIResultView: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(bodyText)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
