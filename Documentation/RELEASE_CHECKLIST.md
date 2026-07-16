# Canopy v1 Release Checklist

This checklist distinguishes automated evidence from work that needs a person, a particular host OS, removable hardware, or App Store credentials. A release candidate should record its commit and date here before the final pass.

- Release candidate commit: _not yet assigned_
- Checklist last updated: 2026-07-15
- Legend: **Automated**, **Manual**, **External**, **N/A**

## Automated gates

- [x] **Automated** — The bounded generated fixture matrix builds and passes with:
  `swift test --package-path Packages/CanopyCore --filter ReleaseFixtureMatrixTests`
  - 24-page representative large PDF, constrained to 4–20 MiB
  - three-page scanned/no-selectable-text PDF
  - malformed embedded title/author metadata with deterministic filename fallback
  - missing selected Source PDF
  - previously added managed Source PDF removed from disk (Library Copy Missing)
  - modified managed Source PDF rejected by fingerprint verification
  - damaged PDF and password-protected PDF with distinct Add Papers failures
- [x] **Automated** — The real macOS `CanopyUITests` target builds through the `Canopy` scheme.
- [ ] **Automated** — Run `CanopyRelaunchUITests/testAddReadHighlightNoteAndResumeAfterRelaunch` successfully. The journey covers Add Papers → open Paper → page 2, intra-page scroll, and zoom → exact text highlight → note → close → terminate → relaunch → reopen → verify annotation, note, page, viewport, and zoom. It uses a generated three-page PDF and a UUID-isolated store below the app sandbox's `CanopyUITests` directory. A cleanup-only isolated launch removes that directory after the journey; malformed UI-test configuration fails closed and never opens the user's normal `CanopyV1.store`.
  - Current host blocker (2026-07-15): `CanopyUITests-Runner` timed out while enabling macOS automation mode before any test method ran. Re-run on a host where Xcode UI-testing automation is enabled. Result bundle: `/tmp/CanopyDerivedData/Logs/Test/Test-Canopy-2026.07.15_19-03-42--0700.xcresult`.
- [ ] **Automated** — Run the complete `CanopyCore`, `CanopyTests`, and `CanopyUITests` suites on the release-candidate commit.
- [ ] **Automated** — Archive the Release configuration and validate the archive before App Store upload.

## Workflow-state applicability

| Workflow | Empty | Failure | Cancellation | Persistence | Source availability | Relaunch |
| --- | --- | --- | --- | --- | --- | --- |
| Library startup | **Applicable** — empty library UI | **Applicable** — non-destructive recovery and reconciliation warning | **N/A** — opening has Retry, Reveal, and Quit rather than a cancellable transaction | **Applicable** — on-disk repository tests | **Applicable** — background availability checks | **Applicable** — UI journey |
| Add Papers | **Applicable** — no selection leaves library unchanged | **Applicable** — matrix covers missing, damaged, and protected inputs; core tests separately cover inaccessible inputs | **Applicable** — Checking Papers cancellation must leave no library changes; Adding Papers intentionally completes | **Applicable** — independently committed Papers and Add Batch summary | **Applicable** — referenced source permissions and exact-match recovery | **Applicable** — added Paper reopens in UI journey |
| Reader and Find | **Applicable** — no selected Paper and empty Find query | **Applicable** — source and save errors remain retryable | **Applicable** — asynchronous Find cancels for a new query or Paper | **Applicable** — reading-state repository coverage | **Applicable** — changed/unavailable sources block stale state | **Applicable** — page, viewport, and zoom restore in the UI journey and repository reopen tests |
| Text/Area annotations and notes | **Applicable** — empty inspector | **Applicable** — save/load errors remain retryable | **Applicable** — `Esc` cancels Area Annotation drawing; text creation is an explicit short transaction; note debounce flushes on focus loss | **Applicable** — text/area on-disk reopen and Undo coverage | **Applicable** — verified fingerprint required before display/edit | **Applicable** — text highlight and note in UI journey |
| Paper Info | **Applicable** — optional metadata fields may be blank; title may not | **Applicable** — invalid staged values block Save | **Applicable** — Cancel discards the staged transaction | **Applicable** — repository and Undo coverage | **Applicable** — Reparse requires verified source | **Applicable** — edits live in the library store |
| Historical schema migration | **N/A** — v1 has no earlier public schema | **N/A** | **N/A** | **Applicable** — initial schema create/reopen only | **N/A** | **Applicable** — initial-schema reopen coverage |

## Manual and external gates

- [ ] **Manual** — Inspect keyboard-only operation and focus order for the complete v1 journey.
- [ ] **Manual** — Inspect VoiceOver output, including native PDF text and all Area Annotation actions before and after pointer capture. VoiceOver does not automatically select or describe an image region.
- [ ] **Manual** — Inspect light, dark, increased-contrast, and Differentiate Without Color modes. Confirm named colors, selection borders/checkmarks, stronger area borders, and non-color symbols.
- [ ] **Manual** — Confirm scanned PDFs disable Find/text highlight while preserving reading and Area Annotation.
- [ ] **Manual** — Disconnect and reconnect a Source PDF on a removable external volume. Removable-drive automation is intentionally **N/A** because it would not reproduce real volume permission and mount behavior reliably.
- [ ] **Manual** — Verify installation, launch, persistence, PDFKit selection, and accessibility on macOS 15.
- [ ] **Manual** — Verify the same behavior on the current supported macOS release.
- [ ] **External** — Confirm App Store application identity, team, signing certificate, provisioning, and sandbox entitlements.
- [ ] **External** — Complete privacy labels. Canopy is offline, has no telemetry containing research content, and makes no network requests; labels still require App Store Connect confirmation.
- [ ] **External** — Capture final screenshots and prepare review notes, including referenced-file access, managed copies, source recovery, and Area Annotation behavior.
- [ ] **External** — Upload the validated archive and resolve App Store validation or review feedback.

## Release sign-off

- [ ] Automated gates complete or have an approved documented exception.
- [ ] Manual gates signed off by reviewer and dated.
- [ ] External/App Store gates signed off by account owner and dated.
- [ ] No release-blocking warnings or known data-loss defects remain.
