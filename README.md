# Canopy

Canopy is a dependable, offline-first research PDF reader for macOS. Version 1 focuses on one complete workflow: import a PDF, find it again, read it, highlight text, attach an optional note, and resume where you stopped.

## Status

This branch is a ground-up rebuild. It intentionally contains no source code or data migrations from the archived Research Paper Reader prototype.

The core reading loop now has five functional slices:

- **Add Papers** supports multi-file selection and drag-and-drop, referenced or managed storage, PDF validation and local metadata parsing, SHA-256 duplicate detection, deterministic Potential Duplicate Review, progress, partial-success reporting, exact-match reference repair or relocation, and lightweight background source availability checks.
- **Library browsing and management** presents recently opened Papers above the remaining library, supports Title and Date Added sorting, ranks title search matches ahead of metadata and note matches, clears recent history without removing Papers, and removes referenced or managed Papers with storage-specific confirmation and native Undo.
- **Reader and resume** verifies Source PDF identity before opening, presents a continuous vertical PDFKit reader with page and zoom controls plus document-local find, and restores page, viewport, zoom, and inspector state.
- **Highlights and notes** captures composite text-selection quadrilaterals, presents an accessible five-color contextual palette, renders database-backed overlays without modifying the Source PDF, and provides a page-ordered inspector with navigation and debounced inline notes. Creation, deletion, and note edits save explicitly and participate in native Undo and Redo.
- **Paper Info** opens from the reader, a Paper row, or `⌘I`; stages title, publication year, DOI, arXiv, and ordered Author Credit edits until Save; validates and normalizes the transaction atomically; shows provenance and Source PDF details; can reparse a verified Source PDF through field-by-field replacement choices; and participates in native Undo and Redo.

Annotations remain hidden until the selected Paper's Source PDF is verified in the current reading session. Source changes and annotation-load failures have explicit unavailable, error, and retry states.

Release hardening is still in progress; see the delivery status in the v1 plan.

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

The repository currently lives in a folder named `$$$`, which Xcode misparses when resolving Swift package source paths. The build script stages a disposable source mirror under the system temporary directory before invoking Xcode. Moving the checkout to a path without dollar signs will remove the need for this workaround.
