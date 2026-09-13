import Foundation

/// 对照 `EditorPersistent.vb` `XMLLoadLocale` / `XMLLoadLocaleMenu` / `LoadLocaleXML`，
/// 以及 `MainWindow.vb` `TBLangDef_Click` / `TBLangRefresh_Click`。
struct LegacyLocaleError: Error, Equatable {
    var message: String
}

struct LegacyLocalePack: Equatable {
    var name: String
    var path: String
    var texts: [String: String]
    var amps: [String: Int]
}

struct LegacyLocaleListing: Equatable {
    var name: String
    var path: String
}

struct LegacyLocaleScan: Equatable {
    var listings: [LegacyLocaleListing]
    var errors: [String]
}

enum LegacyLocaleMenuEntry: Equatable {
    case item(title: String, command: String, tooltip: String)
    case separator
}

enum LegacyLocale {
    static let fileSuffix = ".Lang.xml"
    static let rootName = "iBMSC.Locale"
    static let defaultTitle = "(Default)"
    static let refreshTitle = "Refresh"
    static let defaultCommand = "TBLangDef"
    static let refreshCommand = "TBLangRefresh"
    static let fileCommandPrefix = "TBLangFile:"
    static let defaultsKey = "IBMSNative.DispLang"
    static let defaultPostpone =
        "The preference will take effect on the next start-up of the program."

    /// Designer / `Strings.vb` 英文。缺元素时 `XMLLoadLocale` 不改这些。
    static let designerSaveOnExit = "Do you want to save changes?"
    static let designerSaveOnExit1 =
        "You should tell me if you want to save changes before closing the computer. -_,-"
    static let designerSaveOnExit2 =
        "You still need to tell me if you want to save changes even though you are closing the application with task manager. -_,-"
    static let designerLength = "Length"
    static let designerLongNote = "LongNote"
    static let designerHidden = "Hidden"
    static let designerError = "Error"
    static let designerPromptEnter = "Please enter a label."
    static let designerPromptEnterNumeric = "Please enter a value."
    static let designerPromptEnterBPM = "Please enter a BPM value."
    static let designerPromptEnterSTOP = "Please enter a STOP value."
    static let designerPromptEnterSCROLL = "Please enter a SCROLL value."
    static let designerInvalidLabel = "Invalid label."
    static let designerCannotFind = "Cannot find file {}."
    static let designerErr = "Error"
    static let designerSaveWarning = "Warning: "
    static let designerNoteOverlapError =
        "Note operlapping detected. Increasing Maximum Grid Partition will resolve this."
    static let designerBpmOverflowError = "Numbers of multi-byte BPMs has exceeded supported maximum: "
    static let designerStopOverflowError = "Numbers of STOPs has exceeded supported maximum: "
    static let designerScrollOverflowError = "Numbers of multi-byte SCROLLs has exceeded supported maximum: "
    static let designerSavedFileWillContainErrors = "The saved file will contain errors."

    enum SaveOverflowKind: Equatable {
        case bpm
        case stop
    }

    /// 已经会弹出来、已经会画出来的句子。缺的用英文。
    struct RuntimeStrings: Equatable {
        var saveOnExit: String
        var saveOnExit1: String
        var saveOnExit2: String
        var length: String
        var longNote: String
        var hidden: String
        var error: String
        var promptEnter: String
        var promptEnterNumeric: String
        var promptEnterBPM: String
        var promptEnterSTOP: String
        var promptEnterSCROLL: String
        var invalidLabel: String
        var cannotFind: String
        var err: String
        var saveWarning: String
        var noteOverlapError: String
        var bpmOverflowError: String
        var stopOverflowError: String
        var scrollOverflowError: String
        var savedFileWillContainErrors: String

        static let designer = RuntimeStrings(
            saveOnExit: LegacyLocale.designerSaveOnExit,
            saveOnExit1: LegacyLocale.designerSaveOnExit1,
            saveOnExit2: LegacyLocale.designerSaveOnExit2,
            length: LegacyLocale.designerLength,
            longNote: LegacyLocale.designerLongNote,
            hidden: LegacyLocale.designerHidden,
            error: LegacyLocale.designerError,
            promptEnter: LegacyLocale.designerPromptEnter,
            promptEnterNumeric: LegacyLocale.designerPromptEnterNumeric,
            promptEnterBPM: LegacyLocale.designerPromptEnterBPM,
            promptEnterSTOP: LegacyLocale.designerPromptEnterSTOP,
            promptEnterSCROLL: LegacyLocale.designerPromptEnterSCROLL,
            invalidLabel: LegacyLocale.designerInvalidLabel,
            cannotFind: LegacyLocale.designerCannotFind,
            err: LegacyLocale.designerErr,
            saveWarning: LegacyLocale.designerSaveWarning,
            noteOverlapError: LegacyLocale.designerNoteOverlapError,
            bpmOverflowError: LegacyLocale.designerBpmOverflowError,
            stopOverflowError: LegacyLocale.designerStopOverflowError,
            scrollOverflowError: LegacyLocale.designerScrollOverflowError,
            savedFileWillContainErrors: LegacyLocale.designerSavedFileWillContainErrors
        )

