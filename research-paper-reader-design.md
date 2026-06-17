# Research Paper Reader App Design Document

## 1. Overview

This document describes a local-first, AI-assisted research paper reader for people who read, annotate, compare, and synthesize academic papers. The app should feel like a serious reading environment first and an AI workspace second. AI should reduce cognitive friction without replacing careful reading.

The recommended initial product direction is an Apple-first native app for Mac, iPad, and iPhone, with optional cloud services for sync, team libraries, metadata enrichment, hosted AI, and heavy cross-paper reasoning.

## 2. Product Vision

The app turns static research papers into structured, searchable, explainable research objects.

Instead of treating a paper as only a PDF, the app understands:

- The paper's metadata
- Its sections
- Claims
- Methods
- Datasets
- Figures
- Tables
- Citations
- Limitations
- User highlights and notes
- Relationships to other papers

The user should be able to read deeply, ask precise questions, recover past insights, and move from reading to writing with traceable evidence.

## 3. Target Users

### 3.1 Primary Users

- Graduate students
- Academic researchers
- Industry research scientists
- Engineers reading technical papers
- Medical, legal, and policy analysts who read dense technical literature
- Independent researchers and lifelong learners

### 3.2 Secondary Users

- Lab groups
- Journal clubs
- R&D teams
- Students learning how to read papers
- Writers preparing literature reviews

## 4. Core User Problems

Users struggle with:

- Large unread paper libraries
- Poor recall of previously read papers
- Dense methodology and math sections
- Weak PDF annotation workflows
- Repetitive summarization
- Separating claims from evidence
- Comparing similar papers
- Managing citations and notes
- Moving from reading to literature review writing
- Privacy concerns around unpublished or sensitive papers

## 5. Product Principles

### 5.1 Local First

The app must work without cloud services for core reading, annotation, organization, and basic AI features.

### 5.2 AI Optional, Not Mandatory

Users should be able to read and annotate without AI. AI adds leverage, but the reader remains useful without it.

### 5.3 Traceable Intelligence

AI outputs should cite the exact paper passages, figures, or notes they are based on. The user must be able to inspect sources quickly.

### 5.4 Privacy By Default

Private papers, peer review drafts, proprietary research, medical documents, and lab notes should remain local unless the user explicitly enables cloud processing or sync.

### 5.5 Reading Quality Comes First

PDF rendering, text selection, highlighting, zooming, split views, keyboard navigation, and Pencil support must feel excellent.

### 5.6 Research Objects, Not Files

Each paper should become a structured object with metadata, extracted sections, embeddings, citations, notes, figures, and user-created meaning.

## 6. Platform Strategy

### 6.1 Recommended Initial Platform

Start with native Apple apps:

- macOS
- iPadOS
- iOS

Reasons:

- Strong native PDF support through PDFKit
- Apple Pencil support through PencilKit
- High-quality offline app experience
- Strong local AI capabilities on Apple Silicon
- iCloud and CloudKit for optional Apple ecosystem sync
- Researchers commonly read on Mac and iPad

### 6.2 Future Platforms

Add a web companion later if needed:

- Browser access for team libraries
- Quick lookup and search
- Shared reading lists
- Literature review workspace
- Admin/billing/team management

The web version should not be the primary reading experience at first unless cross-platform support becomes the main market requirement.

## 7. High-Level Architecture

```text
Native Apple App
  Reader UI
  Annotation System
  Paper Library
  Local Search
  Local AI Runtime
  Local Database
  Optional Sync Client

Backend API
  Auth
  Billing
  Metadata Enrichment
  Optional Cloud AI
  Team Libraries
  BYOK Routing
  Cloud Search

Storage
  Local File Store
  Local Database
  Optional iCloud/CloudKit
  Optional Object Storage
  PostgreSQL
  Vector Index

External Integrations
  DOI
  arXiv
  PubMed
  Crossref
  Semantic Scholar
  Zotero
  BibTeX
  OpenAI / Anthropic / Google / Local Models
```

## 8. Recommended Tech Stack

### 8.1 Native Client

