# Canopy v1 Plan

## Product boundary

Canopy v1 is a Mac App Store application for macOS 15 or later. It is fully offline and makes no network requests. The launch experience always opens the library rather than reopening a document.

The complete v1 journey is:

1. Add one or more PDFs from an open panel or drag and drop.
2. Reference the originals by default or explicitly copy the import batch into Canopy.
3. Browse recent and alphabetical library sections and search title, authors, year, and notes.
4. Open a PDF in a continuous vertical reader.
5. Select text or draw a single-page area, choose one of five colors, and optionally attach a note.
6. Close and relaunch Canopy, then recover the library, annotations, and exact reading position.

Everything outside that journey belongs in the deferred-feature catalog.

## Non-negotiable rules

- The prototype is archival reference, never a source dependency.
- No old library migration is provided.
- PDF bytes never live in SwiftData.
- Referenced sources are read-only; Canopy never modifies them.
- Managed PDFs are immutable app-owned copies.
- Annotations are database records separate from the Source PDF, never PDF mutations.
- SwiftData is accessed through repositories rather than directly throughout the UI.
- Paper removal, Paper Info edits, annotation creation/deletion, annotation color changes, and note edits save explicitly and participate in native Undo.
- Every persisted schema is versioned from its first release.
- Research content, filenames, highlights, and notes never enter telemetry.

## Storage model

### Referenced PDFs

Canopy stores an app-scoped security-scoped bookmark, source attributes, and a SHA-256 content fingerprint. The bookmark supplies persistent sandbox access; the fingerprint establishes document identity.

On access, Canopy compares file size and modification date. If either changed, it streams the file through SHA-256 again. A digest mismatch blocks annotation display until the user locates the original file or explicitly resolves the change. Persisted source states distinguish Available, Source Unavailable, Broken Reference, Source Changed, and Library Copy Missing. Permission failures map to Source Unavailable; unreadable and password-protected PDFs are specific Add Papers failures rather than persisted Paper states.

### Managed copies

When explicitly selected during import, Canopy copies the PDF into its Application Support container. The import choice applies to the batch and cannot be changed afterward in v1. Removing the paper also removes its managed copy after confirmation.

### SwiftData

The versioned SwiftData schema stores:

- Paper identity and editable title, authors, year, DOI, and arXiv ID
- Storage mode and bookmark or managed relative path
- SHA-256 fingerprint and cached source attributes
- Added/opened timestamps and reading state
- Text-highlight anchors or Area Annotation rectangles, colors, optional notes, and timestamps

The first schema is deliberately small. Future concepts do not get placeholder columns or speculative relationships.

## Annotations

Each annotation has one kind: text highlight or area. Both kinds store a zero-based page index, one non-semantic color, an optional plain-text note, and timestamps.

Each text highlight additionally stores:

- PDF selection quadrilaterals in page coordinates
- Exact selected text

Each Area Annotation stores one user-drawn rectangle in page coordinates. Canopy renders its inspector thumbnail from the verified Source PDF rather than persisting a second cropped image. Selecting its inspector thumbnail centers and zooms the reader to the rectangle with enough surrounding page context to preserve orientation. Area Annotations work on scanned PDFs and other pages without selectable text.

Geometry provides exact rendering; selected text supplies the text-highlight quotation shown in the inspector. Exact Source PDF fingerprint verification protects both annotation kinds from being applied to changed bytes. Externally changed PDFs do not receive automatic re-anchoring in v1.

Colors are yellow, green, blue, pink, and purple. Color controls always include names, selection borders, and checkmarks, and users can change an existing annotation's color from the inspector with native Undo and Redo. Annotation rows remain understandable without distinguishing hue, and Canopy respects increased-contrast and differentiate-without-color preferences. Area Annotation overlays use a clear border and light translucent fill; increased contrast strengthens the border and Differentiate Without Color adds the color's non-color symbol.

## Window and state ownership

Canopy v1 has one primary window containing a stable sidebar-detail layout with a native inspector:

