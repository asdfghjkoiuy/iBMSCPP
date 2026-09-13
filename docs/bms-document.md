# BMS byte document foundation

`ibms::BmsDocument` is a lossless byte container with a narrow metadata edit
surface. It is not a BMS chart parser, validator, conditional evaluator, or
format conversion layer.

## Source behavior and scope

The local µBMSC source baseline is `iBMSC/iBMSC/ChartIO.vb` at commit
`f5b21d1de50ce28202d1b2e8d2f614fabde18092`. Its `OpenBMS` path first rewrites
line endings and then uses broad prefix checks for several directives. This
foundation deliberately preserves more source information: it keeps the exact
input bytes, recognizes directives with an ASCII case-insensitive exact token
boundary, and does not evaluate random or conditional sections.

`from_bytes` accepts arbitrary non-NUL byte values, including a UTF-8 BOM and
non-UTF-8 text bytes. It rejects UTF-16 and UTF-32 byte-order marks, as well as
any embedded NUL byte, because this batch has no safe decoding path for them.
`serialize()` returns the original bytes until a metadata operation changes a
specific range.

## Metadata contract

`header(key)` performs a raw, ASCII case-insensitive lookup and returns the
last matching line. It does not decode text. The returned payload excludes the
horizontal whitespace separating a directive from its value and trailing
horizontal whitespace on that line; all other bytes are returned unchanged.
`#TITLEIMAGE` does not match `TITLE`.

`set_header` only accepts `TITLE`, `SUBTITLE`, `ARTIST`, `SUBARTIST`, and
`GENRE`. It rejects unsupported keys and values containing CR, LF, or NUL.
When replacing an existing field, it changes the final matching occurrence and
preserves that line's prefix, separator, and trailing horizontal whitespace.
When adding a field, it uses the first existing line ending or CRLF if the
document has none. The operation restores exact original bytes when undone.

Metadata boundaries use ASCII space and tab only. `header()` removes those
bytes at the beginning and end of a payload, and `set_header()` applies the
same trim before comparing or writing a semantic value. This makes repeated
updates such as `"  title\t"` stable while preserving whitespace that was
already framing the source line. Bytes outside ASCII space and tab, including
non-ASCII whitespace, are not trimmed or decoded.

Any exact conditional directive token among `RANDOM`, `SETRANDOM`, `IF`,
`ELSEIF`, `ELSE`, `ENDIF`, `ENDRANDOM`, `SWITCH`, `SETSWITCH`, `CASE`, `SKIP`,
`DEF`, and `ENDSW` makes `has_conditionals()` true. This conservatively blocks
metadata edits and makes `header()` return no value. The document still
round-trips its bytes unchanged. The flag is calculated once when bytes are
loaded; the allowed metadata edits cannot add or remove conditional directives.

## History and save state

Each successful edit stores a reversible byte-range patch, not a document-wide
snapshot. No-op edits leave history and redo intact. `mark_saved()` records the
current revision only after the caller has durably saved `save_bms()` /
`save_bms_report()` (File → Save) or `serialize()` (in-place bytes); it does
not write a file. File Save uses `save_bms_report()` so overlap and
`UBound(hBPM)` / `hSTOP` / `hSCROLL` can raise the four `ChartIO.SaveBMS`
warning boxes after the file is written. `grid_limit` is `192 / gridPartition`. `dirty()` is false whenever undo or redo reaches that saved
revision, and a new edit after undo clears redo history.
