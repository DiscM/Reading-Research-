# Canopy

Canopy is a dependable, offline-first research PDF reader for macOS. Version 1 focuses on one complete workflow: add a Source PDF, find it again, read it, annotate text or a page area, attach an optional note, and resume where you stopped.

## Status

This branch is a ground-up rebuild. It intentionally contains no source code or data migrations from the archived Research Paper Reader prototype.

The core reading loop is implemented across five slices:

- **Add Papers** supports multi-file selection and drag-and-drop, referenced or managed storage, cancellable bounded Preflight, PDF validation and local metadata parsing, SHA-256 duplicate detection, per-comparison Potential Duplicate Review, partial-success reporting, exact-match source repair or relocation, and lightweight background availability checks.
- **Library browsing and management** presents recently opened Papers above the remaining library, supports Title and Date Added sorting, ranks title search matches ahead of metadata and note matches, clears recent history without removing Papers, and removes referenced or managed Papers with storage-specific confirmation and native Undo.
- **Reader and resume** verifies Source PDF identity before opening, presents a continuous vertical PDFKit reader with page and zoom controls plus asynchronous cancellable Find, explains PDFs without selectable text, and restores page, viewport, zoom, and inspector state.
- **Annotations and notes** captures single-page text selections or user-drawn areas, presents an accessible named five-color palette, renders database-backed overlays and area previews without modifying the Source PDF, and provides a current-Paper inspector with Recent Activity or Page Order sorting, multi-color filtering, navigation, anchor adjustment, color editing, and debounced inline notes. Create, delete, anchor, color, and note changes save explicitly and participate in native Undo and Redo.
- **Paper Info** opens from the reader, a Paper row, or `⌘I`; stages title, publication year, DOI, arXiv, and ordered Author Credit edits until Save; validates and normalizes the transaction atomically; shows provenance and Source PDF details; can reparse a verified Source PDF through field-by-field replacement choices; and can transactionally convert an available Source PDF between referenced and managed storage. Metadata edits participate in native Undo and Redo; storage conversion does not.

Annotations remain hidden until the selected Paper's Source PDF is verified in the current reading session. Source changes and annotation-load failures have explicit unavailable, error, and retry states.

The refined v1 product scope is implemented. Release readiness still requires the manual accessibility/OS checks, an automation-enabled run of the relaunch UI journey, packaging, and App Store work recorded in [`Documentation/RELEASE_CHECKLIST.md`](Documentation/RELEASE_CHECKLIST.md).

- Prototype branch: `codex/archive-research-paper-reader-prototype`
- Prototype tag: `archive/research-paper-reader-prototype-2026-07-10`
- Deferred capabilities: [`Documentation/DEFERRED_FEATURES.md`](Documentation/DEFERRED_FEATURES.md)
- Architecture and delivery plan: [`Documentation/V1_PLAN.md`](Documentation/V1_PLAN.md)

## Development

Canopy requires macOS 15+, Xcode 26, and XcodeGen.

```sh
./script/build_and_run.sh
```

The default command builds the Release configuration, replaces `/Applications/Canopy.app`, and opens that installed bundle. Use `./script/build_and_run.sh --debug` only when you explicitly want a temporary Debug build under the staged DerivedData directory.

Generate the Xcode project without launching the app:

```sh
xcodegen generate
```

The bundle identifier `com.discm.Canopy` is provisional until the App Store record and signing team are configured.