- Sidebar: recent history, full library, basic sorting, and search
- Detail: PDFKit reader and reader toolbar
- Inspector: one page-ordered annotation list with text quotations or Area Annotation previews and inline note editing

Paper metadata is managed in a dedicated **Paper Info** sheet opened from an info button in the reader toolbar, the Paper row's **Get Info** context-menu command, or `⌘I`. The sheet contains editable bibliographic fields and Author Credits, field provenance, source status and location, and Reparse Metadata; it does not occupy another column. All edits and approved reparse replacements remain staged until the user chooses Save; Cancel discards the entire transaction. Author Credits use ordered rows with add, remove, and drag-to-reorder controls; each exposes a display name and permits correction of the derived family name when expanded.

The selected Paper and transient reader interaction state belong to the single window. macOS native restoration owns window geometry and column widths; Canopy supplies sensible default and minimum dimensions without persisting a parallel geometry preference. Each Paper stores page, viewport, zoom, and inspector visibility. Switching Papers flushes the outgoing state before verifying and restoring the incoming Paper. Find queries/results, text selections, annotation popovers, and focused annotations reset on a Paper swap. The reader saves navigation state with a debounce; annotation creation and deletion save transactionally; note typing saves after a short debounce and on focus loss.

## Library behavior

- Launch with no selected Paper.
- Show recently opened papers above the remaining alphabetical library.
- “Clear Recent History” removes only opened timestamps.
- Full-library sorting supports Title and Date Added.
- Search ranks title before authors/year and note text.
- Exact duplicate content, detected by SHA-256, maps to one paper record.
- Scanned PDFs are readable and support Area Annotations, but have no text highlighting, document Find, or title inference when text is unavailable. The reader explains that the PDF has no selectable text and disables text-dependent controls without treating the Paper as an Add Batch exception.
- Password-protected and damaged PDFs fail import with a specific explanation.

## Metadata behavior

Canopy reads embedded PDF metadata locally and validates every field before assignment. Identifier-shaped titles—including arXiv IDs, DOIs, URLs, UUIDs, filenames, and generic export labels—are rejected. If the title is unusable, deterministic first-page layout analysis attempts to locate the prominent title block. Low-confidence results fall back to a cleaned filename. Title is the sole required bibliographic field; Paper Info cannot save it empty. Author Credits, year, DOI, and arXiv ID are optional. Each retained field records its current Metadata Provenance. Manual edits replace earlier inferred values. Reparse Metadata presents different, usable values found in the current Source PDF for field-by-field approval rather than overwriting immediately. A value not found during reparsing is not offered as a clear; optional fields can be cleared manually in Paper Info. DOI and arXiv ID may be empty, but malformed nonempty identifiers block Paper Info from saving and never participate in duplicate matching. Publication year may be blank or a four-digit value from 1000 through the next calendar year; invalid values remain visible for correction and block Save.

## Reader behavior

- Continuous vertical scrolling
- Direct page entry and page count
- Zoom in/out, Fit Width, and Actual Size
- Native in-document find with next/previous result and count
- Selection-adjacent five-color highlight palette
- One-shot Area Annotation mode from the reader toolbar or Paper menu (`⌘⇧A`): the user draws one rectangle on one page, `Esc` cancels, and completion presents the existing color/note palette
- Optional “Add Note” path into the inspector
- No outline, thumbnail rail, OCR, or semantic annotation categories

## Architecture

`Canopy` is the application and SwiftUI composition target. `CanopyCore` is a local Swift package containing independently testable domain and infrastructure code.

