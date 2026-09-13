import Foundation

/// 对照 `MainWindow.designer.vb` 顶栏 Options / Conversions / Preview。
enum LegacyChromeMenu {
    enum PreviewCommand: Equatable {
        case playFromBeginning
        case playFromHere
        case stop
    }

    enum Entry: Equatable {
        case item(title: String, command: String, shortcut: String?, checkable: Bool, defaultChecked: Bool)
        case separator
        case submenu(String)
    }

    static let options: [Entry] = [
        .item(
            title: "LN Input Style - NT/BMSE",
            command: "TBNTInput",
            shortcut: "F8",
            checkable: true,
            defaultChecked: true
        ),
        .item(title: "Error Check", command: "TBErrorCheck", shortcut: nil, checkable: true, defaultChecked: true),
        .item(title: "Preview on Click", command: "TBPreviewOnClick", shortcut: nil, checkable: true, defaultChecked: true),
        .item(
            title: "Show File Name on Notes",
            command: "TBShowFileName",
            shortcut: nil,
            checkable: true,
            defaultChecked: false
        ),
        .separator,
        .item(title: "General Options", command: "TBGOptions", shortcut: nil, checkable: false, defaultChecked: false),
        .item(title: "Visual Options", command: "TBVOptions", shortcut: nil, checkable: false, defaultChecked: false),
        .item(title: "Player Options", command: "TBPOptions", shortcut: nil, checkable: false, defaultChecked: false),
        .submenu("Language"),
        .submenu("Theme")
    ]

    static let conversions: [Entry] = [
        .item(title: "→ Long Note", command: "POBLong", shortcut: nil, checkable: false, defaultChecked: false),
        .item(title: "→ Short Note", command: "POBShort", shortcut: nil, checkable: false, defaultChecked: false),
        .item(
            title: "Long Note ↔ Short Note",
            command: "POBLongShort",
            shortcut: nil,
            checkable: false,
            defaultChecked: false
        ),
        .separator,
        .item(title: "→ Hidden Note", command: "POBHidden", shortcut: nil, checkable: false, defaultChecked: false),
        .item(title: "→ Visible Note", command: "POBVisible", shortcut: nil, checkable: false, defaultChecked: false),
        .item(
            title: "Hidden Note ↔ Visible Note",
            command: "POBHiddenVisible",
            shortcut: nil,
            checkable: false,
            defaultChecked: false
        ),
        .separator,
        .item(title: "Modify Labels", command: "POBModify", shortcut: nil, checkable: false, defaultChecked: false),
        .item(title: "Mirror", command: "POBMirror", shortcut: nil, checkable: false, defaultChecked: false)
    ]

    static let preview: [Entry] = [
        .item(
            title: "Play from beginning",
            command: "TBPlayB",
            shortcut: "F5",
            checkable: false,
            defaultChecked: false
        ),
        .item(title: "Play from here", command: "TBPlay", shortcut: "F6", checkable: false, defaultChecked: false),
        .item(title: "Stop", command: "TBStop", shortcut: "F7", checkable: false, defaultChecked: false)
    ]

    static let languageItems: [(title: String, command: String)] = [
        ("(Default)", "TBLangDef"),
        ("Refresh", "TBLangRefresh")
    ]

    /// `POBLong` / `POBLongShort`：`NTInput` 打开时禁用。
    static func conversionEnabled(command: String, ntInput: Bool) -> Bool {
        switch command {
        case "POBLong", "POBLongShort":
            return !ntInput
        default:
            return true
        }
    }

    static func previewCommand(toolbar name: String) -> PreviewCommand? {
        switch name {
        case "TBPlayB":
            return .playFromBeginning
        case "TBPlay":
            return .playFromHere
        case "TBStop":
            return .stop
        default:
            return nil
        }
    }

    /// 内置预览从哪一拍开始。停止没有起点。
    static func playFromBeat(_ command: PreviewCommand, pointerBeat: Double) -> Double? {
        switch command {
        case .playFromBeginning:
            return 0
        case .playFromHere:
            return pointerBeat
        case .stop:
            return nil
        }
    }

    static func titles(of entries: [Entry]) -> [String] {
        entries.compactMap { entry in
            switch entry {
            case .item(let title, _, _, _, _):
                return title
            case .submenu(let title):
                return title
            case .separator:
                return nil
            }
        }
    }
}