- Language: Swift
- UI: SwiftUI
- PDF rendering: PDFKit
- Pencil annotation: PencilKit
- Local persistence: SwiftData for simpler MVP, Core Data for more mature sync control
- Local files: FileManager plus app sandbox document storage
- OCR/layout: Vision
- Language processing: NaturalLanguage
- Background processing: BackgroundTasks
- Sync: CloudKit or custom backend sync

### 8.2 Local AI

- Apple Foundation Models framework for built-in on-device language tasks where available
- Core ML for packaged local models such as embeddings, classifiers, rerankers, and lightweight summarizers
- MLX on Mac for heavier local LLM inference
- Optional llama.cpp or Ollama-compatible integration for advanced Mac users

### 8.3 Backend

- Language: TypeScript
- API framework: Hono, Fastify, or NestJS
- Database: PostgreSQL
- Vector search: pgvector
- Queue: Redis, BullMQ, Cloudflare Queues, or managed queue
- Object storage: S3-compatible storage
- Auth: Clerk, Auth0, Supabase Auth, or custom OAuth/passkey system
- Billing: Stripe
- Observability: OpenTelemetry plus a product analytics tool

### 8.4 Web Companion

- Framework: Next.js
- UI: React
- PDF rendering: PDF.js
- Styling: Tailwind CSS plus a restrained component library
- Auth: Same as backend
- Data access: Same API as native apps

## 9. Major Product Modules

## 9.1 Paper Library

### Purpose

The paper library is the user's research home base. It stores documents, metadata, reading state, collections, tags, and project context.

### Core Features

- Import PDF
- Import from DOI
- Import from arXiv URL
- Import from PubMed URL
- Import BibTeX
- Drag-and-drop import on Mac
- Share-sheet import on iOS/iPadOS
- Auto metadata extraction
- Duplicate detection
- Reading status
- Collections
- Tags
- Smart folders
- Full-text search
- Semantic search
- Sort by title, author, year, venue, last opened, relevance

### User-Facing States

- Unread
- Skimmed
- Reading
- Read
- Cited
- Rejected
- Archived

### Implementation Steps

1. Create a Paper model with title, authors, abstract, venue, publication year, DOI, arXiv ID, PMID, file location, import source, reading state, and timestamps.
2. Create Collection, Tag, Author, Note, Highlight, Citation, Figure, Table, and ExtractedSection models.
3. Store original PDFs in app-controlled local storage.
4. Extract PDF metadata immediately after import.
5. Queue background text extraction and section parsing.
6. Run metadata enrichment through DOI, Crossref, arXiv, PubMed, or Semantic Scholar when online.
7. Generate local embeddings after text extraction.
8. Show import progress clearly but allow the user to start reading immediately.

## 9.2 Reader

### Purpose

The reader is the core product surface. It must be fast, quiet, and ergonomic.

### Core Features

- High-quality PDF rendering
- Continuous scroll and page mode
- Single-page and two-page layout
- Zoom
- Fit width
- Fit page
- Thumbnail sidebar
- Table of contents
- Search within paper
- Citation popovers
- Figure/table navigator
- Split view for notes
- Keyboard shortcuts on Mac
- Apple Pencil markup on iPad
- Offline reading

### Design Requirements

- Prioritize the document, not app chrome.
- Keep the toolbar compact.
- Use icons for common actions.
- Provide stable split-pane layouts.
- Avoid large marketing-style surfaces inside the app.
- Make sidebars collapsible.
- Keep annotation colors consistent and meaningful.

### Implementation Steps

1. Embed PDFKit PDFView inside SwiftUI with a UIViewRepresentable/NSViewRepresentable wrapper.
2. Add document loading, page state, zoom state, and scroll position persistence.
3. Implement highlight creation from selected text.
4. Store annotation anchors using page index, character range where possible, bounding rects, and selected text fallback.
5. Add note panel anchored to the selected highlight or page.
6. Add a citation tap handler that resolves references locally when possible.
7. Add figure/table navigator after processing pipeline identifies visual regions.
8. Add Mac keyboard commands for search, next page, previous page, create note, toggle sidebar, and command palette.

