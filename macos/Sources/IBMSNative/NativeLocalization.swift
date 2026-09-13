import AppKit

/// 原生界面的固定文案。调用方可传稳定键，也可直接传英文原文。
/// 不会处理图表内容、文件名、BMS/BMSON 字段或用户输入。
@MainActor
enum NativeLocalization {
    enum Language: String {
        case chineseSimplified = "zh-Hans"
        case english = "en"
        case legacy = "legacy"
    }

    private static let languageKey = "IBMSNative.NativeLanguage"
    private static var defaults = UserDefaults.standard
    /// 弱键保证窗口、菜单和控件释放后，其原文不会污染复用的对象地址。
    private static let fixedSources = NSMapTable<NSObject, NSString>.weakToStrongObjects()
    /// 提示文字独立保存，避免和按钮标题共用同一原文键。
    private static let tooltipSources = NSMapTable<NSObject, NSString>.weakToStrongObjects()

    static var language: Language {
        get { Language(rawValue: defaults.string(forKey: languageKey) ?? "zh-Hans") ?? .chineseSimplified }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    /// 首次启动时使用简体中文；已有用户的明确选择不受影响。
    static func configureDefaultLanguage(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: languageKey) == nil else { return }
        defaults.set(Language.chineseSimplified.rawValue, forKey: languageKey)
    }

    static func useChineseSimplified() { language = .chineseSimplified }
    static func useEnglish() { language = .english }
    static func useLegacyLanguagePack() { language = .legacy }

    /// 仅供测试隔离偏好设置，传入 `nil` 后恢复用户的默认设置。
    static func setDefaultsForTesting(_ value: UserDefaults?) {
        defaults = value ?? .standard
    }

    /// 切换语言后只刷新已注册的原生窗口和应用菜单，不改编辑框、路径或文件内容。
    static func refreshVisibleInterface() {
        if let menu = NSApp.mainMenu { localize(menu: menu) }
        for window in NSApp.windows where window.isVisible { localize(window: window) }
    }

    static func text(_ key: String, fallback: String? = nil) -> String {
        guard language == .chineseSimplified else { return fallback ?? key }
        if let selectedCount = selectedNoteCount(from: key) {
            return "已选中 \(selectedCount) 个音符"
        }
        return chinese[key] ?? (fallback.flatMap { chinese[$0] }) ?? fallback ?? key
    }

    /// 将固定控件与稳定英文源键绑定。不要用于文件名、统计结果或用户输入。
    static func markFixed(_ object: NSObject, key: String) {
        guard !key.isEmpty else { return }
        fixedSources.setObject(key as NSString, forKey: object)
    }

    /// 为固定提示文字登记英文源键。不要传入路径或用户生成的提示。
    static func markTooltip(_ view: NSView, key: String) {
        guard !key.isEmpty else { return }
        tooltipSources.setObject(key as NSString, forKey: view)
        view.toolTip = text(key)
    }

    /// 仅供已知完全由固定文案组成的对话框在构造结束时登记。
    /// 它只处理字典中已有的键；带边框输入框、弹出数据和空值一律跳过。
    static func registerKnownStaticControls(in root: NSView) {
        for view in root.subviews {
            if view is NSPopUpButton || view is NSComboBox { continue }
            if let button = view as? NSButton, !button.title.isEmpty, chinese[button.title] != nil {
                markFixed(button, key: button.title)
                button.title = text(button.title)
            } else if let label = view as? NSTextField,
                      !label.isBordered,
                      !label.drawsBackground,
                      !label.stringValue.isEmpty,
                      chinese[label.stringValue] != nil {
                markFixed(label, key: label.stringValue)
                label.stringValue = text(label.stringValue)
            } else if let box = view as? NSBox, !box.title.isEmpty, chinese[box.title] != nil {
                markFixed(box, key: box.title)
                box.title = text(box.title)
            }
            registerKnownStaticControls(in: view)
        }
    }

