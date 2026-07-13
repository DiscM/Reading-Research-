# Canopy

Canopy is a dependable, offline-first research PDF reader for macOS. Version 1 focuses on one complete workflow: import a PDF, find it again, read it, highlight text, attach an optional note, and resume where you stopped.

## Status

This branch is a ground-up rebuild. It intentionally contains no source code or data migrations from the archived Research Paper Reader prototype.

The first functional slice is available: **Add Papers** supports multi-file selection and drag-and-drop, referenced or managed storage, PDF validation and local metadata parsing, SHA-256 duplicate detection, deterministic potential-duplicate review, progress, partial-success reporting, and exact-match reference repair or relocation.

- Prototype branch: `codex/archive-research-paper-reader-prototype`
- Prototype tag: `archive/research-paper-reader-prototype-2026-07-10`
- Deferred capabilities: [`Documentation/DEFERRED_FEATURES.md`](Documentation/DEFERRED_FEATURES.md)
- Architecture and delivery plan: [`Documentation/V1_PLAN.md`](Documentation/V1_PLAN.md)

## Development

Canopy requires macOS 15+, Xcode 26, and XcodeGen.

```sh
./script/build_and_run.sh
```

Generate the Xcode project without launching the app:

```sh
xcodegen generate
```

The bundle identifier `com.discm.Canopy` is provisional until the App Store record and signing team are configured.

The repository currently lives in a folder named `$$$`, which Xcode misparses when resolving Swift package source paths. The build script stages a disposable source mirror under the system temporary directory before invoking Xcode. Moving the checkout to a path without dollar signs will remove the need for this workaround.