## 9.3 Annotation System

### Purpose

Annotations should support deep reading and later synthesis, not only visual markup.

### Annotation Types

- Highlight
- Note
- Question
- Claim
- Evidence
- Method
- Limitation
- Definition
- Confusing passage
- Important figure
- Citation note

### Core Features

- Color-coded highlights
- Typed highlights
- Margin notes
- Threaded notes
- Tags on notes
- Link notes to projects
- Export annotations
- Search annotations
- Convert annotations into outline cards

### Implementation Steps

1. Create a normalized Annotation model independent of PDFKit's native annotation storage.
2. Mirror visual highlights into PDFKit annotations for rendering.
3. Keep app-owned annotation data as source of truth.
4. Use robust anchors: document fingerprint, page index, text quote, character offsets if available, and bounding boxes.
5. Add conflict handling if the PDF file changes.
6. Build annotation export to Markdown, JSON, BibTeX notes, and Zotero-compatible formats.

## 9.4 AI Reading Assistant

### Purpose

The assistant helps users understand, inspect, and synthesize papers while preserving traceability.

### Core Tasks

- Explain selected text
- Summarize paper
- Summarize section
- Extract claims
- Extract methods
- Extract datasets
- Extract limitations
- Explain figures
- Ask questions about one paper
- Ask across library
- Compare papers
- Generate flashcards
- Generate literature review matrix
- Convert notes into an outline

### AI Modes

#### Private Local Mode

- Uses only on-device models.
- No paper content leaves the device.
- Best for sensitive papers.
- May be slower or less capable.

#### Balanced Mode

- Uses local models for small tasks.
- Uses cloud models for heavy synthesis after user approval.
- Good default for most users.

#### Best AI Mode

- Uses strongest configured models.
- Best for quality.
- Requires cloud processing unless the user has powerful local hardware.

#### Custom Mode

- User selects providers and models.
- Supports bring-your-own keys.
- Suitable for labs, power users, and institutions.

### AI Architecture

```text
AI Task Request
  Task type
  Privacy policy
  Model preference
  Context budget
  Source passages
  User notes

Model Router
  Local Foundation Models
  Local Core ML
  Local MLX
  Local Ollama/llama.cpp
  Cloud provider
  BYOK provider

Response Builder
  Structured output
  Citations to source chunks
  Confidence/limitations
  UI-ready answer
```

### Implementation Steps

1. Define AI tasks as typed internal requests instead of raw prompts.
2. Build a model router that can choose local, hosted, or BYOK providers.
3. Add privacy policy checks before any cloud request.
4. Chunk paper text by semantic section.
5. Store source chunks with stable IDs.
6. Generate embeddings locally by default.
7. Use retrieval augmented generation for Q&A.
8. Require source citations in AI responses.
9. Cache AI results per paper version, model, task, and prompt hash.
10. Provide visible controls to rerun, regenerate, copy, cite, or save AI output as a note.

## 9.5 Paper Processing Pipeline

### Purpose

The pipeline turns a raw PDF into structured data.

### Pipeline Stages

1. Import document.
2. Fingerprint file.
3. Extract embedded text.
4. Run OCR fallback for scanned pages.
5. Detect title, authors, abstract, sections, references, figures, and tables.
6. Parse citation list.
7. Resolve citation metadata.
8. Chunk paper by section.
9. Generate embeddings.
10. Run optional AI extraction for claims, methods, datasets, and limitations.
11. Index document for local search.
12. Sync permitted metadata if sync is enabled.

### Implementation Steps

1. Create a background job system in the native app.
2. Track pipeline status per paper.
3. Keep each stage idempotent.
4. Store failures with retry information.
5. Let the user read even if processing is incomplete.
6. Use local-only processing unless cloud processing is enabled.
7. Add a diagnostics panel for failed imports.

## 9.6 Search And Retrieval

### Search Types

- Exact title search
- Author search
- Full-text search
- Highlight/note search
- Semantic search
- Citation search
- Question answering over one paper
- Question answering over all papers

### Local Search

- SQLite full-text search for keywords.
- Local vector index for semantic search.
- Search notes, highlights, and paper text together.