        /// 原文 `"Length = "`，把 Length 换成包里的词，等号两边各一个空格。
        var lengthPrefix: String { "\(length) = " }

        func lengthEquals(_ value: String) -> String {
            lengthPrefix + value
        }

        /// 双击 / 按列选提示。对照 `PanelEvents` `DoubleClickNoteIndex`。
        func doubleClickPrompt(channel: String) -> String {
            switch channel.uppercased() {
            case "03", "08":
                return promptEnterBPM
            case "09":
                return promptEnterSTOP
            case "SC":
                return promptEnterSCROLL
            default:
                return promptEnter
            }
        }

        /// 写入时值列。对照 `writeTiming` / `writeBmsonTiming`。
        func writeTimingPrompt(channel: String) -> String {
            switch channel.uppercased() {
            case "09":
                return promptEnterSTOP
            case "SC":
                return promptEnterSCROLL
            default:
                return promptEnterBPM
            }
        }

        /// 对照 `EditorRecent` `OpenRecent`：`Replace("{}")`。
        func cannotFindMessage(path: String) -> String {
            cannotFind.replacingOccurrences(of: "{}", with: path)
        }

        /// 对照 `ChartIO.SaveBMS` 重叠警告。公式与 `Legacy1296Write.overlapMessage` 相同。
        func overlapSaveMessage() -> String {
            saveWarning + "\n" + noteOverlapError + "\n" + savedFileWillContainErrors
        }

        /// 对照 `ChartIO.SaveBMS` BPM / STOP 超限。公式与 `Legacy1296Write.overflowMessage` 相同。
        func overflowSaveMessage(kind: LegacyLocale.SaveOverflowKind, count: Int, enabled: Bool) -> String? {
            let maximum = enabled ? 1295 : 255
            guard count > maximum else { return nil }
            let body = kind == .bpm ? bpmOverflowError : stopOverflowError
            return saveWarning + "\n" + body + "\(count) > \(maximum)\n" + savedFileWillContainErrors
        }

        /// 对照 `ChartIO.SaveBMS` SCROLL 超限。公式与 `Legacy1296Write.scrollOverflowMessage` 相同。
        func scrollOverflowSaveMessage(count: Int) -> String? {
            guard count > 1295 else { return nil }
            return saveWarning + "\n" + scrollOverflowError + "\(count) > 1295\n" + savedFileWillContainErrors
        }
    }

    enum ID {
        static let file = "locale.menu.file"
        static let fileNew = "locale.menu.file.new"
        static let fileOpen = "locale.menu.file.open"
        static let fileImportSM = "locale.menu.file.importSM"
        static let fileImportIBMSC = "locale.menu.file.importIBMSC"
        static let fileSave = "locale.menu.file.save"
        static let fileSaveAs = "locale.menu.file.saveAs"
        static let fileExportIBMSC = "locale.menu.file.exportIBMSC"
        static let edit = "locale.menu.edit"
        static let editUndo = "locale.menu.edit.undo"
        static let editRedo = "locale.menu.edit.redo"
        static let editCut = "locale.menu.edit.cut"
        static let editCopy = "locale.menu.edit.copy"
        static let editPaste = "locale.menu.edit.paste"
        static let editDelete = "locale.menu.edit.delete"
        static let editSelectAll = "locale.menu.edit.selectAll"
        static let editFind = "locale.menu.edit.find"
        static let editStat = "locale.menu.edit.stat"
        static let editTimeSelect = "locale.menu.edit.timeSelect"
        static let editSelect = "locale.menu.edit.select"
        static let editWrite = "locale.menu.edit.write"
        static let editMyO2 = "locale.menu.edit.myO2"
        static let view = "locale.menu.view"
        static let options = "locale.menu.options"
        static let optionsNT = "locale.menu.options.nt"
        static let optionsErrorCheck = "locale.menu.options.errorCheck"
        static let optionsPreviewOnClick = "locale.menu.options.previewOnClick"
        static let optionsShowFileName = "locale.menu.options.showFileName"
        static let optionsGeneral = "locale.menu.options.general"
        static let optionsVisual = "locale.menu.options.visual"
        static let optionsPlayer = "locale.menu.options.player"
        static let optionsLanguage = "locale.menu.options.language"
        static let optionsTheme = "locale.menu.options.theme"
        static let conversion = "locale.menu.conversion"
        static let preview = "locale.menu.preview"
        static let previewBegin = "locale.menu.preview.begin"
        static let previewHere = "locale.menu.preview.here"
        static let previewStop = "locale.menu.preview.stop"
    }

