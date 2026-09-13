# BMS long notes

`BmsDocument::long_notes()` returns a cached `BmsLongNotes` snapshot.  It uses
the same exact `BeatPosition` measure fractions and absolute beats as
`BmsDocument::chart()`.  A `BmsLongNote` exposes its source channel, encoding,
and both endpoints.  Each endpoint retains its exact `{ measure, fraction }`,
absolute beat, canonical token, and zero-based physical `source_line`.

The implementation follows iBMSC's BMS loader and pairing model:

- [ChartIO.vb, L132--L140](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L132-L140)
  reads `#LNTYPE` and `#LNOBJ`.
- [ChartIO.vb, L177--L205](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L177-L205)
  preserves source-grid events by channel.
- [MainWindow.vb, L1146--L1275](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L1146-L1275)
  pairs long-channel endpoints and associates an `#LNOBJ` tail with the
  preceding ordinary note.
- [UndoRedo.vb, L208--L238](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/UndoRedo.vb#L208-L238)
  is the source precedent for treating a compound edit as one undo step.

## Supported representations

Long-channel notes are supported on `51`--`56`, `58`, `59`, `61`--`66`, `68`,
and `69`.  Events are ordered within their playable lane by exact beat then
source order and paired consecutively.  A pair must have a strictly increasing
beat range.  An ordinary note in the same lane at either endpoint or inside the
range invalidates editing.

`#LNOBJ xx` is supported when `xx` is a non-zero base-36 token.  A marker is a
tail only when the immediately preceding ordinary event in that lane is a
strictly earlier non-marker head.  Same-beat candidate heads and consecutive
markers are ambiguous.  The model reports the successful pair as channel `11`
through `29` with encoding `BmsLongNoteEncoding::lnobj`; it does not rewrite
the source row into a long-channel row.

`#LNTYPE 1` without endpoints is harmless.  A leftover unmatched long-channel
endpoint stays editable, reports a diagnostic, and does not form a pair.  The
even-prefix endpoints still pair.  `#LNTYPE 2`, a zero or malformed `#LNOBJ`, a
marker without a head, same-beat head candidates, a normal-note overlap
(including a long-note tail), and a mixture of long-channel events with
`#LNOBJ` produce diagnostics and make the derived chart and long-note snapshots
non-editable.  Conditional charts and charts already unavailable to the normal
chart parser are likewise unavailable.  The raw document stays intact in every
unavailable case.

## Editing contract

The four operations below are `BmsDocument` members and use exact rational
coordinates:

```cpp
void insert_long_note(std::string_view channel, BmsLongNotePosition start,
                      BmsLongNotePosition end, std::string_view start_token,
                      std::string_view end_token);
void move_long_note(std::string_view source_channel, BmsLongNotePosition source_start,
                    std::string_view destination_channel,
                    BmsLongNotePosition destination_start,
                    BmsLongNotePosition destination_end);
void resize_long_note(std::string_view channel, BmsLongNotePosition start,
                      BmsLongNotePosition end);
void erase_long_note(std::string_view channel, BmsLongNotePosition start);
```

For a long-channel note, `channel` is one of the supported `5x`/`6x` channels.
For an LNOBJ note, it is the ordinary playable channel.  LNOBJ insertion writes
the declared marker at the tail: `end_token` may be empty or must equal
`long_notes().lnobj_token`.  It cannot introduce a different marker.

Insertions append sparse source rows.  Moves and resizes clear only their old
cells and append new sparse cells, so unrelated bytes and existing row grids
are preserved.  A move may target one of its own vacated endpoints.  Every
operation validates the resulting complete pair set before committing and
creates one shared document-history entry.  Failed validation changes neither
source bytes nor undo/redo history.

To prevent accidental re-pairing, long-note destinations are checked against
all existing intervals, including endpoints.  Normal `insert_note`,
`erase_note`, and `move_note` also derive the candidate long-note model before
committing; they reject a change that alters any validated LNOBJ pairing, or
that would move the endpoints of an already-validated long-channel pair.
`insert_note` may write a leftover `51` and may complete that leftover into a
new pair.  It cannot insert inside an existing pair to split it.  Ordinary
notes outside a closed LNOBJ interval remain editable, while a normal edit
cannot consume an LNOBJ head or tail.

The implementation is intentionally limited to these BMS representations.  It
does not interpret conditional branches, `#LNTYPE 2`, or audio/playback timing
semantics.
