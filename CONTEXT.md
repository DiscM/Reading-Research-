# Canopy

Canopy is an offline research-reading environment that organizes source material and the reader's work around it.

## Language

**Paper**:
The research object in Canopy that holds editable bibliographic identity, reading state, highlights, and notes.
_Avoid_: Leaf, document, file

**Source PDF**:
The PDF bytes associated with a Paper, either referenced at a user-controlled location or held as a Canopy-managed copy.
_Avoid_: Paper, document

**Leaf**:
The visual branding metaphor used when presenting a Paper; it is not a domain entity or persistence term.
_Avoid_: Using Leaf in model, storage, accessibility, or command terminology

**Add Papers**:
The user-facing action that adds selected Source PDFs to the library, either by reference or as managed copies.
_Avoid_: Import, ingest

**Exact Duplicate**:
A selected Source PDF whose SHA-256 content fingerprint already belongs to a Paper in the library. An Exact Duplicate cannot create another Paper, but it may repair that Paper's Broken Reference.
_Avoid_: Duplicate Paper, copy

**Potential Duplicate**:
A selected Source PDF with different content bytes that shares an exact DOI or base arXiv identifier with an existing Paper, or shares an exact normalized title plus a matching author surname or year. The user compares both Papers' metadata and decides whether to add the candidate.
_Avoid_: Exact Duplicate, related version

**Potential Duplicate Review**:
The Add Papers comparison that presents bibliographic, file, and content differences between a candidate and existing Papers without asserting a version relationship.
_Avoid_: Version comparison, merge review

**Add Batch**:
The set of Source PDFs selected together through Add Papers and reviewed before any accepted Paper is committed to the library.
_Avoid_: Import batch, upload

**Add Batch Summary**:
The ephemeral, exception-only result shown when an Add Batch contains duplicates, skipped candidates, or failures; fully successful batches complete without interruption. A user may copy the report before dismissing it.
_Avoid_: Success popup, import report

**Preflight**:
The read-only phase that validates an Add Batch, fingerprints its Source PDFs, extracts comparison metadata, and identifies duplicates before the library changes.
_Avoid_: Import, commit

**Broken Reference**:
A Paper whose externally stored Source PDF can no longer be accessed at its remembered location. The Paper and reader-created work remain in the library while Canopy presents repair or removal controls.
_Avoid_: Missing Paper, deleted Paper

**Library Copy Missing**:
A Paper whose Canopy-managed Source PDF is absent from app storage. An exact-matching PDF may be copied back into managed storage to restore it.
_Avoid_: Broken Reference, referenced source

**Source Changed**:
A referenced Paper whose file remains reachable but no longer matches its recorded content fingerprint. Canopy preserves the Paper but does not apply its annotations or reading state to the changed bytes.
_Avoid_: New version, Broken Reference

**Source Unavailable**:
A referenced Paper whose source location is temporarily unreachable, such as an offline external volume or cloud location. Canopy preserves its bookmark and retries without treating the source as deleted.
_Avoid_: Broken Reference, Source Changed

**Remembered Location**:
The last displayable filesystem path known for a referenced Source PDF, retained to explain a Broken Reference; it does not grant access.
_Avoid_: Bookmark, managed path

**Repair Reference**:
The user action that selects a Source PDF with the original content fingerprint to restore a Broken Reference.
_Avoid_: Reimport, replace Paper

**Relocate Source**:
The user action that moves a healthy referenced Paper to a different Source PDF location with the same content fingerprint.
_Avoid_: Repair Reference, storage conversion

**Metadata Provenance**:
The retained origin of an accepted Paper's current title, authors, year, and identifiers, such as embedded metadata, first-page extraction, filename fallback, or user entry. A manual edit replaces the prior value and provenance; Preflight candidates that are not added retain neither.
_Avoid_: Confidence score, source path

**Reparse Metadata**:
The user action that extracts fresh metadata from a Paper's current Source PDF and presents different, usable field values for approval after manual edits or unsatisfactory inference. A field not found during reparsing is not treated as an instruction to erase its current value.
_Avoid_: Restore metadata, undo edits

**Author Credit**:
One author name in the order presented by a Paper's Source PDF, unless the user explicitly reorders it. Author Credits are local to that Paper and do not assert cross-paper person identity.
_Avoid_: Author Identity, global author

**Author Identity**:
A future user-confirmed person that may link multiple Author Credits and their name variants across Papers.
_Avoid_: Automatically inferred author, Author Credit

**Area Annotation**:
A user-drawn rectangular annotation on one Source PDF page, intended for figures, tables, equations, diagrams, scanned passages, or other regions without relying on selectable text. Canopy stores page geometry and renders previews from the verified Source PDF; it does not persist a separate cropped image.
_Avoid_: Image file, screenshot, OCR region, automatically detected figure
