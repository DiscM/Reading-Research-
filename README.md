# Research Paper Reader MVP

A native SwiftUI macOS MVP for a local-first AI-assisted research paper reader.

## Features

- Import one or more PDF papers.
- Store a local paper library.
- Read PDFs with PDFKit, with color-coded highlights rendered on the page.
- Full-text search across titles, authors, tags, notes, and PDF body text.
- Track reading status.
- Select PDF text and save typed notes.
- Explain selected text and generate local heuristic summaries and
  claim/method/evidence/limitation extractions.
- Configure MVP AI mode and provider settings.

## Build a distributable app (recommended)

To produce a double-clickable `.app` bundle that any Mac user can launch
without Xcode or the terminal:

```sh
./scripts/build-app.sh          # builds dist/Research Paper Reader.app
./scripts/build-app.sh --open   # build and launch it
```

The script builds a **universal binary** (Apple Silicon `arm64` +
Intel `x86_64`), generates the app icon, assembles the bundle
(`Info.plist`, icon, executable), and ad-hoc code-signs it. If one
architecture slice fails to build on your toolchain, the script warns
and ships the slices that succeeded.

The result is `dist/Research Paper Reader.app`. To share it, zip the
`.app` (or distribute via DMG). Because it is ad-hoc signed (not
notarized), first-time users on another Mac should right-click the app
and choose **Open** to bypass Gatekeeper, or run:

```sh
xattr -dr com.apple.quarantine "Research Paper Reader.app"
```

For wide distribution, sign with a Developer ID certificate and notarize
with `xcrun notarytool` instead of ad-hoc signing.

## Develop

```sh
swift run     # run from source
swift build   # compile only
open Package.swift   # open in Xcode as a Swift Package
```

## Notes

The MVP intentionally keeps paper content local. The AI assistant currently uses deterministic local text extraction and heuristic summarization so the app is useful without keys or cloud services. The next production step is to replace the heuristic `LocalPaperAI` implementation with a model router that can call Apple Foundation Models, Core ML models, MLX/Ollama on Mac, or user-provided cloud API keys.
