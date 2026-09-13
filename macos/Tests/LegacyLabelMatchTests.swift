import Foundation

@main
struct LegacyLabelMatchTests {
    static func main() {
        testSameTokenMatches()
        testDifferentTokenDoesNotMatch()
        testShowFileNameSameFileDifferentToken()
        testShowFileNameMissingFileFallsBackToToken()
        testMatchingNotesIncludesHover()
        testSelectingAddsIsOrNotReplace()
        testSelectClickCtrlTogglesWithoutShift()
        testTogglingFlipsMembership()
        testCtrlDragCopiesSelectedNotes()
        testNoteCaptionUsesFileNameWithoutExtension()
        testHoverASelectsRequiresControlShiftHoverWithoutCommand()
        testCtrlEditMapsEightKeys()
        testCtrlEditRequiresControlWithoutShiftOptionCommand()
        print("LegacyLabelMatchTests passed")
    }

    /// 未勾选 ShowFileName：同一标签匹配。
    private static func testSameTokenMatches() {
        require(
            LegacyLabelMatch.isLabelMatch(
                hoverToken: "01",
                candidateToken: "01",
                showFileName: false,
                hoverFileName: "",
                candidateFileName: ""
            ),
            "same token matches"
        )
    }

    /// 未勾选 ShowFileName：不同标签不匹配。
    private static func testDifferentTokenDoesNotMatch() {
        require(
            !LegacyLabelMatch.isLabelMatch(
                hoverToken: "01",
                candidateToken: "02",
                showFileName: false,
                hoverFileName: "",
                candidateFileName: ""
            ),
            "different token does not match"
        )
    }

    /// 勾选 ShowFileName，两边都有文件名：比文件名，不比标签。
    private static func testShowFileNameSameFileDifferentToken() {
        require(
            LegacyLabelMatch.isLabelMatch(
                hoverToken: "01",
                candidateToken: "02",
                showFileName: true,
                hoverFileName: "kick.wav",
                candidateFileName: "kick.wav"
            ),
            "same file name matches across tokens"
        )
        require(
            !LegacyLabelMatch.isLabelMatch(
                hoverToken: "01",
                candidateToken: "01",
                showFileName: true,
                hoverFileName: "kick.wav",
                candidateFileName: "snare.wav"
            ),
            "different file name does not match even with same token"
        )
    }

    /// 勾选 ShowFileName，但缺文件名：回退到标签。不要把空文件名当成全表相同。
    private static func testShowFileNameMissingFileFallsBackToToken() {
        require(
            LegacyLabelMatch.isLabelMatch(
                hoverToken: "0A",
                candidateToken: "0A",
                showFileName: true,
                hoverFileName: "",
                candidateFileName: ""
            ),
            "both file names empty falls back to token"
        )
        require(
            !LegacyLabelMatch.isLabelMatch(
                hoverToken: "0A",
                candidateToken: "0B",
                showFileName: true,
                hoverFileName: "",
                candidateFileName: ""
            ),
            "empty file names do not match-all"
        )
        require(
            LegacyLabelMatch.isLabelMatch(
                hoverToken: "0A",
                candidateToken: "0A",
                showFileName: true,
                hoverFileName: "kick.wav",
                candidateFileName: ""
            ),
            "one missing file name falls back to token"
        )
        require(
            !LegacyLabelMatch.isLabelMatch(
                hoverToken: "0A",
                candidateToken: "0B",
                showFileName: true,
                hoverFileName: "kick.wav",
                candidateFileName: ""
            ),
            "one missing file name still requires same token"
        )
    }

    /// matchingNotes 含悬停自己，并带上其他同标签音符。
    private static func testMatchingNotesIncludesHover() {
        let hover = LegacyLabelCandidate(id: "hover", token: "03", fileName: "")
        let same = LegacyLabelCandidate(id: "same", token: "03", fileName: "")
        let other = LegacyLabelCandidate(id: "other", token: "04", fileName: "")
        let matches = LegacyLabelMatch.matchingNotes(
            hoverToken: hover.token,
            hoverFileName: hover.fileName,
            candidates: [hover, same, other],
            showFileName: false
        )
        require(matches.contains(hover), "matching notes include hover")
        require(matches.contains(same), "matching notes include same token")
        require(!matches.contains(other), "matching notes exclude other token")
        require(matches.count == 2, "two notes share the hover token")
    }

