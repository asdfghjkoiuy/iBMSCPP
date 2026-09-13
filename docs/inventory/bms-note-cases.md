# BMS note and grid cases

This bounded corpus is a source-backed oracle for the native chart work. It contains ten small synthetic, no-asset inputs under `tests/fixtures/bms-chart/`. The manifest records exact bytes, byte lengths, SHA-256 values, and expected event positions. It is not an exhaustive format audit and does not claim runtime compatibility or implementation completion.

The position fields use rational `measure_fraction` and `absolute_quarterbeats`. They do not use the VB editor's internal 192-unit values. For a measure with ratio `r`, the expected quarter-beat length is `4*r`; an event at fraction `f` has `start = prior_measure_quarterbeats + f*(4*r)`.

Events in different channels at the same measure and slot share the same coordinate. The order of event records never advances time.

## Corpus contract

- Fixtures `01`–`05` are editable normal-note and source-preservation cases.
- Fixtures `06` and `07` are retained as normal-note source cases, while their validated long-note behavior is covered by the separate [`bms-long-note-cases.md`](bms-long-note-cases.md) corpus. The normal-note batch does not use them to make a long-note compatibility claim.
- Fixture `10` is a radix edge: `#00011:G1` is a valid base-36 object index, while `#00003:G1` must reject because channel `03` is parsed as hexadecimal BPM. The fixture is marked non-loadable as a whole because the invalid channel is present; its valid channel event is recorded as a token-level oracle.
- `17` and `27` are intentionally unsupported by the source lane mapper. They must not be promoted to an extra eight-lane group. PMS 9-key channels are outside this batch.
- `expected_events` is the evaluated core expectation. `raw_syntactic_events` records source lines that exist in the input but are not necessarily exposed as events: this is used for the unsupported `17/27` rows in fixture `01` and for all records in conditional fixture `08`.
- `manifest.json` is the machine-readable contract. The source files remain the exact bytes named by each entry.

## Source evidence

The source evidence is from the nested VB repository at `iBMSC/iBMSC/` and is independent of any proposed native implementation.

### Parsing and positions

`ChartIO.vb:175-205` accepts a chart line only when the trimmed line starts with `#` and has `:` at the expected position. It reads the three-digit measure, the two-character channel, maps the channel through `BMSChannelToColumn`, skips unmapped channels, and walks the payload as two-character objects. `00` is skipped; every other object produces a note-like source object. The position formula is `MeasureBottom(measure) + MeasureLength(measure) * slot / slot_count`, where `slot` is the two-character object index and `slot_count` is the number of objects in the payload.

`ChartIO.vb:41-140` reads `#mmm02` measure ratios, `#LNOBJ`, `#WAV`, and related headers. `ChartIO.vb:201-205` uses channel-specific numeric rules: ordinary objects use the source's base-36 conversion, while channel `03` uses hexadecimal conversion. That is why `G1` is valid on `#mmm11` but rejected on `#mmm03`. `ChartIO.vb:4-21` normalizes CR, LF, and CRLF before parsing; the corpus still preserves the original raw bytes so a new loader can test byte round-trip separately.

`EditorColumns.vb:147-175` is the lane mapping used by the oracle. `01` maps to the BGM column. `03` and `08` map to BPM, `09` to STOP, and `SC` to SCROLL. The normal playable lane mapping is:

| Side | Lane | Source channels |
|---|---|---|
| 1P | A1 | `16/36/56/76/D6` |
| 1P | A2 | `11/31/51/71/D1` |
| 1P | A3 | `12/32/52/72/D2` |
| 1P | A4 | `13/33/53/73/D3` |
| 1P | A5 | `14/34/54/74/D4` |
| 1P | A6 | `15/35/55/75/D5` |
| 1P | A7 | `18/38/58/78/D8` |
| 1P | A8 | `19/39/59/79/D9` |
| 2P | D1 | `21/41/61/81/E1` |
| 2P | D2 | `22/42/62/82/E2` |
| 2P | D3 | `23/43/63/83/E3` |
| 2P | D4 | `24/44/64/84/E4` |
| 2P | D5 | `25/45/65/85/E5` |
| 2P | D6 | `28/48/68/88/E8` |
| 2P | D7 | `29/49/69/89/E9` |
| 2P | D8 | `26/46/66/86/E6` |

`EditorColumns.vb:147-175` returns zero for `17` and `27`; the source does not define them as supported normal lanes. The fixture oracle records those raw rows separately and excludes them from `expected_events`, never treating them as A8/D8 aliases.

### Editor geometry and grid

`EditorColumns.vb:37-64` defines the source column layout. The measure column is width 50; SCROLL 60; BPM 60; STOP 50; the separator is 5. Playable widths then follow the source pattern `42, 30, 42, 45, 42, 30, 42, 40` for A1–A8 and the same pattern for D1–D8. The source note colors are raw ARGB values: A1/A3/A5/A7 `&HFFB0B0B0`, A2/A6 `&HFF62B0FF`, A4 `&HFFFFC862`, A8 `&HFF808080`; the D columns use the same pattern. BGA/LAYER/POOR are width 40 with the source green tone, and BGM is width 40 with `&HFFE18080`. These are source declarations, not screenshots or claims about native rendering.