    /// 标识到 `iBMSC.Locale` 路径。缺元素时不改 Designer 文案。
    static let menuPaths: [String: String] = [
        ID.file: "Menu/File/Title",
        ID.fileNew: "Menu/File/New",
        ID.fileOpen: "Menu/File/Open",
        ID.fileImportSM: "Menu/File/ImportSM",
        ID.fileImportIBMSC: "Menu/File/ImportIBMSC",
        ID.fileSave: "Menu/File/Save",
        ID.fileSaveAs: "Menu/File/SaveAs",
        ID.fileExportIBMSC: "Menu/File/ExportIBMSC",
        ID.edit: "Menu/Edit/Title",
        ID.editUndo: "Menu/Edit/Undo",
        ID.editRedo: "Menu/Edit/Redo",
        ID.editCut: "Menu/Edit/Cut",
        ID.editCopy: "Menu/Edit/Copy",
        ID.editPaste: "Menu/Edit/Paste",
        ID.editDelete: "Menu/Edit/Delete",
        ID.editSelectAll: "Menu/Edit/SelectAll",
        ID.editFind: "Menu/Edit/Find",
        ID.editStat: "Menu/Edit/Stat",
        ID.editTimeSelect: "Menu/Edit/TimeSelectionTool",
        ID.editSelect: "Menu/Edit/SelectTool",
        ID.editWrite: "Menu/Edit/WriteTool",
        ID.editMyO2: "Menu/Edit/MyO2",
        ID.view: "Menu/View/Title",
        ID.options: "Menu/Options/Title",
        ID.optionsNT: "Menu/Options/NT",
        ID.optionsErrorCheck: "Menu/Options/ErrorCheck",
        ID.optionsPreviewOnClick: "Menu/Options/PreviewOnClick",
        ID.optionsShowFileName: "Menu/Options/ShowFileName",
        ID.optionsGeneral: "Menu/Options/GeneralOptions",
        ID.optionsVisual: "Menu/Options/VisualOptions",
        ID.optionsPlayer: "Menu/Options/PlayerOptions",
        ID.optionsLanguage: "Menu/Options/Language",
        ID.optionsTheme: "Menu/Options/Theme",
        ID.conversion: "Menu/Conversion",
        ID.preview: "Menu/Preview/Title",
        ID.previewBegin: "Menu/Preview/PlayBegin",
        ID.previewHere: "Menu/Preview/PlayHere",
        ID.previewStop: "Menu/Preview/PlayStop"
    ]

    private static let commandIDs: [String: String] = [
        "TBNTInput": ID.optionsNT,
        "TBErrorCheck": ID.optionsErrorCheck,
        "TBPreviewOnClick": ID.optionsPreviewOnClick,
        "TBShowFileName": ID.optionsShowFileName,
        "TBGOptions": ID.optionsGeneral,
        "TBVOptions": ID.optionsVisual,
        "TBPOptions": ID.optionsPlayer,
        "TBPlayB": ID.previewBegin,
        "TBPlay": ID.previewHere,
        "TBStop": ID.previewStop
    ]

    static func itemID(command: String) -> String? {
        commandIDs[command]
    }

    static func parse(url: URL) throws -> LegacyLocalePack {
        try parse(data: Data(contentsOf: url), path: url.path)
    }

    static func parse(data: Data, path: String) throws -> LegacyLocalePack {
        let document = try document(from: data)
        guard let root = document.rootElement(), root.name == rootName else {
            throw LegacyLocaleError(message: "missing iBMSC.Locale root")
        }
        let attributeName = root.attribute(forName: "Name")?.stringValue ?? ""
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        var texts: [String: String] = [:]
        var amps: [String: Int] = [:]
        collect(root, path: "", texts: &texts, amps: &amps)
        return LegacyLocalePack(
            name: attributeName.isEmpty ? fileName : attributeName,
            path: path,
            texts: texts,
            amps: amps
        )
    }

