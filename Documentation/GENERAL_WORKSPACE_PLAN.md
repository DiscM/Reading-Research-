# Canopy General Workspace v1 Plan

**Status:** Implemented on the generalized workspace branch; verification and release-readiness work remains tracked separately.

Canopy v1 is an offline, PDF-backed knowledge workspace for research papers, lecture slides, class notes, textbooks, handouts, and general documents. It preserves the existing dependable reader and annotation foundation while replacing the research-only library model with generalized Documents, Collections, Document Notes, and local full-text retrieval.

This plan supersedes the research Paper–only boundary in [`V1_PLAN.md`](V1_PLAN.md). Canonical domain terminology lives in [`../CONTEXT.md`](../CONTEXT.md).

## Product boundary

Canopy remains intentionally PDF-backed rather than becoming a standalone notes editor. Every Document has one Source PDF and may additionally hold reading state, Creator Credits, a Document Note, annotations, and Collection memberships.

The first-release workflow is:

1. Add one or more Source PDFs by reference or as Managed Copies, with one user-selected batch Document Kind.
2. Organize Documents later through optional, many-to-many Collection memberships.
3. Browse All Documents, Recent, Unfiled, or one Collection using kind filters, sorting, and scoped search.
4. Open a Document in the existing PDF reader, resume reading, and create text or Area Annotations.
5. Write one Document Note for overall context and Annotation Notes for page-linked observations.
6. Search metadata, Collections, notes, annotations, and locally indexed selectable PDF text.

## Preserved foundations

- macOS 15+ native application with one primary window
- Fully offline operation with no research content entering telemetry
- Referenced Source PDFs and immutable Canopy-managed copies
- SHA-256 content identity, exact duplicate detection, and source recovery
- Source Changed protection before applying reading state or annotations
- Continuous PDFKit reader, page controls, zoom, Find, and exact resume state
- Text highlights, Area Annotations, named colors, adjustment, and page navigation
- Explicit saves where integrity matters, debounced text editing, and native Undo/Redo
- Existing accessibility requirements and non-color status communication

## Domain model

### Document

`Document` replaces `Paper` as the central persisted and user-facing object. It retains source identity, storage state, reading state, and annotations while adding generalized descriptive fields and organization.

Each Document has:

- Title and Metadata Provenance
- One fixed Document Kind
- One optional precision-aware Document Date
- Ordered Creator Credits
- One plain-text Document Note
- Zero or more Collection memberships
- Existing Source PDF identity, storage, availability, and reading-state fields
- Existing text and Area Annotations

### Document Kind

The fixed first-release values are:

- General Document
- Research Paper
- Lecture Slides
- Class Notes
- Textbook
- Handout

Add Documents defaults to General Document and never guesses a specific kind. One Kind choice applies to an Add Batch; users may edit individual Documents or bulk-change selected Documents afterward.

Kind changes presentation without restricting reading or annotation. Creator Credits are labeled Authors for General Documents, Research Papers, Textbooks, and Handouts; Presented by for Lecture Slides; and Created by for Class Notes.

### Document Date

Document Date stores both value and precision so a user may enter a year, month, or day without inventing missing components. Its label adapts by kind: Publication Date, Presentation Date, Note Date, or Document Date.

### Collection

A Collection is a flat, user-defined reference set. Membership is optional and many-to-many. Collections never own, move, copy, or delete a Source PDF, and referenced Documents and Documents with Managed Copies may coexist in one Collection.

One Document retains the same source, note, annotations, metadata, and reading state everywhere it appears. Dragging a Document onto a Collection adds membership and never removes another membership. Removing membership is explicit; deleting a Collection leaves its Documents intact.

### Notes

- A Document Note is one searchable multiline plain-text field without a page anchor.
- An Annotation Note remains attached to a text highlight or Area Annotation and therefore navigates to a page location.
- Standalone notes without Source PDFs remain outside v1.

## Window and navigation

The primary window has three workspace columns plus the native right inspector:

1. Navigation sidebar
2. Document list
3. PDF reader
4. Overview/Annotations inspector

The navigation sidebar, Document list, and inspector collapse independently. The PDF reader remains the permanent primary canvas and does not collapse. Canopy persists column widths and collapsed states across launches.

Collapsing both left columns produces a reader-focused layout. The inspector is a separate resizable column and does not cover PDF content. Its segmented control switches between Overview and Annotations, rendering only one at a time. Annotations is selected at each app launch; a user-selected tab remains active for the rest of that launch.

The View menu and accessible toolbar controls expose every collapse action and inspector tab choice.

### Navigation sidebar

The sidebar contains:

