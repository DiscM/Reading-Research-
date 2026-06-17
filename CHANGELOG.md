# Changelog

## v0.7.0 — 2026-06-16

### Added

- **Collapsible AI sections** — The AI tab now has two expandable/collapsible sub-tabs: "Summary" and "Explanation". Each uses a custom `CollapsibleSection` component with a full-row clickable header, animated rotating chevron, and rounded background. Summary auto-expands on generate; Explanation groups both Extraction and Selection Context results. Placeholder text shown when empty.
- **Note type color swatch** — A 14pt colored circle (filled with the selected highlight kind's color) appears next to the "Type" Picker in the Notes tab, updating live as the selection changes.
- **Shared filter/sort extension** — `Array<Paper>.filtered(searchText:debouncedSearch:status:)` and `.sorted(by:)` added to `Models.swift`, consolidating the duplicate filter/sort logic that previously lived in both `ContentView` and `SelectionScreen`.

### Fixed

- **NotificationCenter observer leak** — `PDFReaderView.Coordinator` now calls `NotificationCenter.default.removeObserver(self)` in its `deinit`, preventing dead coordinators from accumulating on every paper switch (was causing 41 GB memory growth).
- **Find bar performance** — Added `guard newValue.count >= 2` to prevent expensive `sentenceCandidates` split/filter on the full paper text until the user has typed at least 2 characters.

### Removed

- **Details tab** — Removed the reader inspector's Details tab. The inspector now shows only Notes and AI.
- **Dead code** — Removed unused `addMatch()` function from `LocalPaperAI.sections(from:)`, unused `zoomIn()`/`zoomOut()`/`zoomToFit()` methods from `PDFReaderView.Coordinator`, unused empty-state text block from `ReaderWorkspace.aiPanel`, and unused `import AppKit` from `ContentView.swift`.

## v0.6.1 — 2026-06-16

### Added

- **Sidebar paper list with sort** — The library sidebar now shows a filterable, sortable list of all papers. Each row displays a status color dot, title (2-line), authors, and note count. Sort by Recent, Title, Author, or Year via a compact Picker next to the status filter.
- **Back button in toolbar** — When a paper is open in the reader, a "Back to Library" button (chevron.left) appears in the toolbar next to the import button. Clicking it returns to the selection screen.

### Removed

- **Sections panel** — Removed the per-paper section outline ("Sections" list with page navigation and section text sheet) from the sidebar. Sections remain available in the reader's Outline tab within the inspector.

### Changed

- `ContentView.swift` — Rewrote sidebar: removed `sidebarSection` state, sections list, and section sheet. Added `sidebarSort` state and a `sidebarPapers` computed property mirroring the filter/sort logic. Replaced empty space with a `List(selection:)` of `SidebarPaperRow` views. Added back button to toolbar. Removed "Now Reading" section (paper is now visible as selected in the list instead).
- `SidebarPaperRow` — New private struct showing status dot, title, authors, and note count for each paper in the sidebar list.

### Added

- **Numbered-header section detection** — The section parser now prioritizes numbered headers (`1. Introduction`, `2.1 Background`, `III. Methodology`, `A. Setup`). A two-pass regex approach strips the number prefix and matches the content against known keywords. Unnumbered headers are matched secondarily. This produces more accurate outlines with fewer false positives.
- **Page-mapped sections** — Sections now carry a `page: Int?` field pinpointing which PDF page the section starts on. `Paper.allTextPageOffsets` tracks character offsets per page during text extraction; the section parser maps each detected header offset back to a page.
- **Sidebar section outline** — When a paper is open, the sidebar shows a "Sections" panel below "Now Reading". Each row displays: page number (e.g. "p.3"), section kind badge, title, and chevron. Clicking a section both opens its text in a sheet AND navigates the PDF reader to that page.
- **PDF page navigation** — `PDFReaderView` accepts a new `@Binding var navigateToPage: Int?`. When set, the PDF scrolls to and centers on the specified page. `ReaderWorkspace` threads this binding from `ContentView` through to `PDFReaderView`.

### Changed

- `LocalPaperAI.sections(from:text:)` → `sections(from:text:pageOffsets:)` — Now accepts page offsets for page mapping. Rewritten with numbered-header regex prioritization.
- `PaperStore.extractAllText(from:)` returns a `(text: String, offsets: [Int])` tuple. Page offsets stored in `Paper.allTextPageOffsets`.
- `PaperSection` — added `page: Int?` property.
- `ContentView.swift` — Added `navigateToPage` state. Sidebar section buttons set both `navigateToPage` (for PDF scroll) and `sidebarSection` (for text sheet). Added page number ("p.3") in sidebar rows and sheet header.
- `ReaderWorkspace` — Added `@Binding var navigateToPage: Int?`, passed through to `PDFReaderView`.
- `PDFReaderView` — Added `@Binding var navigateToPage: Int?` and `lastNavigatedPage` tracking. On change, calls `pdfView.go(to:)` for the target page.

## v0.5.0 — 2026-06-16

### Added

- **Bulk ingestion with metadata enrichment** — Importing PDFs now triggers an automatic enrichment pipeline that fetches metadata from publication databases and uses on-device AI to improve incomplete data.
- **CrossRef DOI lookup** — On import, the app scans the first page for DOI patterns (`10.xxxx/...`). When found, it queries the CrossRef API (free, no key required) to fetch title, authors, year, abstract, and venue. Matched results overwrite placeholder metadata.
- **arXiv API lookup** — The first page is also scanned for arXiv IDs (`arXiv:xxxx.xxxxx`). When found, the arXiv API provides title, authors, year, and abstract. `paper.venue` is set to "arXiv".
- **Heuristic metadata extraction** — When no DOI or arXiv ID is found, the app attempts to extract title (first non-empty line), authors (second line), year (first four-digit year in first 5 lines), and abstract from the first page text using the existing `abstractCandidate` heuristic.
- **Apple Foundation Model metadata extraction (macOS 26+)** — On future OS versions, the system language model is used to extract structured metadata (title, authors, year, abstract, venue) from the first page via a JSON-prompted generation. Falls back gracefully to the heuristic on older OS versions.
- **Enrichment progress in sidebar** — An animated spinner with "Enriching N..." text appears in the sidebar during the enrichment phase after import. Fades in/out with opacity transition.
- **Enrichment indicators on cards** — Paper cards now show DOI ("DOI" badge in blue) and arXiv ("arXiv" badge in orange) when available. Venue appears as a `building.2` label in the bottom metadata bar.
- **Enrichment status in Details tab** — Read-only fields for DOI, arXiv ID, and Venue appear in the reader's Details tab. An orange warning icon with "Metadata enrichment unavailable" text shows when enrichment is attempted but fails.
- **New data model fields** — `Paper.doi: String`, `Paper.arxivId: String`, `Paper.venue: String`, `Paper.enrichmentFailed: Bool`.

### Removed

- **Library error alert** — Removed the modal `.alert("Library Error", ...)` dialog from ContentView. Errors now appear as a transient red text banner at the bottom of the sidebar that auto-dismisses after 4 seconds. Non-blocking and non-intrusive.

### Added (files)

- `MetadataService.swift` — 215-line service struct with CrossRef/arXiv HTTP lookups, heuristic + Foundation Model text extraction, and the top-level `enrich(_:)` pipeline.

### Changed

- `PaperStore.importPDFs` — Now runs an asynchronous enrichment loop after importing all PDFs. Each paper is passed through `MetadataService.enrich()` in sequence. Progress tracked via `isImporting` and `enrichmentCount` published properties.
- `PaperStore.extractMetadata` — Extended to also extract DOI and arXiv ID from the first page during the initial import pass, before enrichment runs.
- `PaperCard` bottom bar — Added venue icon/label, DOI capsule badge, and arXiv capsule badge.
- `ReaderWorkspace` Details tab — Added read-only venue, DOI, arXiv ID fields, and enrichment-failed warning.
- `ContentView` sidebar — Added import progress HStack with `ProgressView` spinner and enrichment count.

## v0.4.0 — 2026-06-16

### Added

- **Selection screen** — A new visual card-based paper browser replaces the direct-open-to-reader flow. The detail pane shows papers as rich cards with title, authors, abstract preview, reading status badge (color-coded), relative import date, note count, year, and tags.
- **Sort controls** — A segmented picker at the top of the selection screen offers four sort orders: **Recent** (default, by `importedAt` descending), Title, Author, and Year. Changing the sort animates the card list with a spring transition.
- **Sidebar redesign** — The sidebar is now a compact control panel: library title, search field, status filter picker, and a "Now Reading" section showing the currently open paper with a close button. Paper count shown at the bottom.
- **Animated transitions** — Opening a paper uses an asymmetric slide+opacity transition (card grid slides out left, reader slides in from right). Closing reverses. Cards animate in with scale+opacity on initial appearance and smoothly reorder when filter/sort changes.
- **Visual flare** — Paper cards have rounded corners (12pt), subtle shadow, a colored status strip on the leading edge, and a status badge capsule. Empty and no-match states use SF Symbol effects (bounce, pulse). Status colors: unread=gray, skimmed=blue, reading=green, read=indigo, cited=purple, rejected=red, archived=secondary.

### Changed

- `ContentView.swift` — completely restructured. Sidebar extracted into its own `@ViewBuilder`; detail switches between `SelectionScreen` and `ReaderWorkspace` with animated transitions. Removed `PaperList`, `PaperRow`, and `EmptyLibraryView` private structs (replaced by `SelectionScreen`).
- `SelectionScreen.swift` — new file containing `SelectionScreen`, `PaperCard`, and `SortOrder` enum. Filtering, sorting, and card display logic lives here.
- Drag-and-drop import — moved from sidebar `PaperList` to `SelectionScreen` (and retained on the detail view).
- Toolbar — removed the per-paper status Picker (status is now visible on each card and in the reader's Details tab).

### Fixed

- **⌘I keyboard shortcut** — Now wired as a hidden button behind the toolbar import button. Both `⌘O` and `⌘I` open the import panel.

## v0.3.0 — 2026-06-16

### Added

- **Section detection & Outline tab** — On import, the app now parses `allText` for common academic paper section headers (Abstract, Introduction, Related Work, Method, Experiments, Results, Discussion, Conclusion, References, Appendix). The detected sections appear in a new **Outline** tab in the reader inspector. Clicking any section opens a sheet showing its full text.
- **Drag-and-drop import** — PDFs can be dropped from Finder directly onto the paper library sidebar. Accepts single or multiple files; non-PDF files are silently ignored. Uses `NSPasteboard`-based reading for synchronous handling.
- **Keyboard shortcuts** — `⌘F` focuses the search field in the library sidebar. `⌘N` saves the current note in the reader. `⌘S` generates the paper summary. `⌘I` opens the import panel (standard menu item).
- **New data models** — `SectionKind` enum (12 cases mapping to common paper sections) and `PaperSection` struct with id, kind, title, text, and order. `Paper.sections` persists extracted sections alongside the library.

### Changed

- `PaperStore.importPDFs` — now calls `LocalPaperAI.sections(from:)` during import and stores result in `paper.sections`.
- `ContentView` sidebar — extracted `PaperList` helper view to manage list, onDelete, and drag-and-drop independently, reducing type-checking complexity in the main view body.

### Fixed

- **⌘I keyboard shortcut** — Now wired as a hidden button behind the toolbar import button. Both `⌘O` and `⌘I` open the import panel.
- **READNE accuracy** — Removed unimplemented "Sort" claim; corrected "filter by reading status" to reference the actual status filter Picker added in this release; updated tab count from 3 to 4 (added Outline tab).
- **Library status filter** — Added `ReadingStatus?` Picker to the library header. Papers can now be filtered by reading status (All, Unread, Skimmed, Reading, Read, Cited, Rejected, Archived).

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
