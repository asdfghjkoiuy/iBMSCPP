# BMS timing model and timing edits

`BmsDocument::timing()` returns a cached immutable `BmsTiming` snapshot for the
document content revision. Timing uses exact `BeatPosition` values for initial
BPM, measure lengths, event fractions, absolute beats, and BPM/STOP values.
Only the public query result is a `double` number of seconds.

The model accepts a plain `#BPM` initial BPM, indexed `#BPMxx` definitions,
indexed `#STOPxx` definitions, and timing rows `#mmm03`, `#mmm08`, and
`#mmm09`. It accepts decimal BPM values greater than zero and STOP values
greater than or equal to zero. Imported decimal precision is preserved as an
exact rational; the historic editor's entry-widget range and four decimal
places are not import limits. Channel `03` is hexadecimal and accepts integer
BPM values from `01` through `FF`. Indexed resources use base-36 tokens.

`BmsTimingEvent` retains `measure`, exact `fraction`, exact absolute `beat`,
raw canonical `channel` and `token`, decoded exact `value`, and zero-based
physical `source_line`. Duplicate source rows remain observable in `events`.
The derived prefix points are built once per content revision. `seconds_at`
binary-searches those points; it never reparses the document or scans timing
events for a query.

The timing profile follows the documented behavior of Beatoraja's
`jbms-parser` at commit `e19bcc21c8d4c85d7791ff8d31d73c1cb1ea5d27`: within a
same-beat BPM group and within a same-beat STOP group, the last source event
wins. BPM is applied before the STOP at that beat. A STOP value is measured in
raw units, where `raw / 48` is the number of quarter-beats frozen; its seconds
are therefore `raw / 48 * 60 / active_bpm`. `time_before_stop(beat)` returns
arrival time before a STOP at that exact beat; `time_after_stop(beat)` returns
time after it. `seconds_at(beat, after_stop)` provides the same explicit
selection for callers that need one query entry point. Negative beats and
unavailable timing return no value.

The source baseline is iBMSC commit
[`f5b21d1de50ce28202d1b2e8d2f614fabde18092`](https://github.com/zardoru/iBMSC/tree/f5b21d1de50ce28202d1b2e8d2f614fabde18092).
[`ChartIO.vb` lines 23–28](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L23-L28)
initialize BPM to 120; lines
[45–64](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/ChartIO.vb#L45-L64)
parse measure ratios, indexed BPM, and STOP values. The BPM widget permits
only `0.0001..65535.9999` with four decimal places and defaults to 120
([`MainWindow.designer.vb` lines 2561–2571](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.designer.vb#L2561-L2571));
those are UI-entry limits, not import limits.

[`MainWindow.vb` lines 2281–2327](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L2281-L2327)
add STOP duration using `value / 48` and apply a BPM segment to STOPs in that
segment. Its `GetTimeFromVPosition` can integrate a future BPM segment before
the query, so this model deliberately uses the verified reduced timeline
profile instead. This is a bounded playback profile, not a claim of binary
equivalence to an arbitrary bundled parser version.

Timing is unavailable if conditionals appear, `#BASE` is not 36, timing or
measure-ratio syntax is malformed, a timing value is invalid, an indexed
reference is undefined, or an exact beat/timeline cannot be represented. An
unavailable snapshot has source diagnostics but **empty `events` and `points`**;
consumers must guard on `available` and must not use `initial_bpm` as a fallback
playback value. The raw document remains available and serializable. Same-beat
duplicates add a diagnostic but remain available because the selected profile
defines their result.

`set_initial_bpm(decimal)` replaces only the final plain `#BPM` numeric range
or appends a new directive. A bare `#BPM` receives one separating space, and
undo restores its original bytes. It can repair a malformed initial BPM line.

`set_measure_ratio(measure, decimal)` implements only **Case 3** of the four
`BeatChangeMode` branches in
[`MainWindow.vb` lines 4290–4445](https://github.com/zardoru/iBMSC/blob/f5b21d1de50ce28202d1b2e8d2f614fabde18092/iBMSC/MainWindow.vb#L4290-L4445):
the scale operation. Notes retain their source fractions within the edited
measure, while later measure starts move with the changed measure length. It
replaces only the numeric payload of the final `#mmm02` row, preserving the BOM,
indentation, spaces after `:`, trailing spaces, and line ending. It requires
`chart().editable` and validates the candidate chart before committing, so a
ratio that overflows exact derived positions is rejected atomically.

`apply_beat(measures, decimal, mode)` is the side-panel ApplyBeat entry. Case 3
calls `set_measure_ratio` and leaves object coordinates alone. Cases 0–2 rewrite
`#mmm02` and re-home object-edit notes, channel `03` / `08` / `09` / `SC`, and
NT holds (long-channel pairs and LNOBJ pairs) by the absolute beat rules in
`ApplyBeat`. Case 2 NT trims a hold that ends in the cut range to
`xUpAfter - 1` vpos (`1/48` beat). An empty measure list is a no-op. Several
measures commit as one undo. `SC` decimals come from `#SCROLL`, because
`timing()` does not store scroll events.

`insert_timing_event`, `replace_timing_event`, and `erase_timing_event` accept
measures `0..999`, exact fractions in `[0, 1)`, and channels `03`, `08`, or
`09`. They require `chart().editable`; this rejects conditional charts,
non-36 `#BASE`, long-note semantics, and malformed chart rows. `03` writes a
hexadecimal token. `08` and `09` allocate the first free nonzero base-36 ID
after reserving every raw definition and reference, then append a fresh
definition and sparse source row. Indexed replacement patches the original
cell and appends only a fresh definition, so it neither changes a shared
definition nor adds a duplicate event. Replacing an erased cell creates one
new event. Each successful operation is one reversible byte-patch history
transaction shared with metadata and normal-note edits; rejected operations
leave bytes, history, redo, and dirty state unchanged.