- All Documents
- Recent
- Unfiled
- A flat list of user Collections
- New Collection
- A compact background-indexing footer shown only while work or recoverable failures exist

Collection creation, rename, and deletion use ordinary macOS list interactions and native Undo where persistence changes.

### Document list

The middle column uses compact, approximately two-line rows without PDF thumbnails. A row shows:

- Document Kind icon
- Title
- Kind-sensitive creator label and Document Date
- Collection context only in All Documents and search results
- Source or index badge only when action is required

Kind is a multi-select filter rather than a navigation hierarchy. Sort modes are Title, Document Date, Date Added, and Recently Opened, with meaningful ascending and descending variants. The selected filter and sort apply globally rather than being stored per Collection.

### Multi-selection

The Document list supports standard macOS multi-selection. One selected Document opens in the reader. Multiple selection replaces the PDF with a selection summary and permits only safe bulk actions:

- Add to or remove from Collections
- Set Document Kind
- Create Collection from Selection
- Remove from Library with one confirmation summarizing referenced and Managed Copy consequences

The Overview inspector presents checked, unchecked, and mixed Collection membership states for the selected set. Titles, dates, Creator Credits, Document Notes, and annotations remain single-Document edits.

## Inspector and Document Info

### Overview

The Overview tab provides frequent contextual work:

- Multiline Document Note
- Document Kind picker
- Precision-aware Document Date editor
- Editable Collection memberships
- Read-only Creator Credit and source-status summaries
- Search index state and recovery action when relevant

The Collection membership editor shows current memberships, a searchable checklist, removal controls, and New Collection. Inline edits save with native Undo/Redo.

### Annotations

The existing annotation inspector remains the default inspector tab and retains sorting, color filters, navigation, notes, color editing, anchor adjustment, deletion, and source-verification states.

### Document Info

`Document → Get Info…` (`⌘I`) opens the full sheet for:

- Ordered Creator Credit editing
- Research-only DOI and arXiv fields
- Metadata provenance and reparsing
- Source PDF status, location, and storage conversion

Research metadata is shown only for Research Papers. Non-research metadata parsing remains conservative: title inference uses embedded metadata, prominent first-page text, or filename fallback; Creator Credits and Document Date are accepted only from trustworthy embedded metadata rather than guessed from arbitrary page text.

## Add Documents and Collection management

`Add Papers` becomes `Add Documents`. The Add Batch sheet asks for:

- Reference Originals or Keep Copies in Canopy
- One batch Document Kind, defaulting to General Document

It does not ask for Collection organization. Successfully added Documents begin Unfiled unless the user deliberately drops Source PDFs directly onto a Collection. Existing or newly added Documents can be multi-selected, dragged into Collections, or used to create a Collection from the selection.

Exact SHA-256 duplicate detection applies to every Document Kind. Bibliographic Potential Duplicate Review applies only to Research Papers; other kinds with different bytes add normally even when titles match.

When a Source PDF dropped onto a Collection is an Exact Duplicate, Canopy adds the existing Document to that Collection and reports the reuse in the Add Batch Summary. It never creates a second Document for the same content.

## Search

### Scope

Workspace search defaults to the selected navigation location:

- A Collection searches its members
- Unfiled searches Documents without memberships
- All Documents searches the entire library

Every scoped result view offers Search All Documents without requiring query re-entry.

With one Document selected, `⌘F` performs Find in the open PDF. With multiple Documents selected, `⌘F` searches the selected set and displays an explicit selection-count scope. `⌘⇧F` always focuses workspace search for the current navigation location. With no selected Document, `⌘F` also focuses workspace search.

### Ranking and presentation

Results rank:

1. Title
2. Collection, Creator Credit, Document Kind, and Document Date metadata
3. Document Note and Annotation Note text
4. Selected annotation quotations
5. Indexed PDF body text

Results group matches under one Document heading. Metadata and Document Note matches appear first; Annotation matches navigate to their page and select Annotations; PDF body matches show page-numbered snippets and navigate directly to the page. The best three child matches appear initially, with Show More for additional hits.

Referenced Documents whose sources are unavailable remain searchable from retained local index data. Their results show the source state and open recovery UI instead of pretending page navigation succeeded.

## Background full-text indexing

Canopy indexes selectable PDF text locally, asynchronously, and once per unique Source PDF fingerprint and index-format version. Indexing never blocks Add Documents, opening a PDF, quitting, or ordinary library use.

The index lifecycle is:

- Pending
- Indexing with page progress
- Ready
- Needs Source
- Failed with Retry or Locate Source

Incomplete work persists and resumes after relaunch. Exact duplicates reuse index data. A new index-format version schedules a rebuild. Removing the final Document for a fingerprint deletes its indexed text. OCR remains deferred, so scanned PDFs without selectable text do not receive body-text results.