    /// `GetFiles("*.Lang.xml")`：后缀按字面匹配。坏文件记进 errors，不进列表。
    static func scan(directory: URL) -> LegacyLocaleScan {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else {
            return LegacyLocaleScan(listings: [], errors: [])
        }
        var listings: [LegacyLocaleListing] = []
        var errors: [String] = []
        for name in names.sorted() where name.hasSuffix(fileSuffix) {
            let url = directory.appendingPathComponent(name)
            do {
                let pack = try parse(url: url)
                listings.append(LegacyLocaleListing(name: pack.name, path: url.path))
            } catch {
                errors.append("\(url.path)\n\n\(error.localizedDescription)")
            }
        }
        return LegacyLocaleScan(listings: listings, errors: errors)
    }

    static func bundledDataDirectory(bundle: Bundle = .main) -> URL? {
        bundle.resourceURL?.appendingPathComponent("Data", isDirectory: true)
    }

    /// `XMLLoadLocaleMenu`：有 `amp` 就按 UTF-16 下标插入 `&`。
    static func menuRaw(_ pack: LegacyLocalePack, path: String) -> String? {
        guard let text = pack.texts[path] else { return nil }
        guard let amp = pack.amps[path] else { return text }
        return insertAmp(text, at: amp) ?? text
    }

    /// macOS 菜单不走 Windows 助记符，显示时去掉 `&`。
    static func menuDisplay(_ pack: LegacyLocalePack, path: String) -> String? {
        guard let raw = menuRaw(pack, path: path) else { return nil }
        return displayText(raw)
    }