### Cloud Search

- PostgreSQL for metadata.
- pgvector for embeddings.
- Used only for synced or team-visible content.

### Implementation Steps

1. Build keyword search first.
2. Add local embeddings for semantic search.
3. Combine keyword and vector results with reranking.
4. Add filters for year, author, collection, tag, read state, and venue.
5. Add "search within current paper" and "search entire library" as separate scopes.
6. Add source previews for every result.

## 9.7 Literature Review Workspace

### Purpose

The literature review workspace helps users move from reading to synthesis.

### Core Features

- Paper comparison table
- Claim/evidence matrix
- Method comparison
- Dataset comparison
- Limitations summary
- Consensus and disagreement view
- Reading trail map
- Export to Markdown, Word, LaTeX, or BibTeX

### Implementation Steps

1. Let users create Projects.
2. Let users add papers, highlights, and notes to Projects.
3. Build a matrix view from selected papers.
4. Generate draft synthesis paragraphs with citations.
5. Preserve source traceability from generated text back to notes and paper passages.
6. Export project notes and citations.

## 10. User Experience Design

## 10.1 Primary Navigation

Recommended main navigation:

- Library
- Reader
- Search
- Projects
- Review
- Settings

On Mac, use a sidebar. On iPad, use a split view. On iPhone, use tab navigation plus pushed detail screens.

## 10.2 Library Screen

### Layout

- Left: collections and smart folders
- Center: paper list
- Right or detail view: selected paper metadata, abstract, notes, and actions

### Key Actions

- Import
- Search
- Filter
- Create collection
- Change reading status
- Open paper
- Ask AI about selected paper

## 10.3 Reader Screen

### Layout

- Main area: PDF
- Optional left sidebar: thumbnails, outline, figures, references
- Optional right sidebar: notes, AI assistant, paper structure
- Compact top toolbar: search, annotation tools, layout, AI, share/export

### Key Actions

- Highlight selected text
- Add note
- Ask about selection
- Explain paragraph
- Jump to cited paper
- Open figure
- Save quote to project

## 10.4 AI Assistant Panel

### Layout

- Context selector: selection, page, section, whole paper, project, library
- Task buttons: explain, summarize, extract claims, find limitations, compare
- Chat input for custom questions
- Response cards with source links

### Design Rules

- AI answers must show sources.
- AI should not obscure the paper.
- Saved AI outputs become notes.
- The app should label whether the response used local or cloud AI.

## 10.5 Project Workspace

### Layout

- Project paper list
- Notes and highlights grouped by theme
- Matrix views
- Draft outline
- Export controls

### Key Actions

- Add paper to project
- Group notes
- Generate comparison matrix
- Create outline
- Export literature review assets

## 10.6 Settings

### Important Settings

- AI mode
- Cloud processing permissions
- BYOK keys
- Local model downloads
- Sync settings
- iCloud/CloudKit settings
- Citation style
- Export defaults
- Privacy controls
- Data deletion

## 11. Data Model

### Paper

- id
- title
- abstract
- authors
- year
- venue
- DOI
- arXiv ID
- PMID
- file fingerprint
- local file URL
- reading status
- processing status
- created at
- updated at

### ExtractedSection

- id
- paper id
- title
- type
- order
- page range
- text
- embedding status

### Annotation

- id
- paper id
- section id
- type
- color
- selected text
- note body
- page index
- character range
- bounding boxes
- tags
- created at
- updated at

### Citation

- id
- source paper id
- cited title
- cited authors
- cited year
- DOI
- arXiv ID
- matched library paper id
- reference text

### AIResult

- id
- task type
- paper id
- project id
- model provider
- model name
- privacy mode
- prompt hash
- response body
- source chunk ids
- created at

### Project

- id
- name
- description
- paper ids
- note ids
- created at
- updated at

## 12. Privacy And Security

## 12.1 Privacy Defaults

- Store PDFs locally by default.
- Do not upload paper text unless the user enables sync or cloud AI.
- Show clear cloud-processing consent.
- Allow per-paper private mode.
- Allow global private mode.

