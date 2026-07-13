# Deferred Feature Catalog

This catalog preserves product ideas from the Research Paper Reader prototype without allowing their implementation to shape Canopy v1. Prototype code remains available only on `codex/archive-research-paper-reader-prototype` at tag `archive/research-paper-reader-prototype-2026-07-10`.

Items are deliberately unprioritized until the v1 reading loop is stable and observed in real use.

## Search and document understanding

- Tiered full-library search: rank title first, then metadata and notes, then indexed PDF content.
- Persistent full-text index with incremental updates, deletion, and rebuild controls.
- Local OCR for scanned PDFs with page-coordinate mappings and progress/cancellation.
- Section and heading detection with an outline navigator.
- Page thumbnails.
- Semantic and hybrid retrieval using local embeddings.
- Grounded library chat with page-linked evidence.

## Library maintenance

- Batch Broken Reference management: verify remembered locations, repair exact-content references, remove selected Papers, and route changed Source PDFs through Add Papers and Potential Duplicate Review.
- Proactive managed-copy storage estimation and warnings for unusually large Add Batches.

## Annotation and knowledge work

- Semantic annotation categories such as claim, evidence, method, limitation, and question.
- Area/image notes for figures, tables, and equations.
- Annotation re-anchoring when a source PDF changes.
- Storage-mode conversion after import.
- Knowledge cards, active recall, and spaced repetition.
- Multi-paper excerpt and evidence workspaces.
- Supporting and conflicting claim comparison.
- Study-design and evidence-quality extraction.

## Metadata, citations, and discovery

- User-managed Author Identities that manually link and unlink Author Credits or aliases across Papers; never infer identity from names alone.
- Crossref, arXiv, PubMed, and DOI metadata enrichment.
- BibTeX, RIS, and CSL-JSON interoperability.
- Citation keys and formatted citations.
- Duplicate/version relationships for preprints and published papers.
- Reference parsing, citation popovers, and citation graphs.
- Related-paper recommendations and relevance feedback.
- Topic, author, citation, and arXiv-category alerts.
- Browser/share-sheet capture and DOI/URL imports.

## Writing and export

- Context-rich research export containing source metadata, quotations, page anchors, notes, and citations.
- Literature-review outlines and citation-aware writing.
- Unsupported-prose warnings linked to evidence.
- Markdown templates plus DOCX, LaTeX, BibTeX, and CSL-JSON export.
- Obsidian, Notion, Anki, Readwise, Zotero, and local automation integrations.

## Platform and document reach

- Password-protected PDF support with Keychain storage.
- EPUB, HTML, DOCX, slides, datasets, and supplementary files.
- PDF darkening, contrast controls, reflow, read-aloud, and focus tools.
- iCloud metadata and optional PDF sync.
- iPad reader and Apple Pencil annotations.
- iPhone companion.
- Shared libraries, roles, comments, audit history, and conflict handling.
- Web companion and extension API.

## AI and hosted services

- Optional on-device summarization and extraction.
- Secure BYOK or hosted model routing.
- Per-request privacy disclosures, local-only overrides, redaction, cancellation, and budgets.
- Cloud services only after Canopy defines explicit consent and data-boundary contracts.