    static func format(_ key: String, _ arguments: CVarArg..., fallback: String? = nil) -> String {
        String(format: text(key, fallback: fallback), locale: Locale(identifier: "zh_Hans"), arguments: arguments)
    }

    /// 只在窗口或菜单创建、语言切换时调用一次。不会遍历运行中的编辑内容。
    static func localize(menu: NSMenu) {
        let menuSource = source(for: menu) ?? inferredFixedKey(menu.title)
        if let menuSource {
            markFixed(menu, key: menuSource)
            menu.title = text(menuSource)
        }
        for item in menu.items {
            if !item.isSeparatorItem {
                let itemSource = source(for: item) ?? (item.identifier == nil ? nil : inferredFixedKey(item.title))
                if let itemSource {
                    markFixed(item, key: itemSource)
                    item.title = text(itemSource)
                }
            }
            if let submenu = item.submenu { localize(menu: submenu) }
        }
    }

    /// 仅用于构造阶段完全固定的菜单，例如 bmhelper 专用菜单栏。
    static func registerKnownStaticMenu(_ menu: NSMenu) {
        if chinese[menu.title] != nil { markFixed(menu, key: menu.title) }
        for item in menu.items {
            if !item.isSeparatorItem, chinese[item.title] != nil { markFixed(item, key: item.title) }
            if let submenu = item.submenu { registerKnownStaticMenu(submenu) }
        }
    }

    /// 仅翻译非编辑控件和表头。下拉框的项目常是保存值，保持原样。
    static func localize(view: NSView) {
        if let popup = view as? NSPopUpButton {
            if source(for: popup) != nil, let menu = popup.menu {
                localize(menu: menu)
            }
            return
        }
        if view is NSComboBox {
            return
        }
        if let field = view as? NSTextField, let source = source(for: field) {
            field.stringValue = text(source)
        } else if let button = view as? NSButton, let source = source(for: button) {
            button.title = text(source)
        } else if let box = view as? NSBox, let source = source(for: box) {
            box.title = text(source)
        } else if let table = view as? NSTableView {
            for column in table.tableColumns {
                if let source = source(for: column) { column.title = text(source) }
            }
        }
        if let tooltipSource = tooltipSources.object(forKey: view) as String? {
            view.toolTip = text(tooltipSource)
        }
        for child in view.subviews { localize(view: child) }
    }

    static func localize(window: NSWindow) {
        if let source = source(for: window) { window.title = text(source) }
        localize(view: window.contentView ?? NSView())
    }

    static func localize(alert: NSAlert) {
        alert.messageText = text(alert.messageText)
        alert.informativeText = text(alert.informativeText)
        for button in alert.buttons { button.title = text(button.title) }
    }

    private static func source(for object: NSObject) -> String? {
        fixedSources.object(forKey: object) as String?
    }

    private static func inferredFixedKey(_ value: String) -> String? {
        chinese[value] == nil ? nil : value
    }

