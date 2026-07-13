# Canopy v1 Plan

## Product boundary

Canopy v1 is a Mac App Store application for macOS 15 or later. It is fully offline and makes no network requests. The launch experience always opens the library rather than reopening a document.

The complete v1 journey is:

1. Add one or more PDFs from an open panel or drag and drop.
2. Reference the originals by default or explicitly copy the import batch into Canopy.
3. Browse recent and alphabetical library sections and search title, authors, year, and notes.
4. Open a PDF in a continuous vertical reader.
5. Select text, choose one of five colors, and optionally attach a note.
6. Close and relaunch Canopy, then recover the library, annotations, and exact reading position.

Everything outside that journey belongs in the deferred-feature catalog.

## Non-negotiable rules

- The prototype is archival reference, never a source dependency.
- No old library migration is provided.
- PDF bytes never live in SwiftData.
- Referenced sources are read-only; Canopy never modifies them.
- Managed PDFs are immutable app-owned copies.
- Highlights and notes are separate database records, not PDF mutations.
- SwiftData is accessed through repositories rather than directly throughout the UI.
- Critical discrete actions save explicitly and participate in native Undo.
- Every persisted schema is versioned from its first release.
- Research content, filenames, highlights, and notes never enter telemetry.

## Storage model

### Referenced PDFs

Canopy stores an app-scoped security-scoped bookmark, source attributes, and a SHA-256 content fingerprint. The bookmark supplies persistent sandbox access; the fingerprint establishes document identity.

On access, Canopy compares file size and modification date. If either changed, it streams the file through SHA-256 again. A digest mismatch blocks annotation display until the user locates the original file or explicitly resolves the change. Missing, offline, permission-denied, modified, and damaged sources must be distinct states.

### Managed copies

When explicitly selected during import, Canopy copies the PDF into its Application Support container. The import choice applies to the batch and cannot be changed afterward in v1. Removing the paper also removes its managed copy after confirmation.

### SwiftData

The versioned SwiftData schema stores:

- Paper identity and editable title, authors, and year
- Storage mode and bookmark or managed relative path
- SHA-256 fingerprint and cached source attributes
- Added/opened timestamps and reading state
- Highlight anchors, colors, optional notes, and timestamps

The first schema is deliberately small. Future concepts do not get placeholder columns or speculative relationships.

## Annotation anchor

Each highlight stores:

- Zero-based page index
- PDF selection quadrilaterals in page coordinates
- Exact selected text
- Short text context before and after the selection
- One non-semantic color: yellow, green, blue, pink, or purple
- Optional plain-text note

Geometry provides exact rendering. Text and context validate the anchor and reserve a path for future re-anchoring. Externally changed PDFs do not receive automatic re-anchoring in v1.

Color controls always include names, selection borders, and checkmarks. Annotation rows remain understandable without distinguishing hue, and Canopy respects increased-contrast and differentiate-without-color preferences.

## Window and state ownership

The primary `WindowGroup` contains a stable sidebar-detail layout with a native inspector:

- Sidebar: recent history, full library, basic sorting, and search
- Detail: PDFKit reader and reader toolbar
- Inspector: one page-ordered annotation list with quotations and inline note editing

Paper metadata is managed in a dedicated **Paper Info** sheet opened from an info button in the reader toolbar, the Paper row's **Get Info** context-menu command, or `⌘I`. The sheet contains editable bibliographic fields and Author Credits, field provenance, source status and location, and Reparse Metadata; it does not occupy another column. All edits and approved reparse replacements remain staged until the user chooses Save; Cancel discards the entire transaction. Author Credits use ordered rows with add, remove, and drag-to-reorder controls; each exposes a display name and permits correction of the derived family name when expanded.

Window selection and expansion are scene-scoped. Window geometry and column widths are app preferences. Each paper stores page, viewport, zoom, and inspector visibility. The reader saves navigation state with a debounce; highlight creation and deletion save transactionally; note typing saves after a short debounce and on focus loss.

## Library behavior

- Launch with no selected document.
- Show recently opened papers above the remaining alphabetical library.
- “Clear Recent History” removes only opened timestamps.
- Full-library sorting supports Title and Date Added.
- Search ranks title before authors/year and note text.
- Exact duplicate content, detected by SHA-256, maps to one paper record.
- Scanned PDFs are readable but have no text highlighting, document find, or title inference when text is unavailable.
- Password-protected and damaged PDFs fail import with a specific explanation.

## Metadata behavior

