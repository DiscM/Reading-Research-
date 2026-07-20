# Canopy

Canopy is a dependable, offline-first PDF knowledge workspace for macOS. It keeps research papers, lecture slides, class notes, textbooks, handouts, and general documents in one searchable library while preserving each Source PDF and the reader’s work around it.

## Status

This branch is a ground-up rebuild. It intentionally contains no source code or data migrations from the archived Research Paper Reader prototype.

The first-release workspace is implemented across these slices:

- **Add Documents** supports multi-file selection and direct multi-file drops onto Collections, a batch Document Kind, referenced or managed storage, cancellable bounded Preflight, local metadata parsing, universal SHA-256 duplicate detection, and bibliographic Potential Duplicate Review only for Research Papers. Dropping an Exact Duplicate onto a Collection adds the existing Document's membership instead of creating a second Document.
- **Workspace organization** provides All Documents, Recent, Unfiled, and flat many-to-many Collections. Collections are organizational references: they may mix referenced and managed Documents and never own, move, copy, or delete Source PDFs.
- **Browsing and multi-selection** provides a compact Document list, multi-kind filters, four sort modes, standard macOS multi-selection, bulk Kind and Collection changes, and storage-aware removal summaries.
- **Reader and resume** verifies Source PDF identity before opening, presents a continuous vertical PDFKit reader with page and zoom controls plus asynchronous cancellable Find, explains PDFs without selectable text, and restores page, viewport, zoom, and inspector state.
- **Overview, annotations, and notes** adds one searchable Document Note, retains page-linked Annotation Notes, and switches the inspector between Overview and Annotations without overlaying PDF content. Annotations remains the launch-default tab.
- **Document Info** adapts Creator Credit and date labels by Document Kind, limits DOI and arXiv to Research Papers, reparses non-research metadata conservatively, and preserves source recovery and storage conversion.
- **Offline search and indexing** builds a durable, versioned, page-linked PDF text index in the background. It resumes after relaunch, reuses exact-content indexes, retains search text for unavailable referenced sources, and exposes progress through a floating activity popover.

Annotations remain hidden until the selected Document’s Source PDF is verified in the current reading session. Source changes and annotation-load failures have explicit unavailable, error, and retry states.

The refined v1 product scope is implemented. Release readiness still requires the manual accessibility/OS checks, an automation-enabled run of the relaunch UI journey, packaging, and App Store work recorded in [`Documentation/RELEASE_CHECKLIST.md`](Documentation/RELEASE_CHECKLIST.md).

- Prototype branch: `codex/archive-research-paper-reader-prototype`
- Prototype tag: `archive/research-paper-reader-prototype-2026-07-10`
- Deferred capabilities: [`Documentation/DEFERRED_FEATURES.md`](Documentation/DEFERRED_FEATURES.md)
- General workspace plan: [`Documentation/GENERAL_WORKSPACE_PLAN.md`](Documentation/GENERAL_WORKSPACE_PLAN.md)
- Original reader-foundation plan: [`Documentation/V1_PLAN.md`](Documentation/V1_PLAN.md)

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
