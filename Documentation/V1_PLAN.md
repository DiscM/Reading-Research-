# Canopy v1 Plan

## Product boundary

Canopy v1 is a Mac App Store application for macOS 15 or later. It is fully offline and makes no network requests. The launch experience always opens the library rather than reopening a document.

The complete v1 journey is:

1. Import one or more PDFs from an open panel or drag and drop.
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

Canopy reads embedded PDF metadata locally and validates every field before assignment. Identifier-shaped titles—including arXiv IDs, DOIs, URLs, UUIDs, filenames, and generic export labels—are rejected. If the title is unusable, deterministic first-page layout analysis attempts to locate the prominent title block. Low-confidence results fall back to a cleaned filename. Title, authors, and year are always editable.

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
  Views/               library, reader, and inspector composition
  Resources/           entitlements and assets

CanopyCore package
  Models/              versioned persisted and value models
  Persistence/         container creation, migrations, repositories
  Services/            bookmarks, fingerprints, metadata, PDF lifecycle
```

PDFKit adapters remain in the app/platform layer. Core logic accepts value representations of page geometry so it can be tested without a live `PDFView`.

## Implementation slices

### 0. Foundation

- Generate the Xcode project and establish App Store sandbox entitlements.
- Define the versioned SwiftData schema and repository boundary.
- Establish the three-pane window shell and build/run entrypoint.
- Add temporary and on-disk persistence test helpers.

### 1. Import and document identity

- Implement open-panel and drag-and-drop batch imports.
- Add reference/copy batch choice, defaulting to reference.
- Create and resolve security-scoped bookmarks.
- Stream SHA-256 fingerprints and collapse exact duplicates.
- Validate PDFs and report scanned, encrypted, damaged, missing, offline, and changed states.

### 2. Library

- Implement validated metadata extraction and editable fields.
- Add deterministic first-page title inference.
- Add recent and alphabetical sections, clear-history action, sorting, and tier-one search.
- Implement precise removal semantics for referenced and managed files.

### 3. Reader and resume

- Wrap PDFKit with continuous scrolling and navigation controls.
- Implement document-local find.
- Persist and restore page, viewport, zoom, and inspector state.
- Detect source changes before applying stored state or annotations.

### 4. Highlights and notes

- Capture composite selection anchors and render PDFKit overlays.
- Add the accessible contextual color palette.
- Implement the page-ordered inspector and navigation to anchors.
- Add debounced notes, explicit critical saves, persistence errors, and Undo.

### 5. Release hardening

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

