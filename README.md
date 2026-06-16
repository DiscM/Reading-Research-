# Research Paper Reader

A local-first, AI-assisted research paper reader for macOS. Import PDFs, read deeply with color-coded highlights and typed notes, search every word across your library, and use on-device AI to summarize, extract claims, or explain selected passages — all without uploading your papers to a cloud service.

Built with SwiftUI and PDFKit. Designed for graduate students, researchers, and anyone who reads dense technical literature.

## Features

- **PDF import** — Drag-and-drop or open-panel import; metadata extracted from PDF attributes automatically.
- **Paper library** — Sort, search, and filter by reading status, tags, or full-text content.
- **Full-text search** — Every word in every paper is indexed on import. Search titles, authors, tags, notes, and PDF body text with 300ms debounced full-text matching.
- **Reader** — PDFKit-based reader with continuous scroll, zoom, and keyboard navigation.
- **Color-coded highlights** — Annotations render as native PDFKit highlights directly on the page. Color per kind: yellow (highlight), orange (claim), green (evidence), blue (method), red (limitation), purple (question), gray (definition).
- **Typed notes** — Save structured notes anchored to selected text and page number. Export to Markdown.
- **On-device AI** — Summarize papers, extract claims/methods/evidence/limitations, or explain selected passages. All processing stays local using heuristic text extraction — no API keys, no cloud calls, no data leaving your Mac.
- **Debounced persistence** — Library changes write to disk at most once per second, batching rapid mutations (highlighting, status changes) into a single save.
- **Privacy controls** — AI mode selector (Private Local, Balanced, Best AI, Custom) with clear labels showing when content stays on-device.

## Quick Start

### Download

Build a double-clickable `.app` bundle:

```sh
./scripts/build-app.sh
open dist/Research\ Paper\ Reader.app
```

Or build and launch in one step:

```sh
./scripts/build-app.sh --open
```

The script produces a **universal binary** (`arm64` + `x86_64`) with a generated app icon, `Info.plist`, and ad-hoc code signature in `dist/Research Paper Reader.app`. Share it as a zip or DMG.

> [!NOTE]
> Because the app is ad-hoc signed (not notarized), first-time users on another Mac should right-click → **Open**, or run:
> ```sh
> xattr -dr com.apple.quarantine "Research Paper Reader.app"
> ```

### Run from source

Requires macOS 15+ and Xcode 16+.

```sh
swift run
```

Or open in Xcode:

```sh
open Package.swift
```

## Usage

1. **Import papers** — Click `+` in the toolbar or press `⌘O`. Select one or more PDFs.
2. **Browse library** — The sidebar shows your papers. Use the search bar to filter by title, author, tags, notes, or any text in the PDF body.
3. **Read** — Select a paper to open the reader. The PDF fills the left pane; the right pane has three tabs:
   - **Notes** — Select text in the PDF, choose a highlight type, add your notes, and save. Existing notes render as colored highlights on the PDF.
   - **AI** — Click "Summarize" for a local heuristic summary, use "Extract" to find claims/methods/evidence/limitations, or select text and click "Explain Selection" to see surrounding context.
   - **Details** — Edit title, authors, year, reading status, and abstract.
4. **Export** — Click "Export" in the AI tab to save notes and AI summaries as Markdown.

## Architecture

```
Sources/ResearchPaperReader/
  ResearchPaperReaderApp.swift   — App entry, keyboard shortcut, Settings scene
  ContentView.swift              — NavigationSplitView: library sidebar + detail
  PaperStore.swift               — @MainActor ObservableObject, JSON persistence with debounced save
  Models.swift                   — Paper, PaperNote, ReadingStatus, HighlightKind + color map
  PDFReaderView.swift            — NSViewRepresentable wrapping PDFKit.PDFView, highlight rendering
  ReaderWorkspace.swift          — HSplitView: PDF reader + inspector panel (Notes / AI / Details)
  LocalPaperAI.swift             — Stateless enum, heuristic text extraction (no external deps)
  SettingsView.swift             — AI mode, provider, and privacy toggles
```

### Design principles

- **Local-first** — The app works fully offline. Papers, notes, and AI processing stay on your Mac unless you explicitly enable cloud features.
- **AI optional** — You can read, highlight, and take notes without any AI. The heuristic AI adds leverage without requiring API keys.
- **Traceable intelligence** — AI outputs always cite their source passage. You can inspect what the extraction is based on.
- **Reading quality first** — The PDF viewer and annotation system are the core surface; AI is a sidebar tool.

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | Foundation (app shell, PDF rendering, library) | ✅ Done |
| 2 | Annotations & notes (highlights, typed notes, Markdown export) | ✅ Done |
| 3 | Processing pipeline (text extraction, section detection, full-text search) | ✅ Partial |
| 4 | Local AI & retrieval (heuristic summarization, extraction, explain selection) | ✅ MVP |
| 5 | Cloud & BYOK (model router, provider settings, privacy gates) | 🔲 Not started |
| 6 | Sync (iCloud metadata sync, multi-device) | 🔲 Not started |
| 7 | Literature review workspace (projects, comparisons, synthesis) | 🔲 Not started |
| 8 | Collaboration (team libraries, shared annotations) | 🔲 Not started |

See [`research-paper-reader-design.md`](research-paper-reader-design.md) for the full product specification.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 |
| UI | SwiftUI |
| PDF rendering | PDFKit (via NSViewRepresentable) |
| Persistence | JSON file (debounced, in Application Support) |
| AI (heuristic) | Native text extraction + keyword matching |
| Minimum OS | macOS 15 Sequoia |
| Architectures | arm64 + x86_64 (universal binary) |

## License

MIT