## 12.2 Bring Your Own Key

BYOK support should include:

- OpenAI
- Anthropic
- Google
- Local OpenAI-compatible endpoint
- Institutional endpoint

Keys should be stored in Keychain on Apple devices. Backend storage of user keys should be avoided when possible. If server-side BYOK is required, encrypt keys with a strong key management system and explain the tradeoff clearly.

## 12.3 Data Protection

- Use Keychain for secrets.
- Use Apple Data Protection classes for local files.
- Encrypt cloud-stored PDFs.
- Support account deletion.
- Support local data export.
- Support local data wipe.
- Keep audit logs for team libraries.

## 13. Sync Strategy

### MVP Sync

Start with optional iCloud sync for Apple-only users:

- Papers metadata
- Notes
- Highlights
- Reading progress
- Collections
- Tags

Large PDF files can be:

- Local only
- iCloud document synced
- Synced through app cloud storage

### Later Sync

Add custom backend sync for:

- Cross-platform support
- Team libraries
- Web companion
- Shared annotations
- Admin controls

### Implementation Steps

1. Decide whether MVP uses SwiftData plus iCloud, Core Data plus CloudKit, or custom sync.
2. Sync metadata before files.
3. Add conflict handling for notes and highlights.
4. Add per-paper sync status.
5. Add private/local-only flag.
6. Add team sync later through backend.

## 14. AI Provider Strategy

### Provider Types

- Apple on-device model
- App-shipped Core ML models
- Mac local MLX model
- User local endpoint
- Hosted app provider
- User BYOK cloud provider

### Model Routing Rules

- Use local embeddings by default.
- Use local AI for selected-text explanations when possible.
- Use cloud or high-end local models for long-context synthesis.
- Require explicit permission for private papers before cloud processing.
- Prefer cheaper models for routine extraction.
- Use stronger models for methodology critique and cross-paper synthesis.

## 15. Monetization

Possible pricing tiers:

### Free

- Local PDF reader
- Basic annotations
- Limited library size
- Local search
- Manual import/export

### Pro

- Unlimited library
- AI credits
- Advanced extraction
- Local model management
- Literature review workspace
- Advanced exports

### Researcher Plus

- Higher AI usage
- Cross-paper synthesis
- Priority model access
- Advanced citation tools

### Teams/Labs

- Shared libraries
- Shared annotations
- Admin controls
- Institution keys
- Billing management
- Audit logs

BYOK can be available in Pro or Teams while still charging for app features, sync, and collaboration.

## 16. MVP Scope

### MVP Implemented

- ✅ **Native Mac app** (macOS 15+, arm64 + x86_64 universal binary)
- ✅ **PDF import** (open panel, drag-and-drop, batch)
- ✅ **PDF reader** (PDFKit with continuous scroll, zoom, find, go-to-page)
- ✅ **Highlighting** (color-coded PDFKit annotations per highlight kind)
- ✅ **Notes** (typed notes anchored to selected text + page number)
- ✅ **Paper library** (sidebar list + visual card grid)
- ✅ **Metadata extraction** (PDF attributes + CrossRef/arXiv API + heuristic/AI)
- ✅ **Tags** (stored per paper, shown on cards)
- ✅ **Reading status** (7 states, filterable + filterable/sortable)
- ✅ **Full-text search** (debounced, across metadata + PDF body)
- ✅ **Local AI summary** (heuristic + Foundation Model + Core ML routing)
- ✅ **Ask questions about one paper** (Extract claims/methods/evidence/limitations)
- ✅ **Export notes to Markdown** (with AI summary, abstract, metadata)
- ✅ **Basic privacy controls** (AI mode selector with status text)
- ✅ **Section detection** (numbered-header-priority, page-mapped)
- ✅ **AI explanation of selected text** (with surrounding context)
- ✅ **Selection screen** (visual card grid with animated transitions)
- ✅ **Sidebar paper list** (filterable, sortable, with status indicators)
- ✅ **Find within paper** (⌘F find bar with match navigation)
- ✅ **Go to page** (⌘G dialog)
- ✅ **Zoom controls** (toolbar buttons + live percentage + trackpad)
- ✅ **Collapsible AI sections** (Summary + Explanation sub-tabs)