Canopy reads embedded PDF metadata locally and validates every field before assignment. Identifier-shaped titles—including arXiv IDs, DOIs, URLs, UUIDs, filenames, and generic export labels—are rejected. If the title is unusable, deterministic first-page layout analysis attempts to locate the prominent title block. Low-confidence results fall back to a cleaned filename. Title is the sole required bibliographic field; Paper Info cannot save it empty. Author Credits, year, DOI, and arXiv ID are optional. Each retained field records its current Metadata Provenance. Manual edits replace earlier inferred values. Reparse Metadata presents field-by-field replacements for approval rather than overwriting immediately. DOI and arXiv ID may be empty, but malformed nonempty identifiers block Paper Info from saving and never participate in duplicate matching. Publication year may be blank or a four-digit value from 1000 through the next calendar year; invalid values remain visible for correction and block Save.

## Reader behavior

- Continuous vertical scrolling
- Direct page entry and page count
- Zoom in/out, Fit Width, and Actual Size
- Native in-document find with next/previous result and count
- Selection-adjacent five-color highlight palette
- Optional “Add Note” path into the inspector
- No outline, thumbnail rail, OCR, page-area annotation, or semantic annotation categories

## Architecture

`Canopy` is the application and SwiftUI composition target. `CanopyCore` is a local Swift package containing independently testable domain and infrastructure code.

```text
Canopy app target
  App/                 scenes and commands
  Stores/              scene-scoped workflows, annotation session, and Undo coordination
  Views/               library, reader, and inspector composition
  Resources/           entitlements and assets

CanopyCore package
  Models/              versioned persisted and value models
  Persistence/         container creation, migrations, repositories
  Services/            bookmarks, fingerprints, metadata, PDF lifecycle
```

PDFKit adapters remain in the app/platform layer. Core logic accepts value representations of page geometry so it can be tested without a live `PDFView`.

## Implementation slices

Status labels describe the current branch, not release readiness. The release gate below remains authoritative.

### 0. Foundation

**Status: Implemented.**

- Generate the Xcode project and establish App Store sandbox entitlements.
- Discard the unshipped scaffold's development SwiftData container; replace its draft schema rather than migrating it. No real user library data exists yet.
- Define the versioned SwiftData schema and repository boundary.
- Establish the three-pane window shell and build/run entrypoint.
- Add temporary and on-disk persistence test helpers.

### 1. Import and document identity

**Status: Partially implemented.** The functional Add Papers foundation, identity checks, duplicate review, storage choices, progress, summaries, exact-match repair or relocation, and confirmed referenced/managed removal are available. The remaining recovery surfaces and background availability work stay in this slice.

- Implement open-panel and drag-and-drop Add Batches.
- Route the sidebar toolbar button, File → Add Papers (`⌘O`), and library drag-and-drop through one shared Add Batch workflow. After selection or drop, show the same compact sheet with file count, total size, **Reference Originals** selected by default, **Keep Copies in Canopy**, Add Papers, and Cancel.
- Run Preflight silently and show review or summary UI only for duplicates, skipped candidates, invalid files, or failures.
- If Preflight lasts beyond a short delay, show non-cancellable progress while keeping the app responsive; no library changes occur until Preflight completes. Use a determinate 0–100% bar weighted primarily by total bytes hashed, plus “Processing n of total” and the current filename. Reserve a small final portion for metadata parsing so 100% means Preflight is complete.
- Continue the same progress surface through two labeled phases: **Checking Papers** for Preflight and **Adding Papers** for managed-file copies and database commits.
- Commit accepted Papers independently during Adding Papers. Preserve successful additions, continue after isolated failures when safe, and identify each failure in the exception-only Add Batch Summary.
- Do not retain Add Batch Summary history. Keep the exception report available until dismissal and provide Copy Report for troubleshooting.
- Copy Report includes filenames and filesystem paths with the home directory abbreviated as `~/`, but excludes PDF text, bookmark data, content fingerprints, and metadata beyond fields already visible in the summary.
- Create and resolve security-scoped bookmarks.
- Stream SHA-256 fingerprints and collapse exact duplicates.
- Compare Potential Duplicates without creating version relationships; offer Add as Separate Paper, Keep Existing, or Cancel Remaining Additions.
- Present Potential Duplicates in one list-and-detail review. Require a decision per candidate, while offering reversible **Add All as Separate** and **Keep All Existing** bulk choices before final confirmation.
- Compare each triggered candidate with side-by-side metadata and provenance, filename, Remembered Location, file size, page count, embedded dates, normalized extracted-text similarity, and the pages whose extracted text differs. Full paragraph-level and visual PDF diffing is deferred.
- Trigger Potential Duplicate Review only from deterministic evidence: exact DOI, exact base arXiv identifier, exact normalized title plus matching author surname, or exact normalized title plus matching year. General text similarity may inform an already-triggered comparison but never trigger one.
- Compare Add Batch candidates both against the existing library and against earlier candidates in the same Preflight so a single batch cannot introduce Exact or Potential Duplicates unnoticed.
- When a referenced Add Batch contains multiple exact-matching candidates, show their paths and let the user choose the source location to retain. For managed-copy batches, retain one exact candidate and skip the others without a location prompt.
- Validate PDFs and report scanned, encrypted, damaged, missing, offline, and changed states.
- Preserve a referenced Source PDF's Remembered Location. Present Broken References in place with a broken-link symbol and Source Missing label; opening one offers Locate Source, Remove from Library, or Cancel.
- Require an exact SHA-256 match for Repair Reference.
- When Add Papers finds an Exact Duplicate of a Paper with a Broken Reference, offer Repair Existing Paper or Keep Broken instead of creating another Paper.
- When Add Papers finds an Exact Duplicate of a healthy referenced Paper, offer Use New Location, Open Existing Paper, Reveal Current Source, or Dismiss. Relocate Source requires the same SHA-256 fingerprint and only replaces the bookmark and Remembered Location.
- Repairing an externally referenced Paper preserves referenced storage and creates a new bookmark; the Add Batch storage choice applies only to newly added Papers.
- If a Canopy-managed Source PDF is absent, mark the Paper Library Copy Missing. An exact SHA-256 match selected by the user is copied back into managed storage; nonmatching content is rejected or routed through Add Papers as separate.
- If a referenced file remains reachable but its SHA-256 fingerprint changes, mark the Paper Source Changed and block its old annotations and reading state from applying. Offer Locate Original, Add Changed File as Separate Paper, Remove from Library, or Cancel; never silently replace the existing Paper's source.
- Distinguish Source Unavailable for temporarily unreachable external or cloud locations from Broken Reference. Preserve the bookmark, expose Retry, and return the Paper to healthy automatically after access and identity checks succeed.
- When the library opens, perform lightweight background availability checks that do not intentionally materialize File Provider placeholders. Resolve bookmark access, compare attributes, and conditionally hash only when the user opens a Paper or explicitly retries it; Canopy itself makes no network requests.

