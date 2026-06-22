# Research Paper Reader

A local-first, AI-assisted research paper reader for macOS. Import PDFs, read deeply with color-coded highlights and typed notes, search every word across your library, and use on-device AI to summarize, extract claims, or explain selected passages — all without uploading your papers to a cloud service.

Built with SwiftUI and PDFKit. Designed for graduate students, researchers, and anyone who reads dense technical literature.

## Features

- **Selection screen** — A visual card-based browser shows papers as rich cards with title, authors, abstract preview, reading status badge, import date, note count, year, venue, and tags. Sort by Recent, Title, Author, or Year with animated reordering.
- **Sidebar paper list** — The library sidebar shows a filterable, sortable list of all papers with status color dot, title, authors, and note count. Sort by Recent, Title, Author, or Year. Filter by reading status.
- **PDF import** — Drag-and-drop from Finder onto the card grid, or open-panel import (`⌘I` / `⌘O`); metadata extracted from PDF attributes and enriched via CrossRef/arXiv lookups, with AI-powered fallback extraction.
- **Full-text search** — Every word in every paper is extracted on import. Search titles, authors, tags, notes, and PDF body text with 300ms debounced full-text matching.
- **Collections & smart folders** — Organize papers into reusable nested collections, or create live folders from compound metadata, status, tag, author, venue, year, document-type, and full-text rules.
- **Citation library** — Import BibTeX or RIS from pasted text or files, merge DOI/title duplicates, generate stable citation keys, and copy or save the complete library as BibTeX or RIS. Duplicate PDF imports are merged without discarding existing notes or tags.
- **Reader** — PDFKit-based reader with continuous scroll, zoom controls (toolbar + trackpad), find within paper (`⌘F`) with native highlights and chevron navigation, go-to-page dialog (`⌘G`), collapsible inspector, and keyboard navigation.
- **Section-aware navigation** — On import, the app detects common academic paper sections (Abstract, Introduction, Method, Results, Conclusion, etc.) using numbered-header-aware parsing. Click a section in the sidebar outline to jump the PDF to that page.
- **Color-coded highlights** — Annotations render as native PDFKit highlights directly on the page. Color per kind: yellow (highlight), orange (claim), green (evidence), blue (method), red (limitation), purple (question), gray (definition). Hovering over a text highlight for 2 seconds opens a floating popover displaying its category and body content.
- **PDF Area Notes (Image Crop Annotation)** — Annotate charts, tables, equations, or visual figures directly. Activate the green dashed-square Area Note tool, then drag across the PDF; a live marquee dims the surrounding page and shows a blue crop border with corner handles. Releasing the drag captures the region as a high-resolution image thumbnail associated with your note. Saved area notes display as colored rectangular highlights with transparent fills, and clicking one automatically centers the PDF on its coordinates.
- **Typed notes** — Save structured notes anchored to selected text or visual areas. Jump to any note's page by clicking it in the inspector's Notes list, and delete individual notes using the trash icon. Type Picker shows a live color swatch of the selected highlight kind. Export to Markdown. Shortcut: `⌘N`.
- **On-device AI** — Summarize papers (`⌘S`), extract claims/methods/evidence/limitations, or explain selected passages. Results shown in collapsible Summary and Explanation sections. All processing stays local — no API keys, no cloud calls, no data leaving your Mac.
- **Local semantic search & grounded library chat** — Search across papers and notes with Apple's on-device sentence embeddings and a lexical fallback. Ask a library-wide question and receive an extractive answer whose evidence cards link back to source pages.
- **Cross-paper evidence & writing workspaces** — Build editable comparison tables with source-anchored, verifiable cells, export them as Markdown or CSV, then generate a multi-paper literature-review outline and continue writing beside its citation keys.
- **Citation graph, discovery & alerts** — Parse local reference lists into a visual graph, search CrossRef without uploading PDF content, save discovered citations, and monitor topics, authors, or new works citing a DOI. Citation alerts use OpenAlex and refresh stale enabled alerts when opened.
- **Metadata enrichment & editing** — On import, papers are enriched via CrossRef (DOI lookups), arXiv API (arXiv ID lookups), and heuristic/AI text extraction. Correct details (title, authors, year, venue, abstract) and manage tags manually via the details editor. DOI, arXiv ID, and venue are shown on paper cards.
- **Privacy controls** — AI mode selector (Private Local, Balanced, Best AI, Custom) with clear status text.

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

1. **Import papers** — Click `+` in the toolbar, press `⌘O` / `⌘I`, or drag PDFs from Finder onto the card grid.
2. **Browse & filter** — The detail pane shows papers as visual cards. Press `⌘F` to focus the sidebar search and filter by title, author, or any text in the PDF body. Use the status filter below the search bar to narrow by reading status (Unread, Reading, Read, etc.).
3. **Sort** — Use the segmented sort picker at the top of the card grid to order by Recent (default), Title, Author, or Year. Cards animate into their new positions.
4. **Read** — Click any card to open the reader with an animated slide transition. The PDF fills the left pane (collapsible with the sidebar toolbar button); the right pane has two tabs:
   - **Notes** — Select text in the PDF, choose a highlight type (color swatch shown), add your notes, and save. For a visual area, activate the green dashed-square Area Note toolbar button and drag over the PDF; the blue marquee appears during the drag. Existing notes render as colored highlights on the PDF. Shortcut: `⌘N`.
   - **AI** — Click "Summarize" (`⌘S`) for a local heuristic summary, or use "Extract" to find claims/methods/evidence/limitations, or select text and click "Explain Selection". Results appear in collapsible Summary and Explanation sections.
