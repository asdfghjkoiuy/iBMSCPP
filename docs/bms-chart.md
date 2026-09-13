# BMS chart snapshot and normal-note editing

`BmsDocument::chart()` derives a cached, lossless-facing `BmsChart`. It uses
exact `BeatPosition` fractions: an event's `fraction` is its source-row slot
position within the measure, and `beat` is the accumulated measure start plus
that fraction times the exact measure length. Measures default to `4/1` beats;
an exact decimal `#mmm02` ratio produces `ratio * 4`. The snapshot does not
calculate seconds from BPM.

Every syntactically valid, non-zero source cell is represented by an event with
its zero-based physical `source_line`. Duplicate rows, simultaneous cells, and
BGM `01` rows remain independent. `03` accepts hexadecimal values; supported
object rows, including `SC`, use base 36. Unknown syntactically valid rows are
retained as `unknown` events. Invalid supported tokens are diagnosed and are
not emitted as events.

The chart is read-only when conditional directives occur: no branch is chosen
and both `events` and `measures` are empty. Editing is also gated by malformed
recognized channel rows, malformed measure-length rows, invalid supported
tokens, invalid measure ratios, non-36 `#BASE`, invalid `#LNOBJ` or long-note
pairing, and unsupported `#LNTYPE` values. A valid long-channel or LNOBJ pair
keeps the chart and long-note views editable; ordinary-note edits are checked
against the resulting pair model and are rejected only when they would consume
an interval, alter a protected marker pairing, or introduce ambiguity.
`#LNTYPE 1` without a long-note event remains editable. If a ratio, measure
timeline, or event beat exceeds `BeatPosition`'s representable range, the
snapshot is read-only with empty derived positions and an overflow diagnostic;
the raw document remains unchanged and serializable. This batch exposes the
model events for consumers, but does not promise that every non-normal kind is
rendered by a particular UI.

`insert_note`, `erase_note`, and `move_note` accept only `11..16`, `18`, `19`,
`21..26`, `28`, and `29`, measurements `0..999`, fractions in `[0,1)`, and
case-insensitive base-36 values `01..ZZ`. Collisions and duplicate source
matches are rejected. Inserts append a sparse exact-fraction source row rather
than resizing an unrelated row; denominators above 65536 are rejected. Erase
replaces exactly one source token with `00`; move is one vector-patch history
transaction. Metadata and notes share undo/redo, dirty, and save chronology.
Failed operations prepare all checks before changing bytes or history.