    /// 加选是 OR：已选留下，匹配的补进去，不是整表替换。
    private static func testSelectingAddsIsOrNotReplace() {
        let already = "kept"
        let added = "new-match"
        let next = LegacyLabelMatch.selectingAdds(
            selected: [already],
            matching: [added]
        )
        require(next.contains(already), "OR keeps prior selection")
        require(next.contains(added), "OR adds matching notes")
        require(next.count == 2, "OR does not replace the set")
        require(
            !LegacyLabelMatch.selectingAdds(selected: [already], matching: []).contains(added),
            "empty matching does not invent notes"
        )
    }

    /// `OnSelectModeLeftClick`：Ctrl 且不是 Ctrl+Shift 时，松手切换点中的那一条。
    private static func testSelectClickCtrlTogglesWithoutShift() {
        require(LegacyLabelMatch.selectClick(control: true, shift: false, hitNote: true) == .toggle,
                "select + Ctrl on a note toggles that note")
        require(LegacyLabelMatch.selectClick(control: true, shift: true, hitNote: true) == .addMatchingLabel,
                "select + Ctrl+Shift stays on same-label add")
        require(LegacyLabelMatch.selectClick(control: false, shift: false, hitNote: true) == .replace,
                "plain click replaces the selection")
        require(LegacyLabelMatch.selectClick(control: true, shift: false, hitNote: false) == .marqueeKeep,
                "Ctrl on empty space keeps the current selection")
        require(LegacyLabelMatch.selectClick(control: false, shift: false, hitNote: false) == .marqueeClear,
                "plain click on empty space clears the selection")
    }

    /// 松手时 `Selected = Not Selected`，只动点中的那一条。
    private static func testTogglingFlipsMembership() {
        let note = "11@0"
        require(LegacyLabelMatch.toggling(selected: [], item: note) == [note],
                "Ctrl click selects an unselected note")
        require(LegacyLabelMatch.toggling(selected: [note], item: note).isEmpty,
                "Ctrl click deselects an already selected note")
        require(LegacyLabelMatch.toggling(selected: [note, "12@0"], item: note) == ["12@0"],
                "Ctrl click leaves the other selected notes")
    }

    /// `OnDuplicateSelectedNotes`：选择模式 Ctrl 拖出位移时复制，不切换已选。
    private static func testCtrlDragCopiesSelectedNotes() {
        require(LegacyLabelMatch.ctrlDragCopies(control: true, shift: false, didDrag: true),
                "select + Ctrl drag copies")
        require(!LegacyLabelMatch.ctrlDragCopies(control: true, shift: false, didDrag: false),
                "select + Ctrl click without a drag still toggles")
        require(!LegacyLabelMatch.ctrlDragCopies(control: true, shift: true, didDrag: true),
                "Ctrl+Shift stays on same-label add, not copy")
        require(!LegacyLabelMatch.ctrlDragCopies(control: false, shift: false, didDrag: true),
                "plain drag moves, it does not copy")
    }

    /// Control+Shift+A：有悬停、不带 Command 才加选同标签。没有悬停对照 `KMouseOver == -1`。
    private static func testHoverASelectsRequiresControlShiftHoverWithoutCommand() {
        require(
            LegacyLabelMatch.hoverASelects(control: true, shift: true, command: false, hasHover: true),
            "Control+Shift+A with hover adds matching labels"
        )
        require(
            !LegacyLabelMatch.hoverASelects(control: true, shift: true, command: false, hasHover: false),
            "KMouseOver == -1 does not add"
        )
        require(
            !LegacyLabelMatch.hoverASelects(control: true, shift: true, command: true, hasHover: true),
            "Command+Control+Shift+A does not steal Command+A"
        )
        require(
            !LegacyLabelMatch.hoverASelects(control: true, shift: false, command: false, hasHover: true),
            "Control+A without Shift is Select All, not this row"
        )
        require(
            !LegacyLabelMatch.hoverASelects(control: false, shift: true, command: false, hasHover: true),
            "Shift+A alone does not add"
        )
        require(
            !LegacyLabelMatch.hoverASelects(control: false, shift: false, command: false, hasHover: true),
            "plain A does not add"
        )
    }

