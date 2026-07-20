# Require content identity when repairing a reference

Repair Reference accepts only a Source PDF whose SHA-256 fingerprint matches the missing source. Filenames and locations may change, but content may not, because attaching existing highlights, notes, and reading position to changed pages would silently corrupt the meaning of the reader's work; changed files may instead be added as separate Documents.
