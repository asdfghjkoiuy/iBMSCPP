import Foundation

@main
struct LegacyLocaleTests {
    static func main() {
        testEnglishNameAndAmp()
        testChineseEntitiesStripAmp()
        testJapaneseAmpInsert()
        testKoreanEUCName()
        testMissingElementLeavesDesigner()
        testEmptyNameUsesFileName()
        testScanFindsFourPacks()
        testScanIgnoresWrongSuffix()
        testLanguageMenuEntries()
        testFileCommandRoundtrip()
        testRelativeNameAndResolve()
        testSavedPreference()
        testPostponeText()
        testMessageAndStatusText()
        testRuntimeFromPacks()
        testRuntimeMissingFallsBack()
        testDialogMessageText()
        testDialogRuntimeFromPacks()
        testDialogRuntimeMissingFallsBack()
        testDialogDoubleClickPrompts()
        testSaveWarningText()
        testSaveRuntimeFromPacks()
        testSaveRuntimeMissingFallsBack()
        testSaveMessageComposition()
        print("LegacyLocaleTests passed")
    }

    /// `eng.Lang.xml`：`Name`，以及 `amp="0"` / `amp="5"`。
    private static func testEnglishNameAndAmp() {
        let pack = try! LegacyLocale.parse(url: langURL("eng.Lang.xml"))
        require(pack.name == "English by Doaz", "eng Name")
        require(LegacyLocale.menuRaw(pack, path: "Menu/File/Title") == "&File", "amp 0 inserts before File")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/Title") == "File", "display strips &")
        require(LegacyLocale.menuRaw(pack, path: "Menu/File/SaveAs") == "Save &As...", "amp 5 is As")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/SaveAs") == "Save As...", "Save As display")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/New") == "New", "New")
    }

    /// `chs.Lang.xml`：标题写在正文里，`&amp;` 解码后再去掉 `&`。
    private static func testChineseEntitiesStripAmp() {
        let pack = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        require(pack.name == "简体中文 by Doaz", "chs Name")
        require(LegacyLocale.menuRaw(pack, path: "Menu/File/Title") == "文件 (&F)", "chs File keeps &")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/Title") == "文件 (F)", "chs File display")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/New") == "新建 (N)", "chs New")
        require(LegacyLocale.text(pack, path: "None") == "无", "chs None")
    }

    /// `jpn.Lang.xml`：`amp="6"` 插在 `(` 前面，对照 `String.Insert`。
    private static func testJapaneseAmpInsert() {
        let pack = try! LegacyLocale.parse(url: langURL("jpn.Lang.xml"))
        require(pack.name == "日本語 by Nekokan", "jpn Name")
        require(LegacyLocale.menuRaw(pack, path: "Menu/File/Title") == "ファイル (&F)", "jpn amp 6")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/Title") == "ファイル (F)", "jpn display")
    }

    /// `kor.Lang.xml` 声明 `euc-kr`，不是 UTF-16。
    private static func testKoreanEUCName() {
        let pack = try! LegacyLocale.parse(url: langURL("kor.Lang.xml"))
        require(pack.name == "한국어 by MusicGameLAB", "kor Name")
        require(
            LegacyLocale.text(pack, path: "Messages/PreferencePostpone") == "이 설정은 다시 시작할 때 적용됩니다.",
            "kor postpone"
        )
    }

    /// `XMLLoadLocaleMenu`：元素不在就不改。
    private static func testMissingElementLeavesDesigner() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC.Locale Name="Partial">
          <Menu>
            <File>
              <Title amp="0">File</Title>
            </File>
          </Menu>
        </iBMSC.Locale>
        """
        let pack = try! LegacyLocale.parse(data: Data(xml.utf8), path: "/tmp/partial.Lang.xml")
        let designer = [
            LegacyLocale.ID.file: "File",
            LegacyLocale.ID.fileNew: "New",
            LegacyLocale.ID.fileOpen: "Open…"
        ]
        let overlaid = LegacyLocale.overlayTitles(pack, onto: designer)
        require(overlaid[LegacyLocale.ID.file] == "File", "present Title is applied")
        require(overlaid[LegacyLocale.ID.fileNew] == "New", "missing New stays")
        require(overlaid[LegacyLocale.ID.fileOpen] == "Open…", "missing Open stays")
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/New") == nil, "missing path is nil")
    }

    /// `LoadLocaleXML`：`Name` 为空就用文件名。
    private static func testEmptyNameUsesFileName() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC.Locale Name="">
          <OK>OK</OK>
        </iBMSC.Locale>
        """
        let pack = try! LegacyLocale.parse(data: Data(xml.utf8), path: "/tmp/empty.Lang.xml")
        require(pack.name == "empty.Lang.xml", "empty Name uses file name")
    }

    /// Refresh 扫目录里的 `*.Lang.xml`。
    private static func testScanFindsFourPacks() {
        let scan = LegacyLocale.scan(directory: langDirectory())
        require(scan.errors.isEmpty, "shipped packs parse")
        let names = Set(scan.listings.map(\.name))
        require(names.contains("English by Doaz"), "eng listed")
        require(names.contains("简体中文 by Doaz"), "chs listed")
        require(names.contains("日本語 by Nekokan"), "jpn listed")
        require(names.contains("한국어 by MusicGameLAB"), "kor listed")
        require(scan.listings.count == 4, "four shipped packs")
    }

    /// 字面后缀是 `.Lang.xml`，`foo.xml` 和 `bar.lang.xml` 不算。
    private static func testScanIgnoresWrongSuffix() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("IBMSNativeLocaleScan-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try! Data("<iBMSC.Locale Name=\"Skip\"><OK>x</OK></iBMSC.Locale>".utf8)
            .write(to: root.appendingPathComponent("foo.xml"))
        try! Data("<iBMSC.Locale Name=\"Lower\"><OK>x</OK></iBMSC.Locale>".utf8)
            .write(to: root.appendingPathComponent("bar.lang.xml"))
        try! Data("<iBMSC.Locale Name=\"Keep\"><OK>x</OK></iBMSC.Locale>".utf8)
            .write(to: root.appendingPathComponent("ok.Lang.xml"))
        let scan = LegacyLocale.scan(directory: root)
        require(scan.listings.map(\.name) == ["Keep"], "only .Lang.xml is listed")
    }

    /// 菜单固定是 (Default)、Refresh、分隔，再接包名。
    private static func testLanguageMenuEntries() {
        let listings = [
            LegacyLocaleListing(name: "English by Doaz", path: "/Data/eng.Lang.xml")
        ]
        let entries = LegacyLocale.languageMenuEntries(listings: listings)
        require(entries.count == 4, "two fixed, separator, one pack")
        guard case .item(let defaultTitle, let defaultCommand, _) = entries[0] else {
            fputs("Default item missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(defaultTitle == "(Default)" && defaultCommand == "TBLangDef", "Default")
        guard case .item(let refreshTitle, let refreshCommand, _) = entries[1] else {
            fputs("Refresh item missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(refreshTitle == "Refresh" && refreshCommand == "TBLangRefresh", "Refresh")
        guard case .separator = entries[2] else {
            fputs("separator missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        guard case .item(let name, let command, let tooltip) = entries[3] else {
            fputs("pack item missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        require(name == "English by Doaz", "pack title is Name")
        require(command == "TBLangFile:/Data/eng.Lang.xml", "pack command")
        require(tooltip == "/Data/eng.Lang.xml", "tooltip is full path")
    }

    private static func testFileCommandRoundtrip() {
        let command = LegacyLocale.fileCommand(path: "/tmp/chs.Lang.xml")
        require(LegacyLocale.path(fromFileCommand: command) == "/tmp/chs.Lang.xml", "roundtrip")
        require(LegacyLocale.path(fromFileCommand: "TBLangRefresh") == nil, "other commands stay nil")
    }

    /// 保存成 `Data/文件名`，读回时只取文件名再拼目录。
    private static func testRelativeNameAndResolve() {
        require(
            LegacyLocale.relativeName(path: "/App/Contents/Resources/Data/chs.Lang.xml") == "Data/chs.Lang.xml",
            "relative from Data"
        )
        require(LegacyLocale.relativeName(path: #"C:\app\Data\eng.Lang.xml"#) == "Data/eng.Lang.xml", "backslash")
        let directory = URL(fileURLWithPath: "/bundle/Data", isDirectory: true)
        require(
            LegacyLocale.resolve(relative: "Data\\jpn.Lang.xml", dataDirectory: directory).path
                == "/bundle/Data/jpn.Lang.xml",
            "resolve strips prefix"
        )
    }

    /// Default 把 `DispLang` 写成空串，下次启动不再加载包。
    private static func testSavedPreference() {
        let suite = "IBMSNative.LocaleTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fputs("defaults suite missing\n", stderr)
            exit(EXIT_FAILURE)
        }
        defaults.removePersistentDomain(forName: suite)
        require(LegacyLocale.savedRelativeName(defaults: defaults).isEmpty, "starts empty")
        LegacyLocale.saveRelativeName("Data/chs.Lang.xml", defaults: defaults)
        require(LegacyLocale.savedRelativeName(defaults: defaults) == "Data/chs.Lang.xml", "remembers pack")
        LegacyLocale.saveRelativeName("", defaults: defaults)
        require(LegacyLocale.savedRelativeName(defaults: defaults).isEmpty, "Default clears")
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testPostponeText() {
        let pack = try! LegacyLocale.parse(url: langURL("eng.Lang.xml"))
        require(
            LegacyLocale.text(pack, path: "Messages/PreferencePostpone") == LegacyLocale.defaultPostpone,
            "eng postpone matches Strings.vb"
        )
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        require(
            LegacyLocale.text(chs, path: "Messages/PreferencePostpone") == "设置将在下次启动程序时生效。",
            "chs postpone"
        )
    }

    /// `LoadLocale`：已经会弹、已经会画的 7 句。
    private static func testMessageAndStatusText() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        require(LegacyLocale.text(chs, path: "Messages/SaveOnExit") == "是否保存更改？", "chs SaveOnExit")
        require(
            LegacyLocale.text(chs, path: "Messages/SaveOnExit1") == "关机之前你得告诉我你要保存不 -_,-",
            "chs SaveOnExit1 keeps -_,-"
        )
        require(LegacyLocale.text(chs, path: "StatusBar/Length") == "长度", "chs Length")
        require(LegacyLocale.text(chs, path: "StatusBar/LongNote") == "面条", "chs LongNote")
        require(LegacyLocale.text(chs, path: "StatusBar/Hidden") == "隐藏", "chs Hidden")
        require(LegacyLocale.text(chs, path: "StatusBar/Error") == "错误", "chs Error")

        let jpn = try! LegacyLocale.parse(url: langURL("jpn.Lang.xml"))
        require(
            LegacyLocale.text(jpn, path: "Messages/SaveOnExit") == "データは変更されています。保存しますか。",
            "jpn SaveOnExit"
        )
        require(LegacyLocale.text(jpn, path: "StatusBar/Length") == "長さ", "jpn Length")
        require(LegacyLocale.text(jpn, path: "StatusBar/LongNote") == "ロングノート", "jpn LongNote")
        require(LegacyLocale.text(jpn, path: "StatusBar/Hidden") == "不可視オブジェ", "jpn Hidden")
        require(LegacyLocale.text(jpn, path: "StatusBar/Error") == "エラー", "jpn Error")
    }

    private static func testRuntimeFromPacks() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        let runtime = LegacyLocale.runtime(chs)
        require(runtime.saveOnExit == "是否保存更改？", "runtime chs SaveOnExit")
        require(runtime.length == "长度", "runtime chs Length")
        require(runtime.lengthEquals("192") == "长度 = 192", "Length = becomes 长度 = ")
        require(runtime.longNote == "面条", "runtime chs LongNote")
        require(runtime.hidden == "隐藏", "runtime chs Hidden")
        require(runtime.error == "错误", "runtime chs Error")
        require(
            runtime.saveOnExit1 == "关机之前你得告诉我你要保存不 -_,-",
            "runtime chs SaveOnExit1"
        )
    }

    /// 缺元素或没有包：保持 Designer 英文。只有 File 的残包也一样。
    private static func testRuntimeMissingFallsBack() {
        let empty = LegacyLocale.runtime(nil)
        require(empty.saveOnExit == "Do you want to save changes?", "nil pack SaveOnExit")
        require(empty.length == "Length", "nil pack Length")
        require(empty.longNote == "LongNote", "nil pack LongNote")
        require(empty.hidden == "Hidden", "nil pack Hidden")
        require(empty.error == "Error", "nil pack Error")
        require(empty.lengthEquals("192") == "Length = 192", "nil pack Length = ")

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC.Locale Name="FileOnly">
          <Menu>
            <File>
              <Title amp="0">File</Title>
            </File>
          </Menu>
        </iBMSC.Locale>
        """
        let pack = try! LegacyLocale.parse(data: Data(xml.utf8), path: "/tmp/file-only.Lang.xml")
        let runtime = LegacyLocale.runtime(pack)
        require(runtime.saveOnExit == "Do you want to save changes?", "File-only SaveOnExit stays English")
        require(runtime.length == "Length", "File-only Length stays English")
        require(runtime.longNote == "LongNote", "File-only LongNote stays English")
        require(
            LegacyLocale.overlay(pack, path: "Messages/SaveOnExit", fallback: LegacyLocale.designerSaveOnExit)
                == LegacyLocale.designerSaveOnExit,
            "overlay missing path keeps fallback"
        )
        require(LegacyLocale.menuDisplay(pack, path: "Menu/File/Title") == "File", "File-only still overlays File")
    }

    /// `LoadLocale`：已经会弹的输入框 / 非法标签 / 最近文件找不到。
    private static func testDialogMessageText() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        require(LegacyLocale.text(chs, path: "Messages/PromptEnter") == "请输入一个标签。", "chs PromptEnter")
        require(LegacyLocale.text(chs, path: "Messages/PromptEnterNumeric") == "请输入一个值。", "chs PromptEnterNumeric")
        require(LegacyLocale.text(chs, path: "Messages/PromptEnterBPM") == "请输入变速值。", "chs PromptEnterBPM")
        require(LegacyLocale.text(chs, path: "Messages/PromptEnterSTOP") == "请输入STOP值。", "chs PromptEnterSTOP")
        require(LegacyLocale.text(chs, path: "Messages/InvalidLabel") == "标签无效。", "chs InvalidLabel")
        require(LegacyLocale.text(chs, path: "Messages/CannotFind") == "找不到文件 {}。", "chs CannotFind")
        require(LegacyLocale.text(chs, path: "Messages/Err") == "错误", "chs Err")
        require(LegacyLocale.text(chs, path: "Messages/PromptEnterSCROLL") == nil, "chs has no SCROLL element")

        let jpn = try! LegacyLocale.parse(url: langURL("jpn.Lang.xml"))
        require(
            LegacyLocale.text(jpn, path: "Messages/PromptEnter") == "定義番号を入力してください。",
            "jpn PromptEnter"
        )
        require(
            LegacyLocale.text(jpn, path: "Messages/PromptEnterBPM") == "曲のテンポを入力してください。",
            "jpn PromptEnterBPM"
        )
        require(
            LegacyLocale.text(jpn, path: "Messages/PromptEnterSCROLL") == "スクロール速度を入力してください。",
            "jpn PromptEnterSCROLL"
        )
        require(LegacyLocale.text(jpn, path: "Messages/InvalidLabel") == "無効な定義番号です。", "jpn InvalidLabel")
        require(
            LegacyLocale.text(jpn, path: "Messages/CannotFind") == "{} が見つかりません。",
            "jpn CannotFind keeps spaces around {}"
        )
    }

    private static func testDialogRuntimeFromPacks() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        let runtime = LegacyLocale.runtime(chs)
        require(runtime.promptEnter == "请输入一个标签。", "runtime chs PromptEnter")
        require(runtime.promptEnterNumeric == "请输入一个值。", "runtime chs PromptEnterNumeric")
        require(runtime.promptEnterBPM == "请输入变速值。", "runtime chs PromptEnterBPM")
        require(runtime.promptEnterSTOP == "请输入STOP值。", "runtime chs PromptEnterSTOP")
        require(runtime.invalidLabel == "标签无效。", "runtime chs InvalidLabel")
        require(runtime.cannotFind == "找不到文件 {}。", "runtime chs CannotFind")
        require(runtime.err == "错误", "runtime chs Err")
        require(
            runtime.promptEnterSCROLL == "Please enter a SCROLL value.",
            "runtime chs SCROLL falls back to English"
        )
        require(
            runtime.cannotFindMessage(path: "gone.bms") == "找不到文件 gone.bms。",
            "runtime chs CannotFind replaces {}"
        )

        let jpn = try! LegacyLocale.parse(url: langURL("jpn.Lang.xml"))
        let jpnRuntime = LegacyLocale.runtime(jpn)
        require(
            jpnRuntime.cannotFindMessage(path: "song.bms") == "song.bms が見つかりません。",
            "runtime jpn CannotFind replaces {}"
        )
        require(
            jpnRuntime.doubleClickPrompt(channel: "SC") == "スクロール速度を入力してください。",
            "runtime jpn SC double-click"
        )
    }

    private static func testDialogRuntimeMissingFallsBack() {
        let empty = LegacyLocale.runtime(nil)
        require(empty.promptEnter == "Please enter a label.", "nil pack PromptEnter")
        require(empty.promptEnterNumeric == "Please enter a value.", "nil pack PromptEnterNumeric")
        require(empty.promptEnterBPM == "Please enter a BPM value.", "nil pack PromptEnterBPM")
        require(empty.promptEnterSTOP == "Please enter a STOP value.", "nil pack PromptEnterSTOP")
        require(empty.promptEnterSCROLL == "Please enter a SCROLL value.", "nil pack PromptEnterSCROLL")
        require(empty.invalidLabel == "Invalid label.", "nil pack InvalidLabel")
        require(empty.cannotFind == "Cannot find file {}.", "nil pack CannotFind")
        require(empty.err == "Error", "nil pack Err")

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC.Locale Name="FileOnly">
          <Menu>
            <File>
              <Title amp="0">File</Title>
            </File>
          </Menu>
        </iBMSC.Locale>
        """
        let pack = try! LegacyLocale.parse(data: Data(xml.utf8), path: "/tmp/file-only.Lang.xml")
        let runtime = LegacyLocale.runtime(pack)
        require(runtime.promptEnter == "Please enter a label.", "File-only PromptEnter stays English")
        require(runtime.invalidLabel == "Invalid label.", "File-only InvalidLabel stays English")
        require(runtime.cannotFind == "Cannot find file {}.", "File-only CannotFind stays English")
    }

    /// `LoadLocale`：File → Save / Save As 已经会弹的重叠 / 超限警告。
    private static func testSaveWarningText() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        require(LegacyLocale.text(chs, path: "Messages/SaveWarning") == "警告：", "chs SaveWarning")
        require(
            LegacyLocale.text(chs, path: "Messages/NoteOverlapError") == "检测到Note重叠。请增加BMS最大格线设置。",
            "chs NoteOverlapError"
        )
        require(
            LegacyLocale.text(chs, path: "Messages/BPMOverflowError") == "多字节 BPM 数量已经超过上限：",
            "chs BPMOverflowError"
        )
        require(
            LegacyLocale.text(chs, path: "Messages/STOPOverflowError") == "多字节 STOP 数量已经超过上限：",
            "chs STOPOverflowError"
        )
        require(
            LegacyLocale.text(chs, path: "Messages/SavedFileWillContainErrors") == "文件将无法正确保存。",
            "chs SavedFileWillContainErrors"
        )
        require(LegacyLocale.text(chs, path: "Messages/SCROLLOverflowError") == nil, "chs has no SCROLL element")

        let jpn = try! LegacyLocale.parse(url: langURL("jpn.Lang.xml"))
        require(LegacyLocale.text(jpn, path: "Messages/SaveWarning") == "警告：", "jpn SaveWarning")
        require(
            LegacyLocale.text(jpn, path: "Messages/NoteOverlapError")
                == "オブジェの重なりがあります。最大 Grid を大きくすると解決するかもしれません。",
            "jpn NoteOverlapError"
        )
        require(
            LegacyLocale.text(jpn, path: "Messages/SCROLLOverflowError")
                == "SCROLL の数が使用できる最大値を超えています。：",
            "jpn SCROLLOverflowError"
        )
        require(
            LegacyLocale.text(jpn, path: "Messages/SavedFileWillContainErrors") == "保存するファイルにエラーがあります。",
            "jpn SavedFileWillContainErrors"
        )
    }

    private static func testSaveRuntimeFromPacks() {
        let chs = try! LegacyLocale.parse(url: langURL("chs.Lang.xml"))
        let runtime = LegacyLocale.runtime(chs)
        require(runtime.saveWarning == "警告：", "runtime chs SaveWarning")
        require(
            runtime.noteOverlapError == "检测到Note重叠。请增加BMS最大格线设置。",
            "runtime chs NoteOverlapError"
        )
        require(runtime.bpmOverflowError == "多字节 BPM 数量已经超过上限：", "runtime chs BPMOverflowError")
        require(runtime.stopOverflowError == "多字节 STOP 数量已经超过上限：", "runtime chs STOPOverflowError")
        require(
            runtime.savedFileWillContainErrors == "文件将无法正确保存。",
            "runtime chs SavedFileWillContainErrors"
        )
        require(
            runtime.scrollOverflowError
                == "Numbers of multi-byte SCROLLs has exceeded supported maximum: ",
            "runtime chs SCROLL falls back to English"
        )

        let jpn = LegacyLocale.runtime(try! LegacyLocale.parse(url: langURL("jpn.Lang.xml")))
        require(
            jpn.scrollOverflowError == "SCROLL の数が使用できる最大値を超えています。：",
            "runtime jpn SCROLLOverflowError"
        )
    }

    private static func testSaveRuntimeMissingFallsBack() {
        let empty = LegacyLocale.runtime(nil)
        require(empty.saveWarning == "Warning: ", "nil pack SaveWarning keeps trailing space")
        require(
            empty.noteOverlapError
                == "Note operlapping detected. Increasing Maximum Grid Partition will resolve this.",
            "nil pack NoteOverlapError keeps operlapping typo"
        )
        require(
            empty.bpmOverflowError == "Numbers of multi-byte BPMs has exceeded supported maximum: ",
            "nil pack BPMOverflowError keeps trailing space"
        )
        require(
            empty.stopOverflowError == "Numbers of STOPs has exceeded supported maximum: ",
            "nil pack STOPOverflowError"
        )
        require(
            empty.scrollOverflowError == "Numbers of multi-byte SCROLLs has exceeded supported maximum: ",
            "nil pack SCROLLOverflowError"
        )
        require(
            empty.savedFileWillContainErrors == "The saved file will contain errors.",
            "nil pack SavedFileWillContainErrors"
        )

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <iBMSC.Locale Name="FileOnly">
          <Menu>
            <File>
              <Title amp="0">File</Title>
            </File>
          </Menu>
        </iBMSC.Locale>
        """
        let pack = try! LegacyLocale.parse(data: Data(xml.utf8), path: "/tmp/file-only.Lang.xml")
        let runtime = LegacyLocale.runtime(pack)
        require(runtime.saveWarning == "Warning: ", "File-only SaveWarning stays English")
        require(
            runtime.noteOverlapError
                == "Note operlapping detected. Increasing Maximum Grid Partition will resolve this.",
            "File-only NoteOverlapError stays English"
        )
    }

    private static func testSaveMessageComposition() {
        let chs = LegacyLocale.runtime(try! LegacyLocale.parse(url: langURL("chs.Lang.xml")))
        require(
            chs.overlapSaveMessage()
                == "警告：\n检测到Note重叠。请增加BMS最大格线设置。\n文件将无法正确保存。",
            "chs overlap save message"
        )
        require(
            chs.overflowSaveMessage(kind: .bpm, count: 256, enabled: false)
                == "警告：\n多字节 BPM 数量已经超过上限：256 > 255\n文件将无法正确保存。",
            "chs BPM overflow save message"
        )
        require(chs.scrollOverflowSaveMessage(count: 1295) == nil, "chs 1295 SCROLL is allowed")
    }

    private static func testDialogDoubleClickPrompts() {
        let chs = LegacyLocale.runtime(try! LegacyLocale.parse(url: langURL("chs.Lang.xml")))
        require(chs.doubleClickPrompt(channel: "11") == "请输入一个标签。", "chs label column 11")
        require(chs.doubleClickPrompt(channel: "04") == "请输入一个标签。", "chs label column 04")
        require(chs.doubleClickPrompt(channel: "03") == "请输入变速值。", "chs BPM column 03")
        require(chs.doubleClickPrompt(channel: "08") == "请输入变速值。", "chs BPM column 08")
        require(chs.doubleClickPrompt(channel: "09") == "请输入STOP值。", "chs STOP column 09")
        require(
            chs.doubleClickPrompt(channel: "SC") == "Please enter a SCROLL value.",
            "chs SCROLL column stays English"
        )
        require(chs.writeTimingPrompt(channel: "09") == "请输入STOP值。", "chs write STOP")
        require(chs.writeTimingPrompt(channel: "SC") == "Please enter a SCROLL value.", "chs write SCROLL English")
        require(chs.writeTimingPrompt(channel: "03") == "请输入变速值。", "chs write BPM default")
    }

    private static func langDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("iBMSC/misc/Data", isDirectory: true)
    }

    private static func langURL(_ name: String) -> URL {
        langDirectory().appendingPathComponent(name)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
