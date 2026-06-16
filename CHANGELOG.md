# Changelog

## v0.3.0 — 2026-06-16

### Added

- **Section detection & Outline tab** — On import, the app now parses `allText` for common academic paper section headers (Abstract, Introduction, Related Work, Method, Experiments, Results, Discussion, Conclusion, References, Appendix). The detected sections appear in a new **Outline** tab in the reader inspector. Clicking any section opens a sheet showing its full text.
- **Drag-and-drop import** — PDFs can be dropped from Finder directly onto the paper library sidebar. Accepts single or multiple files; non-PDF files are silently ignored. Uses `NSPasteboard`-based reading for synchronous handling.
- **Keyboard shortcuts** — `⌘F` focuses the search field in the library sidebar. `⌘N` saves the current note in the reader. `⌘S` generates the paper summary. `⌘I` opens the import panel (standard menu item).
- **New data models** — `SectionKind` enum (12 cases mapping to common paper sections) and `PaperSection` struct with id, kind, title, text, and order. `Paper.sections` persists extracted sections alongside the library.

### Changed

- `PaperStore.importPDFs` — now calls `LocalPaperAI.sections(from:)` during import and stores result in `paper.sections`.
- `ContentView` sidebar — extracted `PaperList` helper view to manage list, onDelete, and drag-and-drop independently, reducing type-checking complexity in the main view body.

## v0.2.0 — 2026-06-16

### Added

- **Highlight rendering** — Notes now render as native PDFKit highlight annotations directly on the PDF page. Color-coded per highlight kind (yellow, orange, green, blue, red, purple, gray). Annotations are tagged and re-synced only when notes change.
- **Selected-text AI explanation** — New "Explain Selection" button in the AI panel. Finds the selected passage in the paper's full text and displays surrounding context with blockquote formatting.
- **Full-text PDF search** — Library search now searches the complete extracted text of every paper, not just titles, authors, tags, and notes.
- **Debounced persistence** — Library saves are debounced to 1 second, batching rapid mutations (highlighting, status changes) into a single disk write. Destructive operations (import, delete) flush immediately.
- **Debounced full-text search** — Metadata search (title, authors, tags, notes) runs instantly on each keystroke. Full-text body search waits for a 300ms typing pause.
- **Cached text extraction** — AI tasks read from `Paper.allText` (cached in memory at import time) instead of opening the PDF file from disk on every invocation. Eliminates redundant file I/O from summary, extraction, and explanation calls.
- **Universal binary build** — `scripts/build-app.sh` builds and merges `arm64` + `x86_64` slices into a single universal `.app` bundle.
- **App icon** — Custom CoreGraphics-generated icon (gradient squircle + paper sheet + AI sparkle) bundled as `AppIcon.icns`.
- **Info.plist** — Proper bundle metadata: bundle ID `ai.localfirst.researchpaperreader`, version 1.0.0, macOS 15.0 minimum, productivity category, PDF document-type association.
- **HighlightKind.color** — Each highlight kind exposes an `NSColor` for consistent annotation rendering.

### Changed

- `LocalPaperAI.extractedText(from:maxPages:)` removed. Both `summary` and `extraction` now use `paper.allText` directly with character-count limits (15K / 30K). Removed `PDFKit` import from `LocalPaperAI.swift`.
- `Paper.allText` — new persisted field populated during `importPDFs`. Stores all PDF page text joined by newlines.
- `scripts/build-app.sh` — builds each architecture in a separate `swift build` invocation (avoids toolchain prebuilt-module cache issues), then `lipo` merges into a universal binary.
- `ContentView.filteredPapers` — splits into metadata search (instant) and full-text search (debounced).

### Fixed

- Latex/formula artifacts no longer read from PDF on every AI action — cached text eliminates all per-call PDF I/O.

## v0.1.0 — 2026-06-16

### Added

- **Paper library** — Import PDFs via open panel (`⌘O`), with automatic metadata extraction from PDF attributes (title, author). Deduplicated filename storage in `Application Support/ResearchPaperReader/Papers/`.
- **PDF reader** — PDFKit-based reader with continuous scroll, zoom, fit-to-width, and keyboard navigation. Text selection tracked via `PDFViewSelectionChanged` notifications.
- **Paper model** — `Paper`, `PaperNote`, `ReadingStatus` (unread/skimmed/reading/read/cited/rejected/archived), `HighlightKind` (highlight/claim/evidence/method/limitation/question/definition).
- **Typed notes** — Save structured notes with kind, quote, page number, and body text. Animated list display in the inspector panel.
- **Markdown export** — Export notes, AI summary, and metadata as Markdown via save panel.
- **Local heuristic AI** — `LocalPaperAI` implements on-device text extraction with keyword-matched extraction (claims, evidence, methods, limitations) and sentence-ranking summarization (top 4 sentences + method signal). No API keys or network access required.
- **Paper library search** — Filter papers by title, authors, tags, and note body/quote.
- **JSON persistence** — Library stored as `library.json` in `Application Support/ResearchPaperReader/` with pretty-printed, sorted-key, ISO8601-date encoding.
- **Settings** — AI mode picker (Private Local, Balanced, Best AI, Custom), provider selector, cloud processing toggle, BYOK endpoint field. Stored in `@AppStorage`.
- **App entry point** — `@main` SwiftUI App with `WindowGroup`, `CommandGroup` (`⌘O`), and `Settings` scene.
- **Design document** — `research-paper-reader-design.md` — comprehensive 1118-line product specification covering vision, users, architecture, tech stack, modules (library, reader, annotations, AI, pipeline, search, literature review), data model, privacy, sync, monetization, MVP scope, implementation roadmap (8 phases), risks, and success metrics.
- **README** — Setup and usage documentation.

### Build & Distribution

- Swift Package Manager project targeting macOS 15.
- Single-thin-binary build via `swift build -c release`.
- Manual `cp` to assemble an ad-hoc-signed `.app` bundle with basic `PkgInfo`.