    /// 只处理选中对象面板的内部固定状态格式，不推断或改写其他动态文字。
    private static func selectedNoteCount(from value: String) -> Int? {
        let singularSuffix = " selected note"
        let pluralSuffix = " selected notes"
        let suffix = value.hasSuffix(pluralSuffix) ? pluralSuffix : (value.hasSuffix(singularSuffix) ? singularSuffix : nil)
        guard let suffix else { return nil }
        let number = String(value.dropLast(suffix.count))
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return nil }
        return Int(number)
    }

    // 键既可使用语义键，也可使用旧界面中的英文原文，方便渐进式接入。
    private static let chinese: [String: String] = [
        "app.about": "关于 iBMSC", "About iBMSC": "关于 iBMSC",
        "app.quit": "退出 IBMSNative", "Quit IBMSNative": "退出 IBMSNative",
        "File": "文件", "New": "新建", "Open…": "打开…", "Open...": "打开…",
        "Save": "保存", "Save As…": "另存为…", "Save As...": "另存为…",
        "Import from .SM file": "从 .SM 文件导入", "Import from .IBMSC file": "从 .IBMSC 文件导入",
        "Import BMS as BMSON…": "将 BMS 导入为 BMSON…", "Export .IBMSC file": "导出 .IBMSC 文件",
        "Export WAV…": "导出 WAV…", "Edit": "编辑", "Undo": "撤销", "Redo": "重做",
        "Cut": "剪切", "Copy": "复制", "Paste": "粘贴", "Delete": "删除", "Select All": "全选",
        "Go To Measure...": "跳转到小节…", "Encoding": "编码", "Find": "查找",
        "Find / Delete / Replace": "查找 / 删除 / 替换", "Statistics": "统计信息",
        "Time Selection Tool": "时间选择工具", "Select Tool": "选择工具", "Write Tool": "写入工具",
        "MyO2 ToolBox (Chinese Only)": "MyO2 工具箱", "View": "视图", "Timing…": "时序…",
        "ToolBar": "工具栏", "Options Panel": "选项面板", "Status Bar": "状态栏",
        "Left Splitter": "左侧分隔栏", "Right Splitter": "右侧分隔栏", "Grid": "网格",
        "Sub": "子网格", "BackGround": "背景", "Measure Index": "小节编号",
        "Measure Line": "小节线", "Vertical Line": "竖线", "Column Caption": "列标题",
        "Options": "选项", "Conversions": "转换", "Preview": "预览", "Window": "窗口",
        "Minimize": "最小化", "Zoom": "缩放", "Bring All to Front": "全部置于前面", "Help": "帮助",
        "Theme": "主题", "Language": "语言", "Refresh": "刷新",
        "General Options": "常规选项", "Visual Options": "显示选项", "Player Arguments Options": "播放器参数选项",
        "Text Encoding": "文本编码", "Associate Filetype": "关联文件类型",
        "Max Grid Partition in BMS": "BMS 最大网格分割数", "AutoSave": "自动保存",
        "minutes": "分钟", "Beep while saved": "保存时发出提示音",
        "Extend number of multi-byte BPMs to 1296": "将多字节 BPM 数量上限扩展到 1296",
        "Extend number of STOPs to 1296": "将 STOP 数量上限扩展到 1296",
        "Mouse Wheel": "鼠标滚轮", "PageUp / PageDown": "PageUp / PageDown",
        "Mouse Middle Button": "鼠标中键", "Click and Auto Scroll": "单击并自动滚动",
        "Click and Drag": "单击并拖动", "Automatically set focus to editing panel on mouse enter": "鼠标进入编辑区时自动获得焦点",
        "Disable first click if the editing panel is not focused": "编辑区未获得焦点时忽略第一次单击",
        "Stop preview if clicked on the editing panel": "单击编辑区时停止预览", "OK": "确定", "Cancel": "取消",
        "Current Player:": "当前播放器：", "Add": "添加", "Remove": "移除", "Path": "路径",
        "Arguments": "参数", "Play from beginning": "从开头播放", "Play from current measure": "从当前小节播放",
        "Stop": "停止", "Restore Default": "恢复默认设置",
        "Play from Start": "从开头播放", "Play Here": "从当前位置播放", "Apply": "应用",
        "Scale measure": "缩放小节", "Replace value": "替换数值", "Delete selected": "删除所选项",
        "Initial BPM": "初始 BPM", "Measure": "小节", "Ratio": "比例", "Kind": "类型",
        "Fraction": "分数", "Value": "数值", "Time before STOP": "STOP 前时间",
        "Time after STOP": "STOP 后时间", "Source": "来源", "Timing": "时序", "Timing event": "时序事件",
        "BPM — integer (03)": "BPM — 整数（03）", "BPM — decimal (08)": "BPM — 小数（08）",
        "STOP (09)": "STOP（09）", "Exact decimal value": "精确小数值",
        "Note Range": "音符范围", "Measure Range": "小节范围", "Label Range": "标签范围",
        "Value Range": "数值范围", "to": "至", "Column": "列", "Operation": "操作",
        "Select Inverse": "反选", "Unselect All": "取消全选", "Replace with Label:": "替换为标签：",
        "Replace with Value:": "替换为数值：", "Select": "选择", "Unselect": "取消选择", "Close": "关闭",
        "Short": "短音符", "Long": "长音符", "Hidden": "隐藏", "Visible": "可见",
        "File association is a Windows registry setting.": "文件关联是 Windows 注册表设置。",
        "macOS does not write those keys. Use Finder → Get Info → Open with to choose this app.": "macOS 不会写入这些设置。请在 Finder 中选择“显示简介”→“打开方式”，再选择此应用。",
        "There must exist at least one player.": "至少需要保留一个播放器。",
        "Restore default settings?": "要恢复默认设置吗？", "Yes": "是", "No": "否",
        "Error": "错误", "Warning": "警告",
        "Timing data is unavailable for this document.": "这个文档没有可用的时序数据。",
        "Times are supplied by the chart timing map. They are not playback controls.": "时间由谱面的时序表计算得出，不能控制播放。",
        "Line %d: %@": "第 %d 行：%@",
        "Built-in preview plays #WAV samples from the chart folder. OGG stays silent if the system cannot decode it.": "内置预览会播放谱面文件夹中的 #WAV 音频；支持的 OGG 文件也会参与播放。",
        "Import MIDI": "导入 MIDI", "Open Project": "打开工程", "Project Status": "工程状态",
        "No project yet.": "还没有工程。", "Import MIDI or open an existing project.": "导入 MIDI 或打开已有工程。",
        "Play Current Segment": "播放当前段", "Play Previous Segment": "播放上一段",
        "Audio file path": "音频文件路径", "Output folder path": "输出文件夹路径",
        "Audio File": "音频文件", "Output Directory": "输出目录", "Output sound file prefix:": "输出音频文件前缀：",
        "Slice Parameters": "切分参数", "BPM:": "BPM：", "Offset (MS):": "偏移（毫秒）：", "Browse...": "浏览…",
        "Split": "切分", "Cut points:": "切分点：", "Cut marks (seconds):": "切分标记（秒）：",
        "Add mark": "添加标记", "Clear marks": "清除标记", "Sequence start:": "序列起点：", "FF definition": "FF 定义",
        "Export BMSE": "导出 BMSE", "Import BMSE": "导入 BMSE", "New division...": "新建分割…",
        "Write MIDI File": "写入 MIDI 文件", "Copy woslicer II Cutting Positions": "复制 woslicer II 切分位置",
        "Open built-in audio cutter": "打开内置音频切分器", "Open BMS WAV definitions...": "打开 BMS WAV 定义…",
        "Copy BMS Data to Clipboard": "复制 BMS 数据到剪贴板", "Transpose to...": "转换为…",
        "Move WAV definitions down": "下移 WAV 定义", "Move WAV definitions up": "上移 WAV 定义",
        "Source MIDI": "源 MIDI", "Slice Timeline": "切分时间线", "Untitled project": "未命名工程",
        "Project has unsaved changes: %@": "%@（有未保存的改动）。",
        "Simplified Chinese": "简体中文",
        "About": "关于", "ColorPicker": "颜色选择器",
        "Export complete": "导出完成", "Audio export needs attention": "音频导出需要处理",
        "Exporting WAV in the background…": "正在后台导出 WAV…",
        "Output file already exists. Choose a new file name.": "输出文件已存在，请另选文件名。",
        "Choose an audio file before exporting.": "请先选择音频文件再导出。",
        "Exported %d slices to %@": "已导出 %d 个切片到 %@。",
        "Grid Setting": "网格设置", "Export WAV": "导出 WAV", "Preferences": "偏好设置",
        "Convert Resolution": "转换分辨率", "External Viewer Configuration": "外部查看器配置",
        "General": "常规", "BMS Import": "导入 BMS",
        "Language:": "语言：", "(Requires restart)": "（需要重启）", "Save Format:": "保存格式：",
        "Save JSON Format:": "保存 JSON 格式：", "UI Font:": "界面字体：", "Reset": "重置",
        "Enable Master Cache": "启用主缓存", "Show Master Lane": "显示主轨道", "Show Mini Map": "显示小地图",
        "Fix Mini Map": "固定小地图", "Mini Map Opacity:": "小地图不透明度：", "Edit Mode": "编辑模式",
        "Always show cursor line": "始终显示光标线", "Enable snapped-to-grid hit test of clicks": "点击时按网格吸附命中测试",
        "Enable snapped-to-grid selection": "按网格吸附选择", "Sound Channels / Master Channel": "声音轨道 / 主轨道",
        "Timing Adjustment:": "时序调整：", "Smooth bar motion": "平滑小节移动", "Sound Notes": "声音音符",
        "Max duration:": "最大时长：", "Soft fade out": "柔和淡出", "Configure External Viewers...": "配置外部查看器…",
        "Default": "默认", "Ask": "询问", "Text Encoding:": "文本编码：", "Generate random values": "生成随机值",
        "Game Mode:": "游戏模式：", "Trust #PLAYER command": "信任 #PLAYER 命令", "Ignore file extension": "忽略文件扩展名",
        "Miscellaneous": "其他", "Minimum resolution": "最小分辨率", "Maximum resolution": "最大分辨率",
        "Whole Song": "整首歌曲", "Output File:": "输出文件：", "Range:": "范围：", "Refresh Master Cache": "刷新主缓存",
        "Volume:": "音量：", "Clipping:": "削波：", "Export": "导出", "Soft Clip": "柔和削波", "Hard Clip": "硬削波",
        "Normalize": "标准化",
        "Audio Slicer": "音频切片器", "MIDI file import settings": "MIDI 文件导入设置",
        "Tracks (&T):": "音轨（&T）：", "Channels (&C):": "通道（&C）：",
        "Division settings": "分割设置", "Name (&N):": "名称（&N）：", "MIDI settings": "MIDI 设置",
        "Leave MIDI unaltered (&C)": "保持 MIDI 不变（&C）", "Leading silence (&H):": "前置静音（&H）：",
        "Min. interval gap (&I):": "最小间隔（&I）：", "Sorting method (&S):": "排序方式（&S）：",
        "Minimum difference in:": "最小差异：", " Length (&G):": " 时长（&G）：", " Velocity (&V):": " 力度（&V）：",
        "Definition settings": "定义设置", "Use base-36 range(00-ZZ) (&Z)": "使用 36 进制范围（00-ZZ）（&Z）",
        "Use overloading (&M)": "使用重载（&M）", "Starting BMS Index (&D):": "起始 BMS 编号（&D）：",
        "Overloading Interval (&L):": "重载间隔（&L）：",
        "You can drag and drop a .wav file into this window.": "可以将 .wav 文件拖到此窗口。",
        "Select audio file...": "选择音频文件…", "Select audio output directory...": "选择音频输出目录…",
        "Error while splitting file": "切分文件时出错",
        "Audio splitter (division: \"%@\")": "音频切分器（分割：\"%@\"）",
        "File (&F)": "文件（&F）", "New...": "新建…", "Open project (&O)...": "打开工程（&O）…",
        "Save project (&S)": "保存工程（&S）", "Save project as (&A)...": "工程另存为（&A）…",
        "Close project (&C)": "关闭工程（&C）", "Divisions (&D)": "分割（&D）", "Help (&H)": "帮助（&H）",
        "New division (&N)...": "新建分割（&N）…", "Rename division": "重命名分割",
        "Regenerate division (&E)...": "重新生成分割（&E）…", "Delete division (&D)": "删除分割（&D）",
        "Write modified MIDI File (&M)...": "写入修改后的 MIDI 文件（&M）…", "BMS WAV definitions": "BMS WAV 定义",
        "Copy division (&W)": "复制分割（&W）",
        "Copy BMS sequence to clipboard (&S)": "复制 BMS 序列到剪贴板（&S）",
        "Division": "分割", "Label": "标签", "Aux. Grid": "辅助网格",
        "Defined variables": "已定义变量",
        "Name:": "名称：", "Program Path:": "程序路径：", "Working Directory:": "工作目录：",
        "Play from Beginning:": "从开头播放：", "Play from Here:": "从当前位置播放：", "Stop:": "停止：",
        "file name": "文件名", "document directory": "文档目录", "application directory": "应用目录",
        "current measure": "当前小节", "current time in seconds": "当前时间（秒）", "current time in ticks": "当前时间（tick）",
        "Header": "谱面信息", "WaveForm": "波形", "#WAV (Sounds List)": "#WAV（声音列表）",
        "#BMP (Images List)": "#BMP（图像列表）", "Beat": "节拍", "Expansion Code": "扩展代码",
        "Chart Name": "谱面名称", "Judge Rank": "判定等级", "Mode Hint": "模式提示",
        "No objects selected": "未选中对象",
        "Title Image": "标题图像", "Preview Music": "预览音乐", "Selected Objects": "选中对象",
        "Length": "长度", "Extra fields": "额外字段", "Number of B Columns": "B 列数量",
        "Vertical Scroll Lock": "垂直滚动锁定", "Allow Multiple Selection": "允许多选",
        "Synchronize Note Labels": "同步音符标签", "Keep absolute position": "保持绝对位置",
        "Keep measure position": "保持小节位置", "Keep measure position and cut overflow": "保持小节位置并截断溢出",
        "Scale to measure length": "缩放到小节长度", "Move Up": "上移", "Move Down": "下移",
        "Browse": "浏览", "Load WaveForm": "加载波形", "Clear WaveForm": "清除波形",
        "Division shortcuts": "分割快捷操作", "This options-panel control is not wired yet.": "此选项面板控件尚未接入。",
        "Next": "下一步", "Finish": "完成", "Skip Questions": "跳过提问",
        "Loading BMS...": "正在加载 BMS…", "Succeeded to import BMS.": "已导入 BMS。", "Failed to import BMS.": "导入 BMS 失败。",
        "Select game mode:": "选择游戏模式：", "Select text encoding:": "选择文本编码：", "Select random value:": "选择随机值：",
        "Random": "随机", "Up": "上移", "Down": "下移", "Info": "信息",
        "Timeline": "时间线", "Master": "主轨道", "Playing": "播放中", "Abs": "绝对", "Loc": "位置", "Time": "时间", "Lane": "轨道",
        "Move to Key Lanes": "移到键盘轨道", "Move to BGM Lanes": "移到 BGM 轨道", "Separate Layered Notes": "拆分叠层音符",
        "Write Mode": "写入模式", "Clear Master Cache": "清除主缓存", "Views": "视图列表", "Toolbars": "工具栏",
        "View Mode": "查看模式", "Sound Channel Lanes Display": "声音轨道显示", "Full Screen": "全屏",
        "Channel": "轨道", "Add...": "添加…", "Select Previous": "选择上一个", "Select Next": "选择下一个",
        "Move Left": "左移", "Move Right": "右移", "Select File...": "选择文件…", "Preview Source Sound": "试听源音频",
        "About BmsONE": "关于 BmsONE", "About Qt": "关于 Qt",
        "Title": "标题", "Artist": "艺术家", "Genre": "曲风", "Player": "玩家", "Rank": "判定等级", "Play Level": "难度等级",
        "SubTitle": "副标题", "SubArtist": "副艺术家", "Stage File": "舞台文件", "Banner": "横幅", "Back BMP": "背景 BMP",
        "Difficulty": "难度", "ExRank": "EX 判定", "Total": "总值", "Comment": "备注", "LnObj": "长音对象",
        "1 - Single Play": "1 - 单人模式", "2 - Couple Play": "2 - 合作模式", "3 - Double Play": "3 - 双人模式",
        "0 - Very Hard": "0 - 非常困难", "1 - Hard": "1 - 困难", "2 - Normal": "2 - 普通", "3 - Easy": "3 - 简单", "4 - Very Easy": "4 - 很简单",
        "None": "无", "1 - EZ / Beginner": "1 - EZ / 初学", "2 - NM / Normal": "2 - NM / 普通",
        "3 - HD / Hyper": "3 - HD / 困难", "4 - MX / Another": "4 - MX / 另一难度", "5 - SC / Insane": "5 - SC / 极难",
        "None (#LnType 1)": "无（#LnType 1）", "Lock Left Editing Panel": "锁定左侧编辑区",
        "Lock Middle Editing Panel": "锁定中间编辑区", "Lock Right Editing Panel": "锁定右侧编辑区",
        "Lock to BGM": "锁定到 BGM", "Format": "格式", "Export WAV...": "导出 WAV…",
        "Grid Setting...": "网格设置…", "Preferences...": "偏好设置…", "Convert Resolution...": "转换分辨率…",
        "Find Next...": "查找下一个…", "Find Previous...": "查找上一个…", "Active Channels Only": "仅活动轨道",
        "Show Hit Channels Only": "仅显示命中轨道", "Darken Notes in Inactive Channels": "暗化非活动轨道的音符",
        "Snap to Grid": "吸附到网格", "Zoom In": "放大", "Zoom Out": "缩小", "Normal": "普通",
        "Compact": "紧凑", "Simple": "简洁", "Libraries Information:": "库信息：",
        "Converted as %@.": "已按 %@ 转换。", "Title: %@": "标题：%@", "Notes: %d": "音符：%d",
        "Skip Questions used defaults.": "“跳过提问”使用了默认值。", "Default: %@": "默认值：%@", "(untitled)": "（未命名）",
        "multiple values": "多个值", "Expand...": "展开…", "Collapse...": "收起…",
        "Snap to grid (G)": "吸附到网格（G）", "Disable vertical moves (D)": "禁止垂直移动（D）",
        "LN Input Style - NT/BMSE": "长音输入方式 - NT/BMSE", "Error Check": "错误检查",
        "Preview on Click": "单击预览", "Show File Name on Notes": "在音符上显示文件名",
        "Player Options": "播放器选项", "Save Theme": "保存主题",
        "Load Theme File from iBMSC 2.x": "从 iBMSC 2.x 加载主题文件",
        "→ Long Note": "→ 长音符", "→ Short Note": "→ 短音符",
        "Long Note ↔ Short Note": "长音符 ↔ 短音符", "→ Hidden Note": "→ 隐藏音符",
        "→ Visible Note": "→ 可见音符", "Hidden Note ↔ Visible Note": "隐藏音符 ↔ 可见音符",
        "Modify Labels": "修改标签", "Mirror": "镜像",
        "Play from here": "从当前位置播放", "BGA / Layer / Poor": "BGA / 图层 / POOR",
        "BPM": "BPM", "SCROLL": "滚动", "STOP": "停止", "Theme Imported with Notes": "已导入主题和音符",
        "Theme Unavailable": "主题不可用", "Filename (&F):": "文件名（&F）：",
        "Copy to clipboard (&C)": "复制到剪贴板（&C）", "Close (&W)": "关闭（&W）",
        "Please select source MIDI file": "请选择源 MIDI 文件",
        "About Be-Music Helper": "关于 Be-Music Helper", "Quit Be-Music Helper": "退出 Be-Music Helper"
    ]
}