    /// `PMainInPreviewKeyDown`：只要 Control，不要 Alt，不要 Shift。八个键各走已有动作。
    private static func testCtrlEditMapsEightKeys() {
        require(
            LegacyCtrlEdit.action(keyCode: 6, control: true, shift: false, option: false, command: false) == .undo,
            "Control+Z is undo"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 16, control: true, shift: false, option: false, command: false) == .redo,
            "Control+Y is redo"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 7, control: true, shift: false, option: false, command: false) == .cut,
            "Control+X is cut"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 8, control: true, shift: false, option: false, command: false) == .copy,
            "Control+C is copy"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 9, control: true, shift: false, option: false, command: false) == .paste,
            "Control+V is paste"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 0, control: true, shift: false, option: false, command: false) == .selectAll,
            "Control+A is Select All"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 3, control: true, shift: false, option: false, command: false) == .find,
            "Control+F is find"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 17, control: true, shift: false, option: false, command: false) == .statistics,
            "Control+T is statistics"
        )
    }

    /// 没有 Control、带 Shift、带 Option、带 Command、其它键码，这一行都不处理。
    private static func testCtrlEditRequiresControlWithoutShiftOptionCommand() {
        require(
            LegacyCtrlEdit.action(keyCode: 6, control: false, shift: false, option: false, command: false) == nil,
            "Z without Control is not this row"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 0, control: true, shift: true, option: false, command: false) == nil,
            "Control+Shift+A is hover add, not Select All"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 6, control: true, shift: false, option: true, command: false) == nil,
            "Control+Option+Z is not this row"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 6, control: true, shift: false, option: false, command: true) == nil,
            "Command+Z stays on the menu"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 17, control: true, shift: false, option: false, command: true) == nil,
            "Command+T is Snap, not statistics"
        )
        require(
            LegacyCtrlEdit.action(keyCode: 5, control: true, shift: false, option: false, command: false) == nil,
            "Control+G is not this row"
        )
    }

    /// `DrawNote`：勾上 ShowFileName 时，有文件名就画 `GetFileNameWithoutExtension`。
    private static func testNoteCaptionUsesFileNameWithoutExtension() {
        require(
            LegacyLabelMatch.noteCaption(
                token: "01", channel: "11", showFileName: false,
                wavName: "kick.wav", bmpName: ""
            ) == "01",
            "button off keeps the token"
        )
        require(
            LegacyLabelMatch.noteCaption(
                token: "01", channel: "11", showFileName: true,
                wavName: "kick.wav", bmpName: ""
            ) == "kick",
            "sound column uses hWAV without extension"
        )
        require(
            LegacyLabelMatch.noteCaption(
                token: "02", channel: "11", showFileName: true,
                wavName: #"C:\songs\snare.ogg"#, bmpName: ""
            ) == "snare",
            "GetFileNameWithoutExtension drops the directory"
        )
        require(
            LegacyLabelMatch.noteCaption(
                token: "03", channel: "04", showFileName: true,
                wavName: "kick.wav", bmpName: "layer.bmp"
            ) == "layer",
            "BGA uses hBMP, not hWAV"
        )
        require(
            LegacyLabelMatch.noteCaption(
                token: "0A", channel: "01", showFileName: true,
                wavName: "", bmpName: "bg.png"
            ) == "0A",
            "empty hWAV keeps the token"
        )
        require(
            LegacyLabelMatch.noteCaption(
                token: "8C", channel: "03", showFileName: true,
                wavName: "kick.wav", bmpName: "bg.png"
            ) == "8C",
            "numeric columns still draw the value label"
        )
        require(LegacyLabelMatch.isSoundChannel("11") && LegacyLabelMatch.isSoundChannel("01"),
                "A and B columns are sound")
        require(!LegacyLabelMatch.isSoundChannel("04") && !LegacyLabelMatch.isSoundChannel("03"),
                "BGA and BPM are not sound")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