### MVP Not Yet

- iPad/iPhone app (Mac-only for MVP)
- ✔️ Local embeddings (semantic search deferred)
- ❌ Collections (tags only)
- ❌ Citation popovers
- ❌ BYOK provider wiring (UI exists, routing not wired)
- ❌ iCloud sync for notes and metadata
- ❌ Team libraries
- ❌ Full web app
- ❌ Advanced literature review generation
- ❌ Large-scale cross-library synthesis
- ❌ Complex citation graph visualization
- ❌ Collaborative live annotation

## 17. Implementation Roadmap

### Phase 1: Foundation ✅ Done

Goals:

- ✅ Create the native app shell.
- ✅ Build the local data model.
- ✅ Load, render, and navigate PDFs.
- ✅ Store papers in a local library.

Steps:

1. ✅ Create SwiftUI app targets for macOS.
2. ✅ Add PDFKit wrapper.
3. ✅ Add local Paper model.
4. ✅ Implement file import.
5. ✅ Store imported PDFs in app storage.
6. ✅ Persist reading position.
7. ✅ Add library screen with sidebar list + visual card grid.

### Phase 2: Annotation And Notes ✅ Done

Goals:

- ✅ Enable deep reading.
- ✅ Persist structured annotations.

Steps:

1. ✅ Add text selection highlight flow.
2. ✅ Add Annotation (PaperNote) model.
3. ✅ Render highlights in PDFKit (color-coded per kind).
4. ✅ Add margin note editor.
5. ✅ Add annotation list panel.
6. ✅ Add tags and annotation types.
7. ✅ Export notes to Markdown.

### Phase 3: Processing Pipeline ✅ Done

Goals:

- ✅ Turn PDFs into structured paper objects.

Steps:

1. ✅ Extract embedded text (per-page, cached as Paper.allText).
2. ❌ OCR fallback (not implemented — relies on embedded text only).
3. ✅ Detect common sections (numbered-header-priority regex).
4. ❌ Parse references (not implemented).
5. ✅ Store chunks by section (PaperSection model).
6. ✅ Add local full-text search (debounced, across all fields).
7. ✅ Add background processing state (import progress + enrichment).

### Phase 4: Local AI And Retrieval ✅ Done

Goals:

- ✅ Add useful AI without cloud dependence.

Steps:

1. ✅ Add AI task abstraction (LocalPaperAI enum with Provider routing).
2. ❌ Local embeddings (semantic search deferred).
3. ✅ Add retrieval over current paper.
4. ✅ Add selected-text explanation.
5. ✅ Add section summary (via Outline / sidebar sections).
6. ✅ Add whole-paper summary.
7. ✅ Add source-linked AI responses (heuristic with context citation).

### Phase 5: Metadata Enrichment ✅ Done

Goals:

- ✅ Enrich paper metadata from publication databases and AI.

Steps:

1. ✅ CrossRef DOI lookup.
2. ✅ arXiv API lookup.
3. ✅ Heuristic metadata extraction from first page.
4. ✅ Foundation Model extraction (macOS 26+, conditional).
5. ✅ Enrichment progress in sidebar.
6. ✅ DOI/arXiv/venue display on cards.
7. ✅ Enrichment-failed indicator for papers that can't be enriched.

### Phase 6: Preview Features ✅ Done

Goals:

- ✅ Add document navigation features from Preview.app.

Steps:

1. ✅ Find within paper (⌘F, match count + prev/next navigation).
2. ✅ Go to page dialog (⌘G).
3. ✅ Zoom controls (in/out buttons + live percentage label).
4. ✅ Page-mapped section navigation (click section → jump PDF to page).
5. ✅ Color swatch indicator for note highlight types.
6. ✅ Collapsible AI result sections (Summary / Explanation).
7. ✅ Sidebar paper list with sort and filter.

### Phase 7: Cloud And BYOK 🔲 Not Started

Goals:

- Add stronger AI and account-backed features.

Steps:

