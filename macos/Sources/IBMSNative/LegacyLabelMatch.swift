import Foundation

/// 一条待比较的音符。`id` 只用来放进集合，不参与标签比较。
struct LegacyLabelCandidate: Hashable {
    let id: String
    let token: String
    let fileName: String
}

/// 原版 `PanelEvents.IsLabelMatch` / `SelectAllWithHoveredNoteLabel`。
///
/// 原版勾选 `TBShowFileName` 时，用 `hWAV(Value/10000)` 比文件名。
/// 没有文件名时回退到标签。不要把两个空文件名当成全表相同。
enum LegacyLabelMatch {
    /// `EditorColumns.IsColumnSound`：A / B / Hidden / Mine / Long 是声音列；BPM / STOP / SCROLL / BGA 不是。
    static func isSoundChannel(_ channel: String) -> Bool {
        switch channel.uppercased() {
        case "03", "08", "09", "SC", "04", "06", "07":
            return false
        default:
            return true
        }
    }

    /// `Path.GetFileNameWithoutExtension`：只要最后一段名字，去掉最后一个点后面的扩展名。
    static func fileNameWithoutExtension(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = maxIndex(trimmed.lastIndex(of: "/"), trimmed.lastIndex(of: "\\"))
        let name = cut.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// `DrawNote` / `DrawNoteNT` 画在音符上的字。数值列仍画原来的标签。
    static func noteCaption(
        token: String,
        channel: String,
        showFileName: Bool,
        wavName: String,
        bmpName: String
    ) -> String {
        if ["03", "08", "09", "SC"].contains(channel.uppercased()) {
            return token
        }
        guard showFileName else { return token }
        let stored = isSoundChannel(channel) ? wavName : bmpName
        if stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token
        }
        return fileNameWithoutExtension(stored)
    }

    private static func maxIndex(_ lhs: String.Index?, _ rhs: String.Index?) -> String.Index? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left > right ? left : right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    /// `showFileName` 且两边文件名都非空：比文件名。
    /// 其余情况比 token。
    static func isLabelMatch(
        hoverToken: String,
        candidateToken: String,
        showFileName: Bool,
        hoverFileName: String,
        candidateFileName: String
    ) -> Bool {
        if showFileName {
            let hoverName = hoverFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidateName = candidateFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !hoverName.isEmpty && !candidateName.isEmpty {
                return hoverName == candidateName
            }
        }
        return hoverToken == candidateToken
    }

    /// 应画 `kMouseOver` 框的全部音符，含悬停自己。
    static func matchingNotes(
        hoverToken: String,
        hoverFileName: String,
        candidates: [LegacyLabelCandidate],
        showFileName: Bool
    ) -> [LegacyLabelCandidate] {
        candidates.filter { candidate in
            isLabelMatch(
                hoverToken: hoverToken,
                candidateToken: candidate.token,
                showFileName: showFileName,
                hoverFileName: hoverFileName,
                candidateFileName: candidate.fileName
            )
        }
    }

    /// 加选是 OR：匹配的标成已选，已选的不要清掉。
    static func selectingAdds<T: Hashable>(
        selected: Set<T>,
        matching: [T]
    ) -> Set<T> {
        selected.union(matching)
    }

    /// 原版 `ModifierMultiselectActive`：Shift 并且 Ctrl。
    /// 选择模式才是同标签多选；写入模式同一组键是地雷，不要混用。
    static func modifierMultiselectActive(control: Bool, shift: Bool) -> Bool {
        control && shift
    }

    /// 选择模式左键。对照 `OnSelectModeLeftClick` / `PMainInMouseUp`。
    enum SelectClick: Equatable {
        case toggle
        case addMatchingLabel
        case replace
        case marqueeKeep
        case marqueeClear
    }

    static func selectClick(control: Bool, shift: Bool, hitNote: Bool) -> SelectClick {
        if modifierMultiselectActive(control: control, shift: shift) {
            return hitNote ? .addMatchingLabel : .marqueeKeep
        }
        if control {
            return hitNote ? .toggle : .marqueeKeep
        }
        return hitNote ? .replace : .marqueeClear
    }

    /// `OnDuplicateSelectedNotes`：Ctrl 且不是 Ctrl+Shift，拖出位移后复制已选。
    static func ctrlDragCopies(control: Bool, shift: Bool, didDrag: Bool) -> Bool {
        control && !shift && didDrag
    }

    /// 原版 `ModifierMultiselectActive()` 且 `Keys.A` 且 `KMouseOver <> -1`。
    /// 只有 Control、没有 Shift 走 Select All，不是这一行。
    /// 带 Command 不处理，避免抢 `Command+A`。
    static func hoverASelects(control: Bool, shift: Bool, command: Bool, hasHover: Bool) -> Bool {
        control && shift && !command && hasHover
    }

    /// 松手时 `Notes(i).Selected = Not Selected`，只动点中的那一条。
    static func toggling<T: Hashable>(selected: Set<T>, item: T) -> Set<T> {
        var next = selected
        if next.contains(item) {
            next.remove(item)
        } else {
            next.insert(item)
        }
        return next
    }
}

/// 原版 `PMainInPreviewKeyDown`：只要 Control，不要 Alt，不要 Shift。
/// macOS：原文 Ctrl 对应 Control。带 Command 不处理，避免抢菜单。
enum LegacyCtrlEdit {
    enum Action: Equatable {
        case undo
        case redo
        case cut
        case copy
        case paste
        case selectAll
        case find
        case statistics
    }

    static func action(
        keyCode: UInt16,
        control: Bool,
        shift: Bool,
        option: Bool,
        command: Bool
    ) -> Action? {
        guard control, !shift, !option, !command else { return nil }
        switch keyCode {
        case 6: return .undo
        case 16: return .redo
        case 7: return .cut
        case 8: return .copy
        case 9: return .paste
        case 0: return .selectAll
        case 3: return .find
        case 17: return .statistics
        default: return nil
        }
    }
}