The navigation footer displays only compact aggregate status. Selecting it opens a roughly 340-point-wide, capped-height, scrollable macOS-material activity popover. The popover floats without resizing columns, updates live, dismisses with Escape or an outside click, and provides accessible inline recovery actions. Successful items disappear quietly.

## Persistence strategy

The research-only SwiftData schema that preceded this work was unreleased, so the generalized implementation introduced a clean `CanopyWorkspaceV1.store` rather than migrating the draft store. The persisted and user-facing model now uses `Document` and `CreatorCredit`, introduces Collection membership, and stores Document Kind, precision-aware Document Date, and Document Note. Compatibility aliases and some internal reader/repository names retain the earlier `Paper` vocabulary temporarily; they do not appear as the general user-facing term.

The full-text index is stored separately and versioned by Source PDF fingerprint and index-format version. Historical migration fixtures begin only after a public schema ships.

## Accessibility and privacy

- All content and indexing remain offline.
- Indexed text stays inside local Canopy storage and is deleted with the final Document that uses its fingerprint.
- Kind icons, source states, index states, Collection membership, multi-selection, and mixed states have explicit VoiceOver labels and never rely on color alone.
- All column and inspector actions are keyboard reachable.
- The indexing popover maintains readable material contrast and exposes live progress accessibly without excessive announcements.
- Existing increased-contrast and Differentiate Without Color requirements continue to apply.

## Explicitly deferred

- Standalone notes without Source PDFs
- Nested Collections, tags, smart Collections, and user-defined Document Kinds
- OCR and scanned-PDF body-text indexing
- PDF thumbnails in the Document list
- EPUB, HTML, DOCX, editable slide formats, and other non-PDF sources
- Cloud sync, collaboration, and web or mobile companions
- Semantic retrieval, embeddings, library chat, and hosted AI
- Collapsing the PDF reader

## Implementation record

### 1. Generalized vocabulary and persistence

- [x] Generalize persisted and user-facing domain terminology to Document and Creator Credit while retaining narrow internal compatibility adapters.
- [x] Replace the unreleased development schema with `CanopyWorkspaceV1.store`.
- [x] Add Document Kind, Document Date, Document Note, Creator Credit, Collection, and membership persistence.
- [x] Preserve source identity, removal, storage conversion, annotations, reading state, and Undo behavior.

### 2. Workspace shell and Collections

- [x] Introduce navigation, Document-list, reader, and inspector composition.
- [x] Add All Documents, Recent, Unfiled, Collection CRUD, membership editing, and drag-to-add semantics.
- [x] Add independent collapse controls and persistent layout restoration.
- [x] Implement compact rows, Kind filtering, four sort modes, multi-selection, and bulk actions.

### 3. Overview and generalized Document Info

- [x] Add the Overview/Annotations switch with launch-default Annotations.
- [x] Implement Document Note, Kind, Date, and Collection inline editors with Undo.
- [x] Generalize Creator Credits and add kind-sensitive labels.
- [x] Restrict research-only metadata and Potential Duplicate Review to Research Papers.
- [x] Preserve conservative metadata extraction for other kinds.

### 4. Indexed workspace search

- [x] Add the versioned per-fingerprint page-text index and resumable background coordinator.
- [x] Build scoped, selected-set, and All Documents search.
- [x] Group metadata, note, annotation, and page-linked body matches by Document.
- [x] Add the compact footer and material activity popover.
- [x] Cover unavailable-source retention, source recovery, index rebuild, exact-duplicate reuse, and durably queued deletion.

### 5. Generalized release verification

- [x] Update the automated relaunch journey to use Add Documents and the generalized store.
- [x] Add repository tests for Collections, memberships, generalized metadata, notes, multi-selection operations, and Undo behavior.
- [x] Add index lifecycle, ranking, scope, rebuild, fallback, fairness, cancellation, and deletion tests.
- [ ] Re-run manual keyboard, VoiceOver, appearance, contrast, layout-restoration, and source-lifecycle checks across the expanded UI.
- [ ] Run the relaunch UI journey on a host where macOS UI-test automation can establish its runner connection.
- [ ] Complete packaging, App Store copy, and final screenshots after the manual gates pass.

## Design artifact

The agreed visual direction is represented by [`canopy-workspace-mockup.svg`](canopy-workspace-mockup.svg). It demonstrates compact two-line rows, stable non-overlapping workspace regions, the Overview/Annotations inspector switch, and the floating indexing activity popover. Collapse affordances and restoration behavior are requirements even where the static mockup cannot demonstrate interaction.
