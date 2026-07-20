# Canopy v1 Release Checklist

This checklist distinguishes automated evidence from work that needs a person, a particular host OS, removable hardware, or App Store credentials. A release candidate should record its commit and date here before the final pass.

- Release candidate: generalized workspace implementation on `codex/canopy-v1`, based on `ed1e96f`; record the final release commit before distribution
- Checklist last updated: 2026-07-20
- Legend: **Automated**, **Manual**, **External**, **N/A**

## Automated gates

- [x] **Automated** — The complete `CanopyCore` suite passes: 105 tests across 8 suites, including the bounded PDF fixture matrix, generalized persistence and import policy, Collections and membership, Document metadata and dates, source integrity, atomic multi-Document removal and restoration, full-text index lifecycle, version fallback, result fairness, cancellation, and durable index deletion.
- [x] **Automated** — The complete `CanopyTests` app suite passes: 63 tests across 5 suites, including workspace projection and scope, grouped search ranking, precision-preserving Document Info, storage rollback, best-effort index cleanup, and one-operation atomic bulk Undo/Redo.
- [x] **Automated** — The Debug macOS application target builds successfully with code signing disabled.
- [x] **Automated** — The real macOS `CanopyUITests` target builds through the `Canopy` scheme.
- [ ] **Automated** — Run `CanopyRelaunchUITests/testAddReadHighlightNoteAndResumeAfterRelaunch` successfully. The journey covers Add Documents → open Document → page 2, intra-page scroll, and zoom → exact text highlight → Annotation Note → close → terminate → relaunch → reopen → verify annotation, note, page, viewport, and zoom. It uses a generated three-page PDF and a UUID-isolated `CanopyWorkspaceV1.store` below the app sandbox's `CanopyUITests` directory. A cleanup-only isolated launch removes that directory after the journey; malformed UI-test configuration fails closed and never opens the user's normal store.
  - Current host blocker (2026-07-20): `CanopyUITests-Runner` was killed before establishing its XCTest connection, so the operation never entered the test method. Re-run on a host where Xcode macOS UI-test automation is enabled. Result bundle: `/tmp/canopy-ui-tests-final/Logs/Test/Test-Canopy-2026.07.20_16-33-27--0700.xcresult`.
- [ ] **Automated** — Run the complete `CanopyCore`, `CanopyTests`, and `CanopyUITests` suites on the release-candidate commit. Core and app suites are green; the UI journey remains blocked by the host condition above.
- [ ] **Automated** — Archive the Release configuration and validate the generalized-workspace archive before App Store upload.

## Workflow-state applicability

| Workflow | Empty | Failure | Cancellation | Persistence | Source availability | Relaunch |
| --- | --- | --- | --- | --- | --- | --- |
| Workspace startup | **Applicable** — empty workspace shell | **Applicable** — non-destructive recovery and reconciliation warning | **N/A** — opening offers Retry, Reveal, and Quit | **Applicable** — on-disk repository tests | **Applicable** — background availability checks | **Applicable** — repository reopen and UI journey |
| Add Documents | **Applicable** — no selection leaves the workspace unchanged | **Applicable** — fixture matrix covers missing, damaged, protected, and inaccessible inputs | **Applicable** — Checking Documents cancellation leaves no library changes; Adding Documents intentionally completes | **Applicable** — independently committed Documents and Add Batch summary | **Applicable** — referenced-source permissions and exact-match recovery | **Applicable** — added Document reopens in UI journey |
| Collections and multi-selection | **Applicable** — no Collections and empty selection | **Applicable** — failed atomic membership/creation operations roll back | **Applicable** — sheets and confirmations cancel without changes | **Applicable** — many-to-many membership and Undo coverage | **N/A** — Collections never own Source PDFs | **Applicable** — membership repository reopen coverage; layout relaunch remains manual |
| Reader and Find | **Applicable** — no selected Document and empty Find query | **Applicable** — source and save errors remain retryable | **Applicable** — asynchronous Find cancels for a new query or Document | **Applicable** — reading-state repository coverage | **Applicable** — changed or unavailable sources block stale state | **Applicable** — page, viewport, and zoom restore in the UI journey and repository tests |
| Overview and Document Note | **Applicable** — blank optional note/date and no Collections | **Applicable** — invalid dates block persistence and failed saves roll back | **Applicable** — focus changes flush the debounced note; canceled Collection editing changes nothing | **Applicable** — note, date, Kind, membership, and Undo coverage | **N/A** — Document Note editing does not require a currently available source | **Applicable** — store reopen coverage |
| Text/Area Annotations and Annotation Notes | **Applicable** — empty Annotations inspector | **Applicable** — save/load errors remain retryable | **Applicable** — `Esc` cancels Area Annotation drawing; note debounce flushes on focus loss | **Applicable** — text/area on-disk reopen and Undo coverage | **Applicable** — verified fingerprint required before display or editing | **Applicable** — text highlight and Annotation Note in UI journey |
| Document Info | **Applicable** — optional metadata may be blank; title may not | **Applicable** — invalid staged values block Save | **Applicable** — Cancel discards the staged transaction | **Applicable** — precision-preserving repository and Undo coverage | **Applicable** — Reparse requires a verified source | **Applicable** — edits live in `CanopyWorkspaceV1.store` |
| Workspace search and PDF index | **Applicable** — empty query and no indexed Documents | **Applicable** — Needs Source and Failed states expose recovery | **Applicable** — debounced searches and SQLite work observe cancellation; indexing resumes independently | **Applicable** — SQLite FTS index, version fallback, and durable deletion queue coverage | **Applicable** — retained local text stays searchable while navigation requests source recovery | **Applicable** — incomplete index work and deletions reconcile after reopen |
| Historical schema migration | **N/A** — v1 has no earlier public schema | **N/A** | **N/A** | **Applicable** — clean `CanopyWorkspaceV1.store` create/reopen only | **N/A** | **Applicable** — initial-schema reopen coverage |