```text
Canopy app target
  App/                 scenes and commands
  Stores/              window-scoped workflows, annotation session, and Undo coordination
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

**Status: Implemented.** Canopy uses one primary window with focused window-owned commands. The finalized unreleased v1 schema, non-destructive database recovery, and non-blocking managed-copy reconciliation warning are in place.

Remaining:

- [x] Enforce one primary Canopy window and window-targeted commands.
- [x] Finalize the unreleased v1 schema: remove embedded PDF dates and annotation context fields; add annotation kind/area geometry and the selectable-text capability needed by the reader.
- [x] Add the non-destructive database-open recovery screen.
- [x] Surface managed-copy reconciliation failures without blocking the library.

- Generate the Xcode project and establish App Store sandbox entitlements.
- Discard the unshipped scaffold's development SwiftData container; replace its draft schema rather than migrating it. No real user library data exists yet.
- Define the versioned SwiftData schema and repository boundary.
- Establish the sidebar-reader-inspector window shell and build/run entrypoint.
- Add temporary and on-disk persistence test helpers.

### 1. Import and document identity

**Status: Implemented.** Checking Papers is delayed, responsive, cancellable, and generation-gated while Adding Papers remains deterministic. Preflight performs bounded metadata/capability analysis, Potential Duplicate evidence is scoped to each comparison, and changed or unavailable referenced sources follow the specified Add Papers and exact-match recovery paths.

Remaining:

- [x] Make Checking Papers cancellable and keep Adding Papers commit completion deterministic.
- [x] Replace full-document text extraction with first-page metadata, direct page count, and a lightweight selectable-text signal.
- [x] Narrow and align the Potential Duplicate comparison fields.
- [x] Route a known changed file directly through Add Papers.
- [x] Add exact-match Locate Source fallback for Source Unavailable.

- Implement open-panel and drag-and-drop Add Batches.
- Route the sidebar toolbar button, File → Add Papers (`⌘O`), and library drag-and-drop through one shared Add Batch workflow. After selection or drop, show the same compact sheet with file count, total size, **Reference Originals** selected by default, **Keep Copies in Canopy**, Add Papers, and Cancel.
- Run Preflight silently and show review or summary UI only for duplicates, skipped candidates, invalid files, or failures.
- If Preflight lasts beyond a short delay, show cancellable progress while keeping the app responsive; cancellation makes no library changes. Use a determinate 0–100% bar weighted primarily by total bytes hashed, plus “Processing n of total” and the current filename. Reserve a small final portion for metadata parsing so 100% means Preflight is complete. Once Adding Papers begins, let its short sequence of independent file/database commits finish rather than introducing partial-cancellation semantics.
- Continue the same progress surface through two labeled phases: **Checking Papers** for Preflight and **Adding Papers** for managed-file copies and database commits.
- Commit accepted Papers independently during Adding Papers. Preserve successful additions, continue after isolated failures when safe, and identify each failure in the exception-only Add Batch Summary.
- Do not retain Add Batch Summary history. Keep the exception report available until dismissal and provide Copy Report for troubleshooting.
- Copy Report includes filenames and filesystem paths with the home directory abbreviated as `~/`, but excludes PDF text, bookmark data, content fingerprints, and metadata beyond fields already visible in the summary.
- Create and resolve security-scoped bookmarks.
- Stream SHA-256 fingerprints and collapse exact duplicates.
- Analyze only first-page text for metadata, obtain page count directly from PDFKit, and use a lightweight early-exit scan to record whether the PDF has any selectable text. Do not extract and retain every page's text during Preflight.
- Compare Potential Duplicates without creating version relationships; offer Add as Separate Paper, Keep Existing, or Cancel Add Batch.
- Present Potential Duplicates in one list-and-detail review. Require a decision per candidate, while offering reversible **Add All as Separate** and **Keep All Existing** bulk choices before final confirmation.
- Compare each triggered candidate with side-by-side trigger reason, title, comparable full author names, year, DOI/arXiv ID, filename or Remembered Location, file size, and page count. Do not compute or show metadata provenance, embedded PDF dates, text-similarity scores, or differing-page analysis in v1.
- Trigger Potential Duplicate Review only from deterministic evidence: exact DOI, exact base arXiv identifier, exact normalized title plus matching author surname, or exact normalized title plus matching year. General text similarity does not participate in v1 duplicate review.
- Compare Add Batch candidates both against the existing library and against earlier candidates in the same Preflight so a single batch cannot introduce Exact or Potential Duplicates unnoticed.
- When a referenced Add Batch contains multiple exact-matching candidates, show their paths and let the user choose the source location to retain. For managed-copy batches, retain one exact candidate and skip the others without a location prompt.
- Validate selected PDFs, record whether selectable text is available, and report specific encrypted, unreadable/damaged, missing, or inaccessible failures. Changed, unavailable, and missing-source outcomes for existing Papers use the compact persisted source-state model defined above.
- Preserve a referenced Source PDF's Remembered Location. Present Broken References in place with a broken-link symbol and Source Missing label; opening one offers Locate Source, Remove from Library, or Cancel.
- Require an exact SHA-256 match for Repair Reference.
- When Add Papers finds an Exact Duplicate of a Paper with a Broken Reference, offer Repair Existing Paper or Keep Broken instead of creating another Paper.
- When Add Papers finds an Exact Duplicate of a healthy referenced Paper, offer Use New Location, Open Existing Paper, Reveal Current Source, or Dismiss. Relocate Source requires the same SHA-256 fingerprint and only replaces the bookmark and Remembered Location.
- Repairing an externally referenced Paper preserves referenced storage and creates a new bookmark; the Add Batch storage choice applies only to newly added Papers.
- If a Canopy-managed Source PDF is absent, mark the Paper Library Copy Missing. An exact SHA-256 match selected by the user is copied back into managed storage; nonmatching content is rejected or routed through Add Papers as separate.
- If a referenced file remains reachable but its SHA-256 fingerprint changes, mark the Paper Source Changed and block its old annotations and reading state from applying. Offer Locate Original, Add Changed File as Separate Paper, Remove from Library, or Cancel; never silently replace the existing Paper's source. Add Changed File uses the known changed location and routes it directly through the ordinary storage-choice, Preflight, and duplicate checks, falling back to a picker only if that location is no longer accessible.
- Distinguish Source Unavailable for temporarily unreachable external or cloud locations from Broken Reference. Preserve the bookmark, expose Retry as the primary action and exact-match Locate Source as a fallback, and return the Paper to healthy automatically after access and identity checks succeed.
- When the library opens, perform lightweight background availability checks that do not intentionally materialize File Provider placeholders. Resolve bookmark access, compare attributes, and conditionally hash only when the user opens a Paper or explicitly retries it; Canopy itself makes no network requests.

### 2. Library

**Status: Implemented.** Validated local metadata extraction and deterministic title inference are available. The library presents Recent and remaining sections, supports Title and Date Added sorting, ranks title matches before author/year and note matches, clears recent history without deleting Papers, and applies distinct referenced/managed removal semantics with native Undo. Paper Info stages atomic title, year, DOI, arXiv, and ordered Author Credit edits from all three entry points while showing provenance and source details. Author Credits support add, remove, display-name editing, expanded family-name correction, drag reordering, and native Undo. Reparse Metadata verifies and rereads the current Source PDF, presents each different usable value for approval, and preserves inferred or manual provenance through the staged Save, Cancel, Undo, and Redo transaction.

- Implement validated metadata extraction and editable fields.
- Add deterministic first-page title inference.
- Add recent and alphabetical sections, clear-history action, sorting, and tier-one search.
- Implement precise removal semantics for referenced and managed files.

### 3. Reader and resume

**Status: Implemented.** Source identity is verified before reading state or annotations apply. Find is asynchronous, progressive, and cancellable; scanned/no-text PDFs explain and disable text-dependent controls; and the Paper transition path saves outgoing state before restoring incoming state while clearing transient interactions.

Remaining:

- [x] Make document Find asynchronous, progressively counted, and cancellable.
- [x] Explain and disable text-dependent controls for PDFs without selectable text.
- [x] Verify outgoing-save/incoming-restore and transient-state reset across Paper swaps.

- Wrap PDFKit with continuous scrolling and navigation controls.
- Implement asynchronous document-local Find that cancels prior work when the query changes or the user switches Papers and updates its result count progressively.
- Persist and restore page, viewport, zoom, and inspector state.
- Detect source changes before applying stored state or annotations.

### 4. Annotations and notes

**Status: Implemented.** Text highlights and single-page Area Annotations are stored separately from PDF bytes, rendered as temporary PDFKit overlays, and shown in a page-ordered inspector. Area previews render from the verified Source PDF, both kinds support named color editing and notes with Undo/Redo, and cross-page text selections are rejected with guidance.

Remaining:

- [x] Implement Area Annotation capture, persistence, rendering, thumbnails, navigation, notes, Undo, and accessibility behavior.
- [x] Add inspector color editing with explicit save and Undo/Redo for both annotation kinds.
- [x] Reject cross-page text selections with clear guidance.

- Capture composite selection anchors and render PDFKit overlays.
- Restrict a text highlight to one page; if a selection crosses a page boundary, ask the user to select text on one page at a time.
- Add the accessible contextual color palette.
- Implement the page-ordered inspector and navigation to anchors.
- Implement one-shot user-drawn Area Annotations with page rectangles, generated inspector thumbnails, region navigation, scanned-PDF support, toolbar and Paper-menu entry points, `⌘⇧A`, and `Esc` cancellation. Drawing remains a user-controlled pointer operation; VoiceOver covers mode instructions and every action before and after capture without attempting automatic region selection or image description.
- Allow both annotation kinds to change color from the inspector with explicit save and native Undo/Redo.
- Add debounced notes, explicit critical saves, persistence errors, and Undo.

### 5. Release hardening

**Status: In progress.** The v1 surfaces expose keyboard-reachable commands and explicit VoiceOver labels or values for source status, progress, duplicate decisions, Find results, Area Annotation capture, and inspector state. The bounded generated fixture matrix and isolated terminate/relaunch UI journey are implemented. Manual cross-mode inspection, executing the UI journey on an automation-enabled host, macOS 15 verification, packaging, and App Store work remain; see `Documentation/RELEASE_CHECKLIST.md`.

Remaining:

- [ ] Complete manual cross-mode, keyboard, VoiceOver, and native PDF text inspection.
- [x] Add the bounded fixture matrix and one end-to-end terminate/relaunch UI journey.
- [ ] Verify macOS 15 and the current macOS release.
- [ ] Complete App Store identity, signing, privacy labels, screenshots, and review notes.

- Complete keyboard and VoiceOver coverage.
- Validate light, dark, increased-contrast, and differentiate-without-color modes.
- Test large, scanned, malformed-metadata, missing, modified, and external-volume fixtures.
- Configure App Store identity, signing, privacy labels, screenshots, and review notes.

## Release gate

A release candidate must pass:

- Unit tests for metadata validation, fingerprints, duplicates, text/area anchors, and repositories
- Repository-level on-disk tests that save, destroy the container, and reopen it to cover create, update, delete, Undo, recency clearing, annotations, and reading state
- Initial-schema creation and reopen coverage. Historical migration fixtures begin when a second released schema exists; v1 has no earlier public schema to migrate.
- File lifecycle integration tests for reference and copy modes
- One automated UI journey for Add Papers → read → highlight → note → terminate → relaunch → reopen → verify annotation and reading position
- A small fixed fixture matrix covering a representative large PDF, scanned PDF, malformed metadata, missing source, modified source, and damaged/password-protected Add Papers failures. Verify one external-volume disconnect/reconnect manually rather than building removable-drive automation.
- Manual accessibility inspection in light, dark, increased-contrast, and Differentiate Without Color modes, including native PDF text with VoiceOver and the Area Annotation workflow
- Verification on macOS 15 and the current macOS release
- App Store identity, signing, privacy labels, screenshots, and review notes

Each workflow must cover the empty, failure, cancellation, persistence, source-availability, and relaunch states that actually apply to it. The release checklist records why a state is not applicable rather than manufacturing behavior that does not exist.