5. **Navigate** — Use the toolbar zoom controls (`+`/`-`), the find bar (`⌘F`), or go-to-page dialog (`⌘G`). Click a section in the sidebar's paper list to jump the PDF to that page.
6. **Export** — Click "Export" in the AI tab to save notes and AI summaries as Markdown.
7. **Research across papers** — Open **Research Hub** from the toolbar to manage collections and citations, create evidence tables and synthesis workspaces, run semantic search or grounded chat, inspect the citation graph, discover papers, and manage research alerts. To export a comparison, open an evidence table and choose **Table Actions → Export Markdown…** (or **Export CSV…**).

## Architecture

```
Sources/ResearchPaperReader/
  ResearchPaperReaderApp.swift   — App entry, ⌘O/⌘I shortcuts, Settings scene
  ContentView.swift              — NavigationSplitView: sidebar (filter, sort, paper list) + animated detail
  SelectionScreen.swift          — Card-based paper browser with sort (Recent/Title/Author/Year) + PaperCard
  PaperStore.swift               — @MainActor ObservableObject, JSON persistence with debounced save
  Models.swift                   — Paper, PaperSection, PaperNote, ReadingStatus, HighlightKind + sort/filter extensions
  PDFReaderView.swift            — NSViewRepresentable wrapping PDFKit.PDFView, highlights, zoom, page nav
  ReaderWorkspace.swift          — HSplitView: PDF reader + inspector (Notes / AI), find bar, collapsible sections
  LocalPaperAI.swift             — Stateless enum, heuristic text + Core ML + Foundation Models router
  MetadataService.swift          — CrossRef/arXiv API lookups, AI metadata extraction, enrichment pipeline
  ResearchModels.swift           — Collections, citations, evidence, synthesis, semantic, graph, discovery, and alert models
  ResearchServices.swift         — Citation parsing/export, semantic retrieval, evidence synthesis, graph extraction, CrossRef/OpenAlex discovery
  EvidenceWorkspaceView.swift    — Evidence-table comparison, editing, verification, and Markdown/CSV export
  ResearchHubView.swift          — Integrated library, evidence, search/chat, synthesis, graph, discovery, and alerts workspace
  SettingsView.swift             — AI mode, provider, and privacy toggles
  WindowBoundsEnforcer.swift     — NSViewRepresentable enforcing minimum window size
```

### Performance

- **Debounced persistence** — Library saves batch rapid mutations (highlighting, status changes) into a single disk write at most once per second. Destructive operations (import, delete) flush immediately.
- **Debounced full-text search** — Metadata search runs instantly on each keystroke; full-text body search waits for a 300ms typing pause.
- **Shared regex compilation** — BibTeX, RIS, DOI, and reference-marker patterns are compiled once at module load instead of on each parse call.
- **Normalized DOI deduplication** — A single shared `String.normalizedDOI` extension eliminates redundant inline normalization across citation, metadata, and discovery services.
- **Linear page-text extraction** — Semantic search chunk building uses incremental `String.Index` traversal instead of per-page O(n) offsets, keeping extraction O(n) for the full document.
- **Duplicate switch elimination** — `ReadingStatus.color` removes two identical 14-line switch statements across view files.

### Design principles

- **Local-first** — The app works fully offline. Papers, notes, and AI processing stay on your Mac unless you explicitly enable cloud features.
- **AI optional** — You can read, highlight, and take notes without any AI. The heuristic AI adds leverage without requiring API keys.
- **Traceable intelligence** — AI outputs always cite their source passage. You can inspect what the extraction is based on.
- **Reading quality first** — The PDF viewer and annotation system are the core surface; AI is a sidebar tool.

## Roadmap

| Phase | Focus | Status |
|-------|-------|--------|
| 1 | Foundation (app shell, PDF rendering, library, selection screen) | ✅ Done |
| 2 | Annotations & notes (highlights, typed notes, Markdown export) | ✅ Done |
| 3 | Processing pipeline (text extraction, section detection, full-text search) | ✅ Done |
| 4 | Local AI & retrieval (heuristic summarization, extraction, explain selection) | ✅ Done |
| 5 | Metadata enrichment (CrossRef, arXiv, heuristic/AI metadata extraction) | ✅ Done |
| 6 | Preview features (find within paper, go-to-page, zoom controls) | ✅ Done |
| 7 | Research library (collections, smart folders, citations, duplicate merging) | ✅ Done |
| 8 | Cross-paper research (evidence tables, semantic search/chat, synthesis workspace) | ✅ Done |
| 9 | Discovery (citation graph, CrossRef discovery, topic/author/citation alerts) | ✅ Done |
| 10 | Cloud & BYOK (secure model router, provider credentials, privacy gates) | 🔲 Not started |
| 11 | Sync (iCloud metadata sync, multi-device) | 🔲 Not started |

See [`research-paper-reader-design.md`](research-paper-reader-design.md) for the full product specification.

See [`PRODUCT_DEVELOPMENT_PATH.md`](PRODUCT_DEVELOPMENT_PATH.md) for the living product mind map, competitive feature additions, dependency order, and reconciled implementation backlog. Feature completion should be checked against both that document and [`CHANGELOG.md`](CHANGELOG.md).

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