## Manual and external gates

- [ ] **Manual** — Inspect keyboard-only operation and focus order for the complete v1 journey, including all three collapse controls, Overview/Annotations switching, multi-selection actions, selection-scoped search, and index-popover recovery.
- [ ] **Manual** — Inspect VoiceOver output for mixed Collection memberships, Document Kind and source/index states, search-result groups and page hits, native PDF text, and all Area Annotation actions before and after pointer capture. VoiceOver does not automatically select or describe an image region.
- [ ] **Manual** — Inspect light, dark, increased-contrast, and Differentiate Without Color modes. Confirm named colors, selection borders/checkmarks, mixed membership, index status, stronger area borders, and non-color symbols.
- [ ] **Manual** — Collapse each optional workspace column independently, resize the navigation/list/inspector regions, relaunch, and confirm widths and collapsed states restore without the index footer or floating popover overlapping content.
- [ ] **Manual** — Verify contextual `⌘F`, selection-scoped search, `⌘⇧F`, Search All Documents expansion, grouped Show More behavior, and page-linked annotation/PDF hits.
- [ ] **Manual** — Confirm scanned PDFs disable Find/text highlight and PDF body indexing while preserving reading and Area Annotation.
- [ ] **Manual** — Disconnect and reconnect a referenced Source PDF on a removable external volume. Removable-drive automation is intentionally **N/A** because it would not reproduce real volume permission and mount behavior reliably.
- [ ] **Manual** — Verify installation, launch, persistence, PDFKit selection, background indexing, and accessibility on macOS 15.
- [ ] **Manual** — Verify the same behavior on the current supported macOS release.
- [ ] **External** — Confirm App Store application identity, team, signing certificate, provisioning, and sandbox entitlements.
- [ ] **External** — Provide and review the final App Icon asset catalog. No App Icon asset is present in the current target.
- [ ] **External** — Provide a public privacy-policy URL and add an easily accessible in-app privacy-policy link.
- [ ] **External** — Complete privacy labels. The source audit found no network client, web view, analytics, tracking, or third-party SDK; `PrivacyInfo.xcprivacy` declares no collection and no tracking, but the labels still require App Store Connect confirmation.
- [ ] **External** — Capture final screenshots and prepare review notes covering Collections, mixed storage, multi-selection, Overview/Annotations, workspace search, background indexing, referenced-file access, managed copies, source recovery, and Area Annotations.
- [ ] **External** — Upload the validated archive and resolve App Store validation or review feedback.

## Generalized-workspace evidence — 2026-07-20

- Host: macOS 26.5.1 (25F80), Xcode 26.6 (17F113), XcodeGen 2.45.4.
- `swift test --package-path Packages/CanopyCore`: 105 tests across 8 suites passed.
- `xcodebuild test ... -only-testing:CanopyTests`: 63 tests across 5 suites passed.
- `xcodebuild ... -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`: Debug application build succeeded.
- `./script/build_and_run.sh --verify`: universal Release build succeeded, replaced `/Applications/Canopy.app`, launched it, and verified the installed executable was running.
- `CanopyUITests` built successfully, but the host killed its runner before the XCTest connection formed; no UI assertion ran.
- The expected CoreSimulator version warning is irrelevant to the macOS destination. Failure-path tests also emit expected read-only SwiftData diagnostics while verifying rollback.

## Prior reader-foundation evidence — 2026-07-16 (superseded)

- The previous 64-test core and 38-test app suites passed before the generalized workspace work.
- A universal unsigned Release archive passed Xcode store-oriented bundle validation with version `1.0 (1)`, arm64 and x86_64 slices, a dSYM, and the bundled privacy manifest.
- Ad hoc signing with hardened runtime and the production sandbox entitlements verified for local inspection. Distribution signing remained unavailable because the host had no valid signing identity.
- Empty-library light, dark, increased-contrast, and Differentiate Without Color inspection was partial evidence only and does not satisfy the expanded manual gates above.

## Release sign-off

- [ ] Automated gates complete or have an approved documented exception.
- [ ] Manual gates signed off by reviewer and dated.
- [ ] External/App Store gates signed off by account owner and dated.
- [ ] No release-blocking warnings or known data-loss defects remain.