    static func displayText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&", with: "")
    }

    static func text(_ pack: LegacyLocalePack, path: String) -> String? {
        pack.texts[path]
    }

    /// `XMLLoadLocale`：元素在才换；不在就保持 Designer 英文。
    static func overlay(_ pack: LegacyLocalePack?, path: String, fallback: String) -> String {
        guard let pack, let value = text(pack, path: path) else { return fallback }
        return value
    }

    static func runtime(_ pack: LegacyLocalePack?) -> RuntimeStrings {
        RuntimeStrings(
            saveOnExit: overlay(pack, path: "Messages/SaveOnExit", fallback: designerSaveOnExit),
            saveOnExit1: overlay(pack, path: "Messages/SaveOnExit1", fallback: designerSaveOnExit1),
            saveOnExit2: overlay(pack, path: "Messages/SaveOnExit2", fallback: designerSaveOnExit2),
            length: overlay(pack, path: "StatusBar/Length", fallback: designerLength),
            longNote: overlay(pack, path: "StatusBar/LongNote", fallback: designerLongNote),
            hidden: overlay(pack, path: "StatusBar/Hidden", fallback: designerHidden),
            error: overlay(pack, path: "StatusBar/Error", fallback: designerError),
            promptEnter: overlay(pack, path: "Messages/PromptEnter", fallback: designerPromptEnter),
            promptEnterNumeric: overlay(
                pack, path: "Messages/PromptEnterNumeric", fallback: designerPromptEnterNumeric
            ),
            promptEnterBPM: overlay(pack, path: "Messages/PromptEnterBPM", fallback: designerPromptEnterBPM),
            promptEnterSTOP: overlay(pack, path: "Messages/PromptEnterSTOP", fallback: designerPromptEnterSTOP),
            promptEnterSCROLL: overlay(
                pack, path: "Messages/PromptEnterSCROLL", fallback: designerPromptEnterSCROLL
            ),
            invalidLabel: overlay(pack, path: "Messages/InvalidLabel", fallback: designerInvalidLabel),
            cannotFind: overlay(pack, path: "Messages/CannotFind", fallback: designerCannotFind),
            err: overlay(pack, path: "Messages/Err", fallback: designerErr),
            saveWarning: overlay(pack, path: "Messages/SaveWarning", fallback: designerSaveWarning),
            noteOverlapError: overlay(
                pack, path: "Messages/NoteOverlapError", fallback: designerNoteOverlapError
            ),
            bpmOverflowError: overlay(
                pack, path: "Messages/BPMOverflowError", fallback: designerBpmOverflowError
            ),
            stopOverflowError: overlay(
                pack, path: "Messages/STOPOverflowError", fallback: designerStopOverflowError
            ),
            scrollOverflowError: overlay(
                pack, path: "Messages/SCROLLOverflowError", fallback: designerScrollOverflowError
            ),
            savedFileWillContainErrors: overlay(
                pack, path: "Messages/SavedFileWillContainErrors", fallback: designerSavedFileWillContainErrors
            )
        )
    }

    /// 元素在包里才覆盖；缺的保持 Designer 原文。
    static func overlayTitles(_ pack: LegacyLocalePack, onto designer: [String: String]) -> [String: String] {
        var result = designer
        for (identifier, path) in menuPaths {
            if let title = menuDisplay(pack, path: path) {
                result[identifier] = title
            }
        }
        return result
    }

    static func languageMenuEntries(listings: [LegacyLocaleListing]) -> [LegacyLocaleMenuEntry] {
        var entries: [LegacyLocaleMenuEntry] = [
            .item(title: defaultTitle, command: defaultCommand, tooltip: ""),
            .item(title: refreshTitle, command: refreshCommand, tooltip: "")
        ]
        entries.append(.separator)
        for listing in listings {
            entries.append(
                .item(title: listing.name, command: fileCommand(path: listing.path), tooltip: listing.path)
            )
        }
        return entries
    }

    static func fileCommand(path: String) -> String {
        fileCommandPrefix + path
    }

    static func path(fromFileCommand command: String) -> String? {
        guard command.hasPrefix(fileCommandPrefix) else { return nil }
        let path = String(command.dropFirst(fileCommandPrefix.count))
        return path.isEmpty ? nil : path
    }

    /// 原版 `DispLang` 是相对 exe 的 `Data\文件名`。这里统一成 `Data/文件名`。
    static func relativeName(path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if let range = normalized.range(of: "/Data/", options: .backwards) {
            return "Data/" + String(normalized[range.upperBound...])
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func resolve(relative: String, dataDirectory: URL) -> URL {
        let name = URL(fileURLWithPath: relative.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
        return dataDirectory.appendingPathComponent(name)
    }

    static func savedRelativeName(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: defaultsKey) ?? ""
    }

    static func saveRelativeName(_ name: String, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: defaultsKey)
        // 原有语言菜单仍由 MainWindowController 驱动。同步原生界面的选择，
        // 首次启动则由 AppDelegate 设为简体中文。
        defaults.set(name.isEmpty ? "en" : "legacy", forKey: "IBMSNative.NativeLanguage")
    }

    static func insertAmp(_ text: String, at amp: Int) -> String? {
        let units = Array(text.utf16)
        guard amp >= 0, amp <= units.count else { return nil }
        var result = units
        result.insert(38, at: amp)
        return String(utf16CodeUnits: result, count: result.count)
    }

    private static func document(from data: Data) throws -> XMLDocument {
        do {
            return try XMLDocument(data: data, options: [])
        } catch {
            let converted = try transcodeToUTF8(data)
            return try XMLDocument(data: converted, options: [])
        }
    }

    private static func transcodeToUTF8(_ data: Data) throws -> Data {
        let declared = encodingName(in: data)
        guard !declared.isEmpty else {
            throw LegacyLocaleError(message: "unable to parse locale XML")
        }
        let cf = CFStringConvertIANACharSetNameToEncoding(declared as CFString)
        guard cf != kCFStringEncodingInvalidId else {
            throw LegacyLocaleError(message: "unsupported locale encoding \(declared)")
        }
        let ns = CFStringConvertEncodingToNSStringEncoding(cf)
        guard let text = String(data: data, encoding: String.Encoding(rawValue: ns)),
              let utf8 = text.data(using: .utf8) else {
            throw LegacyLocaleError(message: "unable to decode locale as \(declared)")
        }
        return utf8
    }

    /// 声明在 ASCII 里，UTF-16 文件也能从 BOM 后读到 `encoding=`。
    private static func encodingName(in data: Data) -> String {
        let head: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            head = String(data: data.prefix(240), encoding: .utf16) ?? ""
        } else {
            head = String(data: data.prefix(120), encoding: .utf8)
                ?? String(data: data.prefix(120), encoding: .isoLatin1)
                ?? ""
        }
        guard let range = head.range(of: "encoding=\"", options: .caseInsensitive) else { return "" }
        let after = head[range.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return "" }
        return String(after[..<end])
    }

    private static func collect(
        _ element: XMLElement,
        path: String,
        texts: inout [String: String],
        amps: inout [String: Int]
    ) {
        let children = (element.children ?? []).compactMap { $0 as? XMLElement }
        if children.isEmpty {
            guard !path.isEmpty else { return }
            texts[path] = element.stringValue ?? ""
            if let ampText = element.attribute(forName: "amp")?.stringValue, let amp = Int(ampText) {
                amps[path] = amp
            }
            return
        }
        for child in children {
            guard let name = child.name else { continue }
            let next = path.isEmpty ? name : path + "/" + name
            collect(child, path: next, texts: &texts, amps: &amps)
        }
    }
}
