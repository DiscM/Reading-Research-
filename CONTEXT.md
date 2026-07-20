# Canopy

Canopy is an offline PDF knowledge workspace that organizes source material and the reader's work around it.

## Language

**Document**:
A PDF-backed library item in Canopy that holds descriptive identity, reading state, highlights, and notes. A Document may be a research paper, lecture slide deck, class handout, textbook, exported note, or other PDF source.
_Avoid_: Paper as the general term, file, item

**Document Kind**:
A fixed, user-controlled classification whose initial values are General Document, Research Paper, Lecture Slides, Class Notes, Textbook, and Handout; Add Documents defaults it to General Document rather than guessing a specific kind. It may tailor presentation and descriptive fields but never determines whether a Source PDF can be added or annotated.
_Avoid_: File type, required category, format

**Document Date**:
An optional date associated with a Document whose precision may be a year, month, or day. The interface labels it Publication Date, Presentation Date, Note Date, or Document Date according to Document Kind without creating separate date concepts.
_Avoid_: Assuming January 1 for a year-only value, separate publication year

**Collection**:
A user-defined organizational set of Documents. Membership is optional and many-to-many; a Collection refers to Documents without owning, moving, copying, or deleting their Source PDFs, so referenced Documents and Documents with Managed Copies may coexist in one Collection.
_Avoid_: Folder, storage location, course as a distinct entity

**Document Note**:
The single searchable plain-text note attached directly to a Document for summaries, takeaways, assignments, or general context; it has no page anchor.
_Avoid_: Standalone note, Annotation Note

**Annotation Note**:
An optional plain-text note attached to a text highlight or Area Annotation and therefore anchored to a specific place in a Document's Source PDF.
_Avoid_: Document Note, standalone note

**Source PDF**:
The PDF bytes associated with a Document, either referenced at a user-controlled location or held as a Canopy-managed copy.
_Avoid_: Document, file

**Leaf**:
The visual branding metaphor used when presenting a Document; it is not a domain entity or persistence term.
_Avoid_: Using Leaf in model, storage, accessibility, or command terminology

**Add Documents**:
The user-facing action that adds selected Source PDFs to the library, either by reference or as managed copies.
_Avoid_: Import, ingest

**Exact Duplicate**:
A selected Source PDF whose SHA-256 content fingerprint already belongs to a Document in the library. An Exact Duplicate cannot create another Document, but it may repair that Document's Broken Reference, relocate a healthy referenced Source PDF to the selected location, or add the existing Document to a Collection when the duplicate is dropped there. Each outcome preserves the existing Document and its reader-created work.
_Avoid_: Duplicate Document, copy

**Potential Duplicate**:
A selected Research Paper Source PDF with different content bytes that shares an exact DOI or base arXiv identifier with an existing Research Paper, or shares an exact normalized title plus a matching creator surname or Document Date. Other Document Kinds use only Exact Duplicate detection.
_Avoid_: Exact Duplicate, related version

**Potential Duplicate Review**:
The Add Documents comparison that presents bibliographic, file, and content differences between a Research Paper candidate and existing Research Papers without asserting a version relationship.
_Avoid_: Version comparison, merge review

**Add Batch**:
The set of Source PDFs selected together through Add Documents and reviewed before any accepted Document is committed to the library.
_Avoid_: Import batch, upload

**Add Batch Summary**:
The ephemeral, exception-only result shown when an Add Batch contains duplicates, skipped candidates, or failures; fully successful batches complete without interruption. A user may copy the report before dismissing it.
_Avoid_: Success popup, import report

**Preflight**:
The read-only phase that validates an Add Batch, fingerprints its Source PDFs, extracts comparison metadata, and identifies duplicates before the library changes.
_Avoid_: Import, commit

**Broken Reference**:
A Document whose externally stored Source PDF can no longer be accessed at its remembered location. The Document and reader-created work remain in the library while Canopy presents repair or removal controls.
_Avoid_: Missing Document, deleted Document

**Library Copy Missing**:
A Document whose Canopy-managed Source PDF is absent from app storage. An exact-matching PDF may be copied back into managed storage to restore it.
_Avoid_: Broken Reference, referenced source

**Source Changed**:
A referenced Document whose file remains reachable but no longer matches its recorded content fingerprint. Canopy preserves the Document but does not apply its annotations or reading state to the changed bytes.
_Avoid_: New version, Broken Reference

**Source Unavailable**:
A referenced Document whose source location is temporarily unreachable, such as an offline external volume or cloud location. Canopy preserves its bookmark and retries without treating the source as deleted.
_Avoid_: Broken Reference, Source Changed

**Remembered Location**:
The last displayable filesystem path known for a referenced Source PDF, retained to explain a Broken Reference; it does not grant access.
_Avoid_: Bookmark, managed path

**Repair Reference**:
The user action that selects a Source PDF with the original content fingerprint to restore a Broken Reference.
_Avoid_: Reimport, replace Document

**Relocate Source**:
The user action that moves a healthy referenced Document to a different Source PDF location with the same content fingerprint.
_Avoid_: Repair Reference, storage conversion

**Metadata Provenance**:
The retained origin of an accepted Document's current descriptive metadata, such as embedded metadata, first-page extraction, filename fallback, or user entry. A manual edit replaces the prior value and provenance; Preflight candidates that are not added retain neither.
_Avoid_: Confidence score, source path

**Reparse Metadata**:
The user action that extracts fresh metadata from a Document's current Source PDF and presents different, usable field values for approval after manual edits or unsatisfactory inference. A field not found during reparsing is not treated as an instruction to erase its current value.
_Avoid_: Restore metadata, undo edits

**Creator Credit**:
One attributed person or organization in the order presented by a Document's Source PDF, unless the user explicitly reorders it. The interface labels Creator Credits as Authors for Research Papers, Textbooks, Handouts, and General Documents; Presented by for Lecture Slides; and Created by for Class Notes.
_Avoid_: Separate author, presenter, and note-creator models; Creator Identity

**Creator Identity**:
A future user-confirmed person or organization that may link multiple Creator Credits and their name variants across Documents.
_Avoid_: Automatically inferred creator, Creator Credit

**Area Annotation**:
A user-drawn rectangular annotation on one Source PDF page, intended for figures, tables, equations, diagrams, scanned passages, or other regions without relying on selectable text. Canopy stores page geometry and renders previews from the verified Source PDF; it does not persist a separate cropped image.
_Avoid_: Image file, screenshot, OCR region, automatically detected figure