`MainWindow.designer.vb:1840-2083` declares grid controls with `CGDivide=16`, `CGSub=4`, snap enabled, and grid/sub-grid controls enabled. `MainWindow.vb:275-277` maps increasing vertical position upward on the panel, so time runs bottom to top. `MainWindow.vb:293-297` is the exact snap rule:

```vb
xRatio = 192.0R / gDivide
Return Math.Floor((xVPos - xOffset) / xRatio) * xRatio + xOffset
```

The rule floors within the current measure using the fixed `192/gDivide` step; it does not split each measure into a number of divisions. With the default `gDivide=16`, the step is 12 VB units, equivalent to 1/4 quarterbeat. A ratio `0.5` measure is 96 VB units and has 8 such steps; a ratio `1.5` measure is 288 VB units and has 24. Fixture `03` carries the corresponding rational quarter-beat expectations.

`MainWindow.designer.vb:3965-4005` declares the main panels as black, fill-docked panels, with the inner panel at 849x643 and scrollbars. `MainWindow.designer.vb:4163-4175` declares the main window at 1082x730 with `AutoScaleMode=None`, `DoubleBuffered=True`, `Segoe UI` 9-point defaults, and key preview enabled. These declarations establish source geometry context only.

### Write, select, drag, and delete behavior

`PanelEvents.vb:515-625` handles NT write mode. It obtains a snapped vertical position, resolves the enabled column, treats an exact same-position/same-column hit as an edit path, prompts for numeric values on numeric columns, and creates an undo record for writes. `PanelEvents.vb:1587-1674` contains the raw write path: it snaps the position, removes an exact collision in the same column, applies modifier-derived flags, creates the note value, and records undo. Normal sound notes use the selected WAV value; numeric channels use the parsed value.

`PanelEvents.vb:930-1033` handles mouse selection and movement dispatch. `PanelEvents.vb:1477-1496` builds a selection box from note rectangles and updates selected state for enabled columns. `PanelEvents.vb:1415-1474` moves selected notes by column and vertical delta, clamps them to valid boundaries, and records the move. `PanelEvents.vb:1356-1412` handles write-mode drag/resize, snaps the moved endpoint, flips start/end when crossed, clamps the result, and records undo. These source behaviors explain the actionable edit cases represented by the corpus; they do not prove native runtime behavior.

`PanelEvents.vb:120-136` dispatches Delete to `mnDelete_Click`, and `MainWindow.vb:4092-4105` removes selected notes, creates the corresponding undo/redo action, recalculates, and refreshes. The manifest does not encode an exhaustive sequence of UI gestures; it records the input event oracle that editing tests can use.

## Fixture index

| Fixture | Purpose | Expected handling |
|---|---|---|
| `01-normal-1p-2p-lanes.bms` | One event in each source-supported 1P/2P normal lane plus `17/27` edge inputs | Supported lanes produce events; `17/27` remain unsupported; editable normal case |
| `02-thirds-and-12grid.bms` | Thirds and a 12-slot row | Positions use fractions such as `1/3` and `11/12`; editable normal case |
| `03-measure-ratios-0.5-1.5.bms` | Ratio `0.5` followed by ratio `1.5` | Quarter-beat positions use measure lengths `2` and `6`; default snap context is 8 and 24 steps |
| `04-duplicate-bgm-and-normal-rows.bms` | Duplicate BGM rows and same normal channel at distinct rows | BGM rows remain independent; same normal channel at different positions does not collide |
| `05-bom-mixed-eol-no-final-newline.bms` | UTF-8 BOM, mixed line endings, no final newline | Raw bytes remain available for round-trip; parser line normalization is a source caveat |
| `06-readonly-lnobj-candidate.bms` | `#LNOBJ` declaration and long-note candidate | Pairing and editability are covered by the separate long-note corpus; this normal-note table makes no pairing claim |
| `07-readonly-ln-endpoint.bms` | Long-note endpoint channel | Pairing and editability are covered by the separate long-note corpus; this normal-note table makes no pairing claim |
| `08-readonly-conditional-branch.bms` | `#RANDOM/#IF` branch with chart content | `expected_events` is empty; raw branch and outside records remain in `raw_syntactic_events`; no branch selection is asserted |
| `09-readonly-malformed-channel.bms` | Malformed channel line beside valid records | Valid records are retained only where the source parser permits; malformed handling remains pending |
| `10-radix-edge-hex-bpm-vs-base36-object.bms` | `#00011:G1` versus `#00003:G1` | Normal channel object is base-36 valid; channel `03` must reject `G1` as non-hex; whole fixture is non-loadable |

Exact expected events, source rows, rational positions, and byte hashes are in `tests/fixtures/bms-chart/manifest.json`.

## Deviations and remaining checks

This batch has no assets, playback, audio verification, BMSON coverage, pixel comparison, or native GUI proof. It does not claim a complete editor or format implementation. LNOBJ/LN endpoint pairing, conditional evaluation, malformed-line policy, and runtime edit behavior remain explicit follow-up checks. Source line normalization means the VB parser's in-memory behavior cannot by itself establish raw-byte preservation. The core and native agents should use the manifest as a bounded contract and record any intentional deviation separately.