1. ❌ Add account system.
2. ❌ Add backend API.
3. ❌ BYOK provider wiring (UI exists, routing not wired).
4. ❌ Add hosted AI provider.
5. ❌ Add model router.
6. ❌ Add privacy consent gates.
7. ❌ Add usage tracking and billing.

### Phase 8: Sync 🔲 Not Started

Goals:

- Make research state available across devices.

Steps:

1. ❌ Add iCloud or backend sync for metadata.
2. ❌ Sync annotations and notes.
3. ❌ Sync reading status and collections.
4. ❌ Add conflict handling.
5. ❌ Add optional PDF sync.
6. ❌ Add per-paper local-only mode.

### Phase 9: Literature Review Workspace 🔲 Not Started

Goals:

- Help users synthesize across papers.

Steps:

1. ❌ Add Projects.
2. ❌ Add selected notes/highlights to projects.
3. ❌ Build comparison matrix.
4. ❌ Add claim/evidence extraction.
5. ❌ Add method/limitation comparison.
6. ❌ Add outline builder.
7. ❌ Add export to Markdown, Word, LaTeX, and BibTeX.

### Phase 10: Collaboration 🔲 Not Started

Goals:

- Support labs and teams.

Steps:

1. ❌ Add team workspaces.
2. ❌ Add shared libraries.
3. ❌ Add shared annotations.
4. ❌ Add role-based permissions.
5. ❌ Add institution model keys.
6. ❌ Add audit logs.
7. ❌ Add admin billing.

## 18. Key Technical Risks

### PDF Anchoring

PDF text extraction is inconsistent. Highlights must survive imperfect text extraction and document changes.

Mitigation:

- Store multiple anchors: quote, page, bounding boxes, character offsets, and document fingerprint.

### AI Hallucination

AI may produce unsupported claims.

Mitigation:

- Require source citations.
- Use retrieval from extracted chunks.
- Show source previews.
- Avoid presenting AI output as authoritative.

### Local AI Performance

Small local models may be slower or less capable than cloud models.

Mitigation:

- Use task-specific routing.
- Cache outputs.
- Use local models for narrow tasks.
- Offer cloud fallback.

### Sync Complexity

Annotations, documents, and AI outputs can conflict across devices.

Mitigation:

- Sync metadata first.
- Keep immutable event history for annotations when possible.
- Use conflict-aware merges.
- Let users keep papers local-only.

### Copyright And Publisher Restrictions

Cloud processing and sharing can create legal or institutional concerns.

Mitigation:

- Provide local-only mode.
- Avoid public sharing of full paper text.
- Let institutions configure policies.
- Make data flow transparent.

## 19. Success Metrics

### Engagement

- Papers imported per user
- Papers opened per week
- Reading sessions per week
- Highlights per paper
- Notes per paper
- Search usage

### AI Usefulness

- AI responses saved as notes
- Regeneration rate
- Source click-through rate
- User rating of AI answer
- Cloud fallback usage

### Retention

- Weekly active readers
- Returning library searches
- Project creation
- Export usage
- Cross-device sync usage

### Business

- Free-to-pro conversion
- AI credit usage
- BYOK adoption
- Team workspace creation
- Churn by user segment

## 20. Open Product Questions

- Should the MVP be Mac-first, iPad-first, or universal from day one?
- Should sync use CloudKit first or a custom backend from the start?
- Should BYOK be available in the first paid plan?
- Should local AI model downloads be user-visible or managed automatically?
- Should the app target academics first or broader technical readers?
- Should PDF files sync by default, or should only metadata and annotations sync?
- Should the literature review workspace be part of Pro or a separate product tier?

## 21. Recommended First Build

Build a native Apple MVP with:

- Mac and iPad support
- Local paper library
- PDFKit reader
- Structured highlights and notes
- Metadata extraction
- Local full-text search
- Local-first AI for selected text and summaries
- Optional cloud/BYOK for stronger AI
- Markdown export
- Basic iCloud sync for notes and metadata

The first lovable version should make a researcher feel this:

"I can finally read, understand, remember, and reuse what I learned from papers without losing my mind or my notes."
