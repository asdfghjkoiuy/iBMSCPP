# BMS metadata batch validation

This record covers the current native document session and its byte-metadata
surface. It is a bounded validation record, not a claim of full BMS, editor,
audio, or application compatibility.

## Current functions

The native window exposes these document operations:

| Function | Current behavior | Evidence or source |
| --- | --- | --- |
| New | Creates an empty `DocumentSession`, clears pending field edits, and refreshes the window. | `macos/Sources/IBMSNative/MainWindowController.swift` |
| Open | Opens a single `.bms`, `.bme`, `.bml`, `.pms`, or `.txt` document through an attached `NSOpenPanel` sheet and retains the source URL. | `macos/Sources/IBMSNative/MainWindowController.swift`; final GUI open of `tests/fixtures/bms/01-mixed-endings-no-final-newline.bms` worked. |
| Save | Writes the current session to its existing URL, marks that revision saved, and preserves source bytes outside changed metadata ranges. | `macos/Sources/IBMSNative/MainWindowController.swift`; `out/ui-audit/native-audit-mixed.bms` byte check. |
| Save As | Uses an attached `NSSavePanel` sheet, writes the selected destination, and updates the session URL after success. | `macos/Sources/IBMSNative/MainWindowController.swift`; GUI `Cmd+Shift+S` audit. |
| Undo / Redo | Applies the session history and refreshes the fields and dirty state. `Cmd+Z` and `Cmd+Shift+Z` were exercised. | `macos/Sources/IBMSNative/MainWindowController.swift`; GUI smoke evidence. |
| Preview | Opens and closes the current native preview window. | GUI smoke evidence; playback is not implemented. |

The editable metadata keys are exactly `TITLE`, `SUBTITLE`, `ARTIST`,
`SUBARTIST`, and `GENRE`, as defined by
`macos/Sources/IBMSNative/DocumentSession.swift`. The current UI presents these
five fields in the Header section of
`macos/Sources/IBMSNative/MainWindowContentView.swift`.

## Encoding and byte rules

`DocumentSession` offers an encoding only when the complete source can be
decoded and re-encoded without changing its bytes, and when the editable
metadata payloads also round-trip. The explicit choices are UTF-8, Shift JIS,
and EUC-KR.

- A UTF-8 BOM pins the choice to UTF-8. Foundation's BOM handling is excluded
  only from the candidate round-trip comparison; the bridge retains the BOM in
  the serialized source.
- Without a BOM, ASCII-only content can make the choice ambiguous. UTF-8 is
  initially selected and labelled as a selection, not a detected encoding;
  the user can choose another supported encoding before editing.
- Shift JIS source bytes, including a Japanese resource name, can exclude
  UTF-8 even when `TITLE` itself is ASCII.
- A source that has no supported display encoding remains read-only, but Save
  still writes its original raw bytes.
- An unrepresentable replacement, such as an emoji in Shift JIS metadata, is
  rejected without changing content or undo history.

Conditional documents are also read-only for metadata. Recognized conditional
directives remain in the raw source, metadata values are unavailable for
editing, and Save preserves the source bytes without evaluating branches.

Changing the encoding is rejected whenever undo or redo history exists. Select
the encoding before editing; after an edit, save and reopen the document to
start a fresh session before selecting another encoding. Saving alone records
the saved revision but does not erase the history stacks.

## GUI evidence

The final GUI pass verified New, typing metadata, Return, `Cmd+Z`,
`Cmd+Shift+Z`, and opening and closing Preview. The attached sheet flows were
also exercised:

- Open of `tests/fixtures/bms/01-mixed-endings-no-final-newline.bms` succeeded.
- A TITLE edit made without pressing Return, followed by `Cmd+Shift+S`, saved
  `out/ui-audit/native-audit-mixed.bms`.
- Independent byte comparison matched the original fixture with only
  `#TITLE Mixed Endings` replaced by `#TITLE Native audit title`; all other
  bytes and the missing final newline were preserved.
- With a pending Artist edit, `Cmd+Q` followed by Cancel retained the text.
- Undo restored the saved document's Artist value; New then opened an empty
  document without a discard prompt.
- With a fresh pending TITLE edit, `Cmd+Q`, Save, and Cancel in the Save sheet
  canceled termination and retained the title.
- Undo followed by closing the main window exited the process cleanly.

The saved artifact is intentionally referenced by its workspace-relative path
`out/ui-audit/native-audit-mixed.bms`. The nested VB source checkout remained
clean after this audit.

## Automated evidence and remaining work

| Check | Result |
| --- | --- |
| Final Release test run | 4/4 passed |
| Final independent Debug run | 4/4 passed |
| Independent core ASan + UBSan run | 2/2 passed |
| Independent strict release checks (`-Wall -Wextra -Wconversion -Werror`) | 2/2 passed |

The native link emits a duplicate `-lc++` warning; it is non-blocking for the
reported results.

Actual audio playback, chart note editing, BMSON behavior, external
integrations, and pixel or performance acceptance remain pending. No result in
this batch claims those capabilities.