### 2. Library

**Status: Partially implemented.** Validated local metadata extraction and deterministic title inference are available. The library presents Recent and remaining sections, supports Title and Date Added sorting, ranks title matches before author/year and note matches, clears recent history without deleting Papers, and applies distinct referenced/managed removal semantics with native Undo. Paper Info stages atomic title, year, DOI, arXiv, and ordered Author Credit edits from all three entry points while showing provenance and source details. Author Credits support add, remove, display-name editing, expanded family-name correction, drag reordering, and native Undo. Reparse Metadata remains.

- Implement validated metadata extraction and editable fields.
- Add deterministic first-page title inference.
- Add recent and alphabetical sections, clear-history action, sorting, and tier-one search.
- Implement precise removal semantics for referenced and managed files.

### 3. Reader and resume

**Status: Implemented.** Source identity is verified before the current session applies reading state or loads annotations. Reader-state persistence failures are surfaced with retry behavior.

- Wrap PDFKit with continuous scrolling and navigation controls.
- Implement document-local find.
- Persist and restore page, viewport, zoom, and inspector state.
- Detect source changes before applying stored state or annotations.

### 4. Highlights and notes

**Status: Implemented.** Highlights are stored separately from PDF bytes and rendered as temporary PDFKit overlays. A scene-scoped annotation session prevents stale annotations from appearing before current-source verification and exposes retryable verification or load failures. Create, delete, and note-edit operations support native Undo and Redo.

- Capture composite selection anchors and render PDFKit overlays.
- Add the accessible contextual color palette.
- Implement the page-ordered inspector and navigation to anchors.
- Add debounced notes, explicit critical saves, persistence errors, and Undo.

### 5. Release hardening

**Status: Pending.** Feature-level accessibility affordances and automated coverage exist, but the complete fixture, accessibility, appearance, packaging, and App Store passes have not been performed.

- Complete keyboard and VoiceOver coverage.
- Validate light, dark, increased-contrast, and differentiate-without-color modes.
- Test large, scanned, malformed-metadata, missing, modified, and external-volume fixtures.
- Configure App Store identity, signing, privacy labels, screenshots, and review notes.

## Release gate

A release candidate must pass:

- Unit tests for metadata validation, fingerprints, duplicates, anchors, and repositories
- Real-store persistence tests that destroy and recreate containers
- Multi-process or multi-launch tests covering create, update, delete, undo, recency clearing, and reading state
- Migration tests opening fixtures from every released schema
- File lifecycle integration tests for reference and copy modes
- UI smoke tests for import → read → highlight → note → terminate → relaunch → resume
- Manual fixture-library checks and accessibility inspection

No feature is complete without its empty, error, offline/unavailable, cancellation, persistence, and relaunch behavior.
