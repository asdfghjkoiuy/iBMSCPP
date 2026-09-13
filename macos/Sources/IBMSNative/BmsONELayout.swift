import CoreGraphics
import Foundation

/// Geometry taken from BmsONE `bb3406eeb8f45d79350241f09bb897dd229ce3af`.
/// BMSON is modeled separately from BMS; this file only records window numbers.
enum BmsONEMainWindowLayout {
    /// `MainWindow.cpp:43` `resize(960, 640)` — widget size, not the OS frame.
    static let clientSize = CGSize(width: 960, height: 640)
    /// `MainWindow.cpp:420` `dock2->resize(334, dock2->height())`.
    static let channelDockWidth: CGFloat = 334
    /// `StatusBar.cpp:31` `StatusBarSection::BaseHeight`.
    static let statusBarHeight: CGFloat = 18
    /// `MainWindow.cpp:29` `UIUtil::ToolBarIconSize`.
    static let toolBarIconSize = CGSize(width: 18, height: 18)

    static let infoDockTitle = "Info"
    static let infoChartNameLabel = "Chart Name"
    static let infoJudgeRankLabel = "Judge Rank"
    static let infoModeHintLabel = "Mode Hint"
    static let infoTitleImageLabel = "Title Image"
    static let infoPreviewMusicLabel = "Preview Music"
    static let infoExtraFieldsTitle = "Extra fields"
    /// `InfoView.cpp` `SettingsShowExtraFields`。
    static let infoShowExtraFieldsKey = "DocumentInfoView/ShowExtraFields"
    /// Working height: leftover InfoView fields plus Extra fields. Not a screenshot.
    static let infoDockSize = CGSize(width: 200, height: 258)
    static let channelDockTitle = "Channel"
    static let selectedObjectsDockTitle = "Selected Objects"
    static let transferToKeyTitle = "Move to Key Lanes"
    static let transferToBgmTitle = "Move to BGM Lanes"
    static let separateLayeredTitle = "Separate Layered Notes"
    static let editModeTitle = "Edit Mode"
    static let writeModeTitle = "Write Mode"
    static let channelMenuTitle = "Channel"
    static let channelAddTitle = "Add..."
    static let channelPreviousTitle = "Select Previous"
    static let channelNextTitle = "Select Next"
    static let channelFindNextTitle = "Find Next..."
    static let channelFindPreviousTitle = "Find Previous..."
    /// `ChannelFindTools.cpp` `actionChannelFindFilterActive`。
    static let channelFindActiveOnlyTitle = "Active Channels Only"
    /// `ChannelFindTools.cpp` `actionChannelFindHideOthers`。
    static let channelFindHideOthersTitle = "Show Hit Channels Only"
    static let channelMoveLeftTitle = "Move Left"
    static let channelMoveRightTitle = "Move Right"
    static let channelDeleteTitle = "Delete"
    static let channelSelectFileTitle = "Select File..."
    static let channelPreviewSourceTitle = "Preview Source Sound"
    /// `MainWindow.cpp` `actionEditClearMasterCache`。
    static let clearMasterCacheTitle = "Clear Master Cache"
    /// `MainWindow.cpp` `actionViewDarkenNotesInInactiveChannels`。
    static let darkenInactiveChannelsTitle = "Darken Notes in Inactive Channels"
    /// `MainWindow.cpp` `actionViewSnapToGrid`。
    static let snapToGridTitle = "Snap to Grid"
    /// `MainWindow.cpp` `menuViewMode = menuView->addMenu(tr("View Mode"))`。
    static let viewModeMenuTitle = "View Mode"
    /// `MainWindow.cpp` `menuView->addMenu(tr("Zoom"))`。
    static let zoomMenuTitle = "Zoom"
    static let zoomInTitle = "Zoom In"
    static let zoomOutTitle = "Zoom Out"
    /// `tr("Reset", "Zoom")`。
    static let zoomResetTitle = "Reset"
    /// `SequenceTools.cpp` `tr("Sound Channel Lanes Display")`。
    static let soundChannelLanesMenuTitle = "Sound Channel Lanes Display"
    static let soundChannelLaneNormalTitle = "Normal"
    static let soundChannelLaneCompactTitle = "Compact"
    static let soundChannelLaneSimpleTitle = "Simple"

    /// Left docks consume the Channel requested width; toolbar height is not in source.
    static var sequenceViewFrame: CGRect {
        CGRect(
            x: channelDockWidth,
            y: 0,
            width: clientSize.width - channelDockWidth,
            height: clientSize.height - statusBarHeight
        )
    }

    static var statusBarFrame: CGRect {
        CGRect(
            x: 0,
            y: clientSize.height - statusBarHeight,
            width: clientSize.width,
            height: statusBarHeight
        )
    }

    static var dockColumnFrame: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: channelDockWidth,
            height: clientSize.height - statusBarHeight
        )
    }
}

enum BmsONEFileTypes {
    /// `MainWindow.cpp` FileOpen: `*.bms *.bme *.bml *.pms`
    static let bmsExtensions = ["bms", "bme", "bml", "pms"]

    static func isBmsURL(_ url: URL) -> Bool {
        bmsExtensions.contains(url.pathExtension.lowercased())
    }
}

enum BmsONEWindowTitle {
    static let appName = "BmsONE"
    /// `AppInfo.h` `APP_VERSION_STRING`。
    static let version = "beta 0.2.1"
    static let untitled = "untitled"
    /// `MainWindow.cpp:750-756` always appends `" [*] - " APP_NAME`.
    static let sourceSuffix = " [*] - BmsONE"

    static func sourceTitle(filePath: String?) -> String {
        let base: String
        if let filePath, !filePath.isEmpty {
            base = filePath
        } else {
            base = untitled
        }
        return base + sourceSuffix
    }
}

/// 对照 `MainWindow::HelpAbout`。系统关于框，没有手写客户区。
/// `__DATE__` / `__TIME__` 不写：那是本程序编译钟，不是 BmsONE。
/// `QT_VERSION_STR` 不写：产品不是 Qt。
enum BmsONEAbout {
    static let title = BmsONEDialogLayout.aboutTitle
    static let helpMenuTitle = BmsONEDialogLayout.helpMenuTitle
    static let appName = BmsONEWindowTitle.appName
    static let version = BmsONEWindowTitle.version
    static let platform = "macOS"
    static let url = "https://github.com/excln/BmsONE"
    static let copyrightHolder = "exclusion"
    static let copyright = "Copyright 2015-2017 \(copyrightHolder)"
    static let librariesTitle = "Libraries Information:"
    static let qtName = "Qt"
    static let qtURL = "http://www.qt.io/"
    static let oggName = "libogg"
    static let oggVersion = "Xiph.Org libOgg 1.3.2"
    static let oggURL = "https://www.xiph.org/"
    static let vorbisName = "libvorbis"
    static let vorbisVersion = "Xiph.Org libVorbis 1.3.5"
    static let vorbisURL = "https://www.xiph.org/"

    static var versionLine: String {
        "version \(version) \(platform)"
    }

    static var informativeText: String {
        """
        \(appName)

        \(versionLine)

        \(copyright)
        \(url)

        \(librariesTitle)
        \(qtName)
        \(oggName) \(oggVersion)
        \(vorbisName) \(vorbisVersion)
        """
    }

    /// 对照 `HelpAbout` 的 HTML，不含编译日期和 Qt 版本号。
    static var html: String {
        "<h2>\(appName)</h2>"
            + "<p>\(versionLine)</p>"
            + "<p>\(copyright)</p>"
            + "<hr>"
            + librariesTitle
            + "<ul>"
            + "<li><a href=\"\(qtURL)\">\(qtName)</a>"
            + "<li><a href=\"\(oggURL)\">\(oggName)</a> \(oggVersion)"
            + "<li><a href=\"\(vorbisURL)\">\(vorbisName)</a> \(vorbisVersion)"
            + "</ul>"
    }
}

enum BmsONESequenceLayout {
    /// `SequenceView.cpp:68-70`.
    static let timeLineMeasureWidth: CGFloat = 20
    static let timeLineBpmWidth: CGFloat = 34
    static let timeLineWidth: CGFloat = timeLineMeasureWidth + timeLineBpmWidth
    static let headerHeight: CGFloat = 0
    static let masterLaneWidth: CGFloat = 64
    /// `SequenceView.cpp:26-27`.
    static let footerGripWidth: CGFloat = 6
    static let minFooterHeight: CGFloat = 48 + footerGripWidth * 2
    static let maxFooterHeight: CGFloat = 180
    static let defaultFooterHeight: CGFloat = minFooterHeight
    static let largeSoundChannelWidth: CGFloat = 64
    static let smallSoundChannelWidth: CGFloat = 32
    /// `Skin.h:204-208` plus `Skin.cpp:64` for Beat 7-key.
    static let laneMargin: CGFloat = 5
    static let scratchWidth: CGFloat = 32
    static let whiteKeyWidth: CGFloat = 24
    static let blackKeyWidth: CGFloat = 24
    static let beat7kPlayingWidth: CGFloat =
        laneMargin * 2 + scratchWidth + whiteKeyWidth * 4 + blackKeyWidth * 3
    /// `MasterView.cpp:24`.
    static let miniMapWidth: CGFloat = 50
    /// `EditConfig.cpp:35-40` defaults are true, so `CanShowMasterLane` starts on.
    static let showMasterLaneByDefault = true

    static func frames(
        origin: CGPoint = .zero,
        viewportHeight: CGFloat,
        footerHeight: CGFloat = defaultFooterHeight,
        playingWidth: CGFloat = beat7kPlayingWidth,
        showMasterLane: Bool = showMasterLaneByDefault
    ) -> BmsONESequenceFrames {
        let y = origin.y + headerHeight
        let footerY = origin.y + headerHeight + viewportHeight
        let timeLine = CGRect(x: origin.x, y: y, width: timeLineWidth, height: viewportHeight)
        let masterX = origin.x + timeLineWidth
        let masterLane = showMasterLane
            ? CGRect(x: masterX, y: y, width: masterLaneWidth, height: viewportHeight)
            : .zero
        let playingX = showMasterLane ? masterX + masterLaneWidth : origin.x + timeLineWidth
        return BmsONESequenceFrames(
            timeLine: timeLine,
            masterLane: masterLane,
            playingPane: CGRect(x: playingX, y: y, width: playingWidth, height: viewportHeight),
            footerCorner: CGRect(x: origin.x, y: footerY, width: timeLineWidth, height: footerHeight),
            footerMaster: showMasterLane
                ? CGRect(x: masterX, y: footerY, width: masterLaneWidth, height: footerHeight)
                : .zero,
            footerPlaying: CGRect(x: playingX, y: footerY, width: playingWidth, height: footerHeight)
        )
    }

    /// Sequence viewport inside the main window after the dock column, status bar, and footer.
    static var mainWindowViewportHeight: CGFloat {
        BmsONEMainWindowLayout.sequenceViewFrame.height - defaultFooterHeight
    }

    static var mainWindowFrames: BmsONESequenceFrames {
        frames(
            origin: BmsONEMainWindowLayout.sequenceViewFrame.origin,
            viewportHeight: mainWindowViewportHeight
        )
    }
}

/// 对照 `SequenceView::GetVisibleRangeExtended`。
/// 先按视口上下各加 4 像素，再按 1.5 倍拉长。转成 `int` 时向零取整。
enum BmsONEVisibleRange {
    static let marginPixels: CGFloat = 4
    static let extensionRatio = 1.5

    static func extended(tBegin: Double, tEnd: Double) -> (Int, Int) {
        let delta = (tEnd - tBegin) * (extensionRatio - 1)
        return (Int(tBegin - delta), Int(tEnd + delta))
    }

    /// 源码公式：`t = viewLength - (scrollY + y) / zoomY`。
    static func fromScroll(
        viewLength: Double,
        scrollY: Double,
        viewportHeight: Double,
        zoomY: Double
    ) -> (Int, Int) {
        let top = 0 - Double(marginPixels)
        let bottom = viewportHeight + Double(marginPixels)
        let tBegin = viewLength - (scrollY + bottom) / zoomY
        let tEnd = viewLength - (scrollY + top) / zoomY
        return extended(tBegin: tBegin, tEnd: tEnd)
    }

    /// 主编辑器视口：底边更早、顶边更晚，和 BmsONE 一样。
    static func pulses(
        viewport: CGRect,
        resolution: Int,
        beatAtY: (CGFloat) -> Double
    ) -> (Int, Int) {
        let safeResolution = resolution > 0 ? resolution : BmsONEInfoDefaults.resolution
        let tBegin = beatAtY(viewport.maxY + marginPixels) * Double(safeResolution)
        let tEnd = beatAtY(viewport.minY - marginPixels) * Double(safeResolution)
        return extended(tBegin: tBegin, tEnd: tEnd)
    }
}

/// 对照 `SequenceView::SetNoteColor`。只测半 RGB，不写像素已通过。
enum BmsONENoteDarken {
    static let menuTitle = BmsONEMainWindowLayout.darkenInactiveChannelsTitle
    /// `SequenceView.cpp` `SettingsGroup` / `SettingsDarkenNotesInInactiveChannels`。
    static let settingsKey = "SequenceView/DarkenNotesInInactiveChannels"
    /// 源码默认 `true`。
    static let defaultEnabled = true
    /// 必须和 `BmsonChartMapping.noteIdentityStride` 相同。
    static let identityStride = 1_000_003

    static func load(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: settingsKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: settingsKey)
    }

    static func save(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: settingsKey)
    }

    /// `QColor` 分量整数除以 2。关掉或当前声道时原样返回。
    static func channel(_ value: UInt8, active: Bool, enabled: Bool) -> UInt8 {
        if !enabled || active {
            return value
        }
        return value / 2
    }

    static func argb(_ argb: UInt32, active: Bool, enabled: Bool) -> UInt32 {
        if !enabled || active {
            return argb
        }
        let alpha = (argb >> 24) & 0xFF
        let red = (argb >> 16) & 0xFF
        let green = (argb >> 8) & 0xFF
        let blue = argb & 0xFF
        return (alpha << 24) | ((red / 2) << 16) | ((green / 2) << 8) | (blue / 2)
    }

    /// 悬停音永远当当前声道。时值身份（非正数）不暗化。
    static func isPaintedActive(
        identity: Int,
        currentChannel: Int,
        hoverIdentity: Int?,
        identityStride: Int = identityStride
    ) -> Bool {
        if hoverIdentity == identity {
            return true
        }
        guard identity > 0, identityStride > 0 else { return true }
        return (identity - 1) / identityStride == currentChannel
    }
}

/// 对照 `SequenceView::SnapToLowerFineGrid` / `SnapToUpperFineGrid`。
/// 只改 BMSON 脉冲，不套 iBMSC 的 `4 / gDivide` 拍。
enum BmsONESnap {
    static let menuTitle = BmsONEMainWindowLayout.snapToGridTitle
    /// `SequenceView.cpp` `SettingsGroup` / `SettingsSnapToGridKey`。
    static let settingsKey = "SequenceView/SnapToGrid"
    /// `SequenceView.cpp` `SettingsFineGridKey`，存成 `d,n`，对应 `QPoint(d, n)`。
    static let fineGridKey = "SequenceView/FineGrid"
    /// `SequenceView.cpp` `SettingsCoarseGridKey`，默认 `QPoint(4, 4)` → `GridSize(4, 4)`。
    static let coarseGridKey = "SequenceView/CoarseGrid"
    static let defaultEnabled = true
    static let defaultFineGrid = BmsONEGridSize.fallbackFine
    static let defaultCoarseGrid = BmsONEGridSize.defaultMedium

    static func load(from defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: settingsKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: settingsKey)
    }

    static func save(_ enabled: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: settingsKey)
    }

    /// 默认 `QPoint(16, 4)` → `GridSize(4, 16)`。
    static func loadFineGrid(from defaults: UserDefaults = .standard) -> BmsONEGridSize {
        guard let text = defaults.string(forKey: fineGridKey) else {
            return defaultFineGrid
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let denominator = UInt(parts[0]),
              let numerator = UInt(parts[1]),
              denominator > 0,
              numerator > 0
        else {
            return defaultFineGrid
        }
        return BmsONEGridSize(numerator: numerator, denominator: denominator)
    }

    static func saveFineGrid(_ grid: BmsONEGridSize, to defaults: UserDefaults = .standard) {
        defaults.set("\(grid.denominator),\(grid.numerator)", forKey: fineGridKey)
    }

    /// 默认 `QPoint(4, 4)` → `GridSize(4, 4)`。给状态栏 Composite 的拍用。
    static func loadCoarseGrid(from defaults: UserDefaults = .standard) -> BmsONEGridSize {
        guard let text = defaults.string(forKey: coarseGridKey) else {
            return defaultCoarseGrid
        }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let denominator = UInt(parts[0]),
              let numerator = UInt(parts[1]),
              denominator > 0,
              numerator > 0
        else {
            return defaultCoarseGrid
        }
        return BmsONEGridSize(numerator: numerator, denominator: denominator)
    }

    static func saveCoarseGrid(_ grid: BmsONEGridSize, to defaults: UserDefaults = .standard) {
        defaults.set("\(grid.denominator),\(grid.numerator)", forKey: coarseGridKey)
    }

    /// `QMap::lowerBound`：第一根 `>= time` 的线。没有前一根就原样返回 `int(time)`。
    static func snapToLowerFineGrid(
        time: Double,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int {
        guard time.isFinite else { return 0 }
        let timeBase = UInt(max(1, resolution))
        let sorted = bars.sorted()
        let index = sorted.firstIndex { Double($0) >= time } ?? sorted.count
        if index == 0 {
            return Int(time)
        }
        let previous = sorted[index - 1]
        let number = fineGrid.gridNumber(timeBase: timeBase, time: time - Double(previous))
        return Int(Double(previous) + fineGrid.nthGrid(timeBase: timeBase, n: number) + 0.5)
    }

    /// 对照 `SnapToUpperFineGrid`：下一格，并夹到下一根小节线。
    static func snapToUpperFineGrid(
        time: Double,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int {
        guard time.isFinite else { return 0 }
        let timeBase = UInt(max(1, resolution))
        let sorted = bars.sorted()
        let index = sorted.firstIndex { Double($0) >= time } ?? sorted.count
        if index == 0 {
            return Int(time)
        }
        let previous = sorted[index - 1]
        let next = index < sorted.count ? sorted[index] : Int64.max
        let number = fineGrid.gridNumber(timeBase: timeBase, time: time - 1.0 - Double(previous))
        let snapped = Int(Double(previous) + fineGrid.nthGrid(timeBase: timeBase, n: 1 + number) + 0.5)
        if next == Int64.max {
            return snapped
        }
        return min(snapped, Int(next))
    }

    /// 写入对照 `WriteModeContext`：先 `int iTime = time`，勾上再 `SnapToLowerFineGrid`。
    static func writePulse(
        time: Double,
        snap: Bool,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int64 {
        guard time.isFinite else { return 0 }
        let truncated = Int(time)
        if !snap {
            return Int64(truncated)
        }
        return Int64(
            snapToLowerFineGrid(
                time: Double(truncated),
                bars: bars,
                resolution: resolution,
                fineGrid: fineGrid
            )
        )
    }
}

/// 对照 `SequenceView::ZoomIn` / `ZoomOut` / `ZoomReset` / `wheelEventVp`。
/// `zoomY` 是每脉冲像素。共用编辑器里 `ppq = zoomY * resolution`，`CGHeight = ppq / 48`。
/// 只改打开的 BMSON 的竖向比例，不套 iBMSC 的 `0.25` 步进。
enum BmsONEZoom {
    static let menuTitle = BmsONEMainWindowLayout.zoomMenuTitle
    static let zoomInTitle = BmsONEMainWindowLayout.zoomInTitle
    static let zoomOutTitle = BmsONEMainWindowLayout.zoomOutTitle
    static let resetTitle = BmsONEMainWindowLayout.zoomResetTitle
    /// `SequenceView.cpp` `SettingsGroup` / `SettingsZoomYKey`。
    static let settingsKey = "SequenceView/ZoomY"
    static let referencePixels = 48.0
    static let defaultResolution = 240
    static let minFactor = 0.5
    static let maxFactor = 8.0
    static let step = 1.25
    static let pixelStep = 1.01

    static var defaultZoomY: Double { referencePixels / Double(defaultResolution) }

    static func clampZoomY(_ zoomY: Double, resolution: Int) -> Double {
        let safe = max(resolution, 1)
        let minY = minFactor * referencePixels / Double(safe)
        let maxY = maxFactor * referencePixels / Double(safe)
        guard zoomY.isFinite else { return defaultZoomY }
        return min(maxY, max(minY, zoomY))
    }

    static func resetZoomY(resolution: Int) -> Double {
        referencePixels / Double(max(resolution, 1))
    }

    static func zoomIn(_ zoomY: Double, resolution: Int) -> Double {
        clampZoomY(zoomY * step, resolution: resolution)
    }

    static func zoomOut(_ zoomY: Double, resolution: Int) -> Double {
        clampZoomY(zoomY / step, resolution: resolution)
    }

    /// `zoomY *= pow(1.01, numPixels.y())`，再夹紧。
    static func applyPixelDelta(_ zoomY: Double, pixels: Double, resolution: Int) -> Double {
        guard pixels.isFinite else { return clampZoomY(zoomY, resolution: resolution) }
        return clampZoomY(zoomY * pow(pixelStep, pixels), resolution: resolution)
    }

    /// 有像素增量走 `1.01^y`；否则按格 `*1.25` / `/1.25`。一次事件只按符号看方向。
    static func applyWheel(
        zoomY: Double,
        resolution: Int,
        pixelDeltaY: Double,
        hasPrecisePixels: Bool,
        notches: Int
    ) -> Double {
        if hasPrecisePixels && pixelDeltaY != 0 {
            return applyPixelDelta(zoomY, pixels: pixelDeltaY, resolution: resolution)
        }
        if notches > 0 {
            return zoomIn(zoomY, resolution: resolution)
        }
        if notches < 0 {
            return zoomOut(zoomY, resolution: resolution)
        }
        return clampZoomY(zoomY, resolution: resolution)
    }

    static func pixelsPerQuarterBeat(zoomY: Double, resolution: Int) -> CGFloat {
        CGFloat(zoomY * Double(max(resolution, 1)))
    }

    static func zoomY(pixelsPerQuarterBeat: CGFloat, resolution: Int) -> Double {
        BmsONEMasterView.zoomY(pixelsPerQuarterBeat: pixelsPerQuarterBeat, resolution: resolution)
    }

    static func gridHeight(zoomY: Double, resolution: Int) -> Double {
        zoomY * Double(max(resolution, 1)) / referencePixels
    }

    static func load(from defaults: UserDefaults = .standard) -> Double {
        if defaults.object(forKey: settingsKey) == nil {
            return defaultZoomY
        }
        let value = defaults.double(forKey: settingsKey)
        return value.isFinite && value > 0 ? value : defaultZoomY
    }

    static func save(_ zoomY: Double, to defaults: UserDefaults = .standard) {
        defaults.set(zoomY, forKey: settingsKey)
    }
}

/// 对照 `SequenceViewChannelLaneMode` / `ChannelLaneWidth` / `DrawsWaveform`。
/// 设置键是 `SequenceView/SoundChannelLaneMode`，读写 `normal` / `compact` / `simple`。
enum BmsONESoundChannelLaneMode: Equatable, CaseIterable {
    case normal
    case compact
    case simple

    static let menuTitle = BmsONEMainWindowLayout.soundChannelLanesMenuTitle
    static let settingsKey = "SequenceView/SoundChannelLaneMode"
    static let defaultMode = Self.normal

    var title: String {
        switch self {
        case .normal: return BmsONEMainWindowLayout.soundChannelLaneNormalTitle
        case .compact: return BmsONEMainWindowLayout.soundChannelLaneCompactTitle
        case .simple: return BmsONEMainWindowLayout.soundChannelLaneSimpleTitle
        }
    }

    /// `toLower()` 之后对不上就回 Normal。
    var storedValue: String {
        switch self {
        case .normal: return "normal"
        case .compact: return "compact"
        case .simple: return "simple"
        }
    }

    static func parse(_ text: String) -> Self {
        switch text.lowercased() {
        case "normal": return .normal
        case "compact": return .compact
        case "simple": return .simple
        default: return defaultMode
        }
    }

    /// `LargeSoundChannelWidth = 64`；Compact / Simple 是 `SmallSoundChannelWidth = 32`。
    var width: CGFloat {
        switch self {
        case .normal:
            return BmsONESequenceLayout.largeSoundChannelWidth
        case .compact, .simple:
            return BmsONESequenceLayout.smallSoundChannelWidth
        }
    }

    /// SIMPLE 不画波形、也不更新精确可见区。
    var drawsWaveform: Bool {
        self != .simple
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let stored = defaults.string(forKey: settingsKey) else {
            return defaultMode
        }
        return parse(stored)
    }

    static func save(_ mode: Self, to defaults: UserDefaults = .standard) {
        defaults.set(mode.storedValue, forKey: settingsKey)
    }

    /// 原版第一下只改当前声道，不写音。
    static func continuesAfterClick(current: Int?, clicked: Int) -> Bool {
        current == clicked
    }
}

/// 共用谱面右侧每道一列。显示通道是 `CH0`、`CH1`…，避免和 `SC` 抢名字。
enum BmsonSoundLane {
    static func displayChannel(index: Int) -> String {
        "CH\(max(0, index))"
    }

    static func index(display: String) -> Int? {
        let key = display.uppercased()
        guard key.hasPrefix("CH"), let value = Int(key.dropFirst(2)), value >= 0 else {
            return nil
        }
        return value
    }

    static func isVisible(index: Int, shown: [Bool]?) -> Bool {
        guard let shown else { return true }
        return shown.indices.contains(index) && shown[index]
    }

    static func visibleIndices(count: Int, shown: [Bool]?) -> [Int] {
        (0..<max(0, count)).filter { isVisible(index: $0, shown: shown) }
    }
}

/// 对照 `SequenceViewCursor` 底栏文案。共用 iBMSC 状态条，不另做一条 BmsONE 底栏。
/// Real Time 对照 `Document::GetAbsoluteTime`，不加 `stopNotes`。
enum BmsONEStatus {
    static let bgmLane = "BGM"
    static let unknownLane = "?"

    static func absoluteLocation(_ pulse: Int) -> String {
        "\(pulse)"
    }

    /// `bar` 从 `-1` 起，数 `key <= t` 的小节线。`beat` 两位补零。
    /// `ticks` 宽度是分辨率的十进制位数。
    static func compositeLocation(
        pulse: Int,
        bars: [Int64],
        resolution: Int,
        coarseGrid: BmsONEGridSize = .defaultMedium
    ) -> String {
        var bar = -1
        var tb = 0
        for location in bars.sorted() where location <= Int64(pulse) {
            tb = Int(location)
            bar += 1
        }
        let timeBase = UInt(max(resolution, 1))
        var beat = 0
        var tt = 0
        while true {
            tt = tb + Int(coarseGrid.nthGrid(timeBase: timeBase, n: beat))
            if tt > pulse {
                beat -= 1
                tt = tb + Int(coarseGrid.nthGrid(timeBase: timeBase, n: beat))
                break
            }
            beat += 1
            if beat > 1_000_000 {
                break
            }
        }
        let ticks = pulse - tt
        let tickWidth = max(1, String(max(resolution, 1)).count)
        return String(format: "%d:%02d:%0\(tickWidth)d", bar, beat, ticks)
    }

    /// `QString("%0:%1").arg(min).arg(sec, 6, 'f', 3, QChar('0'))`。
    static func realTime(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? seconds : 0
        let minutes = Int(safe / 60.0)
        let sec = safe - Double(minutes) * 60.0
        return String(format: "%d:%06.3f", minutes, sec)
    }

    /// `Document::GetAbsoluteTime`：只看 `initBpm` 和 `bpmNotes`，查询点上的 BPM 还不生效。
    static func absoluteSeconds(
        pulse: Int,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)] = []
    ) -> Double {
        var cursor = 0
        var seconds = 0.0
        var bpm = initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm
        let ticksPerBeat = Double(max(resolution, 1))
        for event in bpmNotes.sorted(by: { $0.y < $1.y }) where event.y < Int64(pulse) {
            seconds += Double(Int(event.y) - cursor) * 60.0 / (bpm * ticksPerBeat)
            cursor = Int(event.y)
            if event.v > 0 {
                bpm = event.v
            }
        }
        return seconds + Double(pulse - cursor) * 60.0 / (bpm * ticksPerBeat)
    }

    static func laneName(_ x: Int64, mode: BmsONEViewMode) -> String {
        if x <= 0 {
            return bgmLane
        }
        return mode.definedLaneName(x) ?? unknownLane
    }

    /// 只有 ViewMode 车道和 BGM（`01` / `B1`）有名字。BPM / STOP / 小节沟槽没有车道。
    static func laneX(channel: String, mode: BmsONEViewMode) -> Int64? {
        let key = channel.uppercased()
        if key == "01" || key == "B1" {
            return 0
        }
        if BmsonSoundLane.index(display: key) != nil {
            return 0
        }
        return mode.channelToLane[key]
    }

    static func range(_ left: String, _ right: String) -> String {
        "\(left) - \(right)"
    }

    /// 对照 `GetAbsoluteLocationRangeString`：`"%0 - %1"`。
    static func absoluteLocationRange(begin: Int, end: Int) -> String {
        range(absoluteLocation(begin), absoluteLocation(end))
    }

    /// 对照 `GetCompositeLocationRangeString`。
    static func compositeLocationRange(
        begin: Int,
        end: Int,
        bars: [Int64],
        resolution: Int,
        coarseGrid: BmsONEGridSize = .defaultMedium
    ) -> String {
        range(
            compositeLocation(pulse: begin, bars: bars, resolution: resolution, coarseGrid: coarseGrid),
            compositeLocation(pulse: end, bars: bars, resolution: resolution, coarseGrid: coarseGrid)
        )
    }

    /// 对照 `GetRealTimeRangeString`。两端各自算 `GetAbsoluteTime`。
    static func realTimeRange(
        begin: Int,
        end: Int,
        initBpm: Double,
        resolution: Int,
        bpmNotes: [(y: Int64, v: Double)] = []
    ) -> String {
        range(
            realTime(absoluteSeconds(pulse: begin, initBpm: initBpm, resolution: resolution, bpmNotes: bpmNotes)),
            realTime(absoluteSeconds(pulse: end, initBpm: initBpm, resolution: resolution, bpmNotes: bpmNotes))
        )
    }

    /// 对照 `EditModeSelectNotesContext`：勾上 Snap 且 `SnappedSelectionInEditMode` 时用 Lower。
    static func rubberBandOriginPulse(
        time: Double,
        snapToGrid: Bool,
        snapSelection: Bool,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> Int {
        let truncated = Int(time)
        if snapToGrid && snapSelection {
            return BmsONESnap.snapToLowerFineGrid(
                time: time,
                bars: bars,
                resolution: resolution,
                fineGrid: fineGrid
            )
        }
        return truncated
    }

    /// 对照演奏区 / BGM / BPM 拖框：`iTime >= origin` 时 `end` 用 Upper，光标跟 `end`。
    static func rubberBandTimes(
        origin: Int,
        time: Double,
        snapToGrid: Bool,
        snapSelection: Bool,
        bars: [Int64],
        resolution: Int,
        fineGrid: BmsONEGridSize
    ) -> (cursor: Int, begin: Int, end: Int) {
        var iTime = Int(time)
        var iTimeUpper = Int(time)
        if snapToGrid && snapSelection {
            iTime = BmsONESnap.snapToLowerFineGrid(
                time: time,
                bars: bars,
                resolution: resolution,
                fineGrid: fineGrid
            )
            iTimeUpper = BmsONESnap.snapToUpperFineGrid(
                time: time,
                bars: bars,
                resolution: resolution,
                fineGrid: fineGrid
            )
        }
        if iTime >= origin {
            return (iTimeUpper, origin, iTimeUpper)
        }
        return (iTime, iTime, origin)
    }

    /// 音符半开区间：`location + length >= begin && location < end`。
    static func containsNote(location: Int64, length: Int64, begin: Int, end: Int) -> Bool {
        location + max(length, 0) >= Int64(begin) && location < Int64(end)
    }

    /// BPM 点选：`location >= begin && location < end`。
    static func containsEvent(location: Int64, begin: Int, end: Int) -> Bool {
        location >= Int64(begin) && location < Int64(end)
    }

    static func isBgmChannel(_ channel: String) -> Bool {
        let key = channel.uppercased()
        if key == "01" { return true }
        guard key.first == "B" else { return false }
        return Int(key.dropFirst()) != nil
    }

    static func isBpmChannel(_ channel: String) -> Bool {
        let key = channel.uppercased()
        return key == "03" || key == "08"
    }

    /// STOP / SCROLL / BGA / 小节沟槽不能开拖框。
    static func rubberBandKind(channel: String, mode: BmsONEViewMode) -> BmsONERubberBandKind? {
        let key = channel.uppercased()
        if isBpmChannel(key) { return .bpm }
        if isBgmChannel(key) { return .bgm }
        if BmsonSoundLane.index(display: key) != nil { return .sound }
        if let lane = laneX(channel: key, mode: mode), lane > 0 {
            return .keys
        }
        return nil
    }

    static func rubberBandChannels(origin: String, current: String, visualOrder: [String]) -> [String] {
        func index(of channel: String) -> Int? {
            visualOrder.firstIndex { $0.caseInsensitiveCompare(channel) == .orderedSame }
        }
        guard let start = index(of: origin), let end = index(of: current) else { return [] }
        let low = min(start, end)
        let high = max(start, end)
        return Array(visualOrder[low...high])
    }

    /// 对照 `X2Lane < 0`：落到该类列的第一列或最后一列。
    static func clampedRubberBandChannel(
        current: String?,
        visualOrder: [String],
        pointX: CGFloat,
        frames: [String: CGRect]
    ) -> String? {
        if let current,
           let match = visualOrder.first(where: { $0.caseInsensitiveCompare(current) == .orderedSame })
        {
            return match
        }
        guard let first = visualOrder.first, let last = visualOrder.last else { return nil }
        if let frame = frames[first], pointX < frame.minX {
            return first
        }
        return last
    }

    /// `ViewMode::NoteName`：`C`…`B` 加 `number/12+1`。
    static func noteName(_ number: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let index = ((number % 12) + 12) % 12
        return names[index] + String(number / 12 + 1)
    }

    static let soundNote = "Sound note"
    static let layeredSoundNote = "Layered sound note"
    static let clickAddSoundNote = "Click to add a sound note"
    static let clickAddBarLine = "Click to add a bar line"
    static let barLine = "Bar line"
    static let temporaryBarLine = "Temporary bar line"
    static let layeredDifferentLengths = "Layered notes have different lengths"
    static let overlappingLongNote = "Overlapping with a long note"

    /// `QString("%1").arg(double)`：整数不带小数。
    static func bpmDisplay(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < Double(Int.max) {
            return "\(Int(value))"
        }
        return String(value)
    }

    static func bpmEvent(_ value: Double) -> String {
        "BPM event: \(bpmDisplay(value))"
    }

    static func clickAddBpmEvent(_ value: Double) -> String {
        "Click to add a BPM event: \(bpmDisplay(value))"
    }

    /// `SetLayeredSoundNotesWithConflict`：错误段前面两个空格，再 `[文案]`。
    static func objectWithErrors(_ base: String, nonuniform: Bool, overlapping: Bool) -> String {
        var text = base
        if nonuniform {
            text += "  [\(layeredDifferentLengths)]"
        }
        if overlapping {
            text += "  [\(overlappingLongNote)]"
        }
        return text
    }

    /// 对照 `FindConflictsByLanes` 在该脉冲、该车道上的旗。
    /// `layered` 只数和命中音同一起点、同一长度的音，对照 `HitTestPlayingPaneMulti`。
    static func soundConflict(
        pulse: Int64,
        lane: Int64,
        hitLength: Int64,
        notes: [(x: Int64, y: Int64, l: Int64)]
    ) -> (layered: Bool, nonuniform: Bool, overlapping: Bool) {
        guard lane > 0 else { return (false, false, false) }
        let covering = notes.filter { note in
            note.x == lane && note.y <= pulse && note.y + max(note.l, 0) >= pulse
        }
        let sameStart = covering.filter { $0.y == pulse }
        let earlier = covering.filter { $0.y < pulse }
        let nonuniform = sameStart.count > 1 && Set(sameStart.map(\.l)).count > 1
        let layered = sameStart.filter { $0.l == hitLength }.count > 1
        let overlapping = !earlier.isEmpty && !sameStart.isEmpty
        return (layered, nonuniform, overlapping)
    }

    static func soundNoteObject(
        pulse: Int64,
        lane: Int64,
        hitLength: Int64,
        notes: [(x: Int64, y: Int64, l: Int64)]
    ) -> String {
        let conflict = soundConflict(pulse: pulse, lane: lane, hitLength: hitLength, notes: notes)
        let base = conflict.layered ? layeredSoundNote : soundNote
        return objectWithErrors(base, nonuniform: conflict.nonuniform, overlapping: conflict.overlapping)
    }

    /// 查询点之前最后一条 BPM；没有则用 init。对照写入时预填的速度。
    static func inferredBpm(
        pulse: Int64,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)]
    ) -> Double {
        var bpm = initBpm > 0 ? initBpm : BmsONEInfoDefaults.initialBpm
        for event in bpmNotes.sorted(by: { $0.y < $1.y }) where event.y < pulse && event.v > 0 {
            bpm = event.v
        }
        return bpm
    }

    static func existingBpm(pulse: Int64, bpmNotes: [(y: Int64, v: Double)]) -> Double? {
        bpmNotes.first { $0.y == pulse }?.v
    }

    /// 共用底栏没有对象区时接到 `FST`。没有对象文案时返回空串，对照 `SetTime`。
    static func objectHint(
        writeMode: Bool,
        channel: String?,
        pulse: Int64,
        hitLength: Int64?,
        inMeasureArea: Bool,
        viewMode: BmsONEViewMode,
        notes: [(x: Int64, y: Int64, l: Int64)],
        explicitBars: Set<Int64>,
        allBars: Set<Int64>,
        initBpm: Double,
        bpmNotes: [(y: Int64, v: Double)]
    ) -> String {
        if let hitLength {
            let lane = channel.flatMap { laneX(channel: $0, mode: viewMode) } ?? 0
            return soundNoteObject(pulse: pulse, lane: lane, hitLength: hitLength, notes: notes)
        }
        if let channel {
            let key = channel.uppercased()
            if key == "03" {
                if let value = existingBpm(pulse: pulse, bpmNotes: bpmNotes) {
                    return bpmEvent(value)
                }
                if writeMode {
                    return clickAddBpmEvent(inferredBpm(pulse: pulse, initBpm: initBpm, bpmNotes: bpmNotes))
                }
                return ""
            }
            if laneX(channel: key, mode: viewMode) != nil {
                return writeMode ? clickAddSoundNote : ""
            }
        }
        if inMeasureArea {
            if allBars.contains(Int64(pulse)) {
                return explicitBars.contains(Int64(pulse)) ? barLine : temporaryBarLine
            }
            return writeMode ? clickAddBarLine : ""
        }
        return ""
    }
}

enum BmsONERubberBandKind: Equatable {
    case keys
    case bgm
    case bpm
    case sound
}

struct BmsONECursor: Equatable {
    var pulse: Int64
    var channel: String?
    var writeMode: Bool
    var inMeasureArea: Bool
    var hitLength: Int64?
    var rangeBegin: Int64? = nil
    var rangeEnd: Int64? = nil

    var hasRange: Bool {
        rangeBegin != nil && rangeEnd != nil
    }
}

struct BmsONEStatusContext {
    var resolution: Int
    var bars: [Int64]
    var explicitBars: [Int64]
    var initBpm: Double
    var bpmNotes: [(y: Int64, v: Double)]
    var viewMode: BmsONEViewMode
    var coarseGrid: BmsONEGridSize
}

/// Beat 7-key playing lanes. `x` is the BmsONE Skin lane, not a BMS channel `11`.
/// Default scratch is on the left (`Skin.cpp` `SetupSkin7k` case 0): `x=8`
/// scratch, then keys `x=1...7`. Display scale uses default `zoomY = 48/240`.
enum BmsONEPlayingLaneLayout {
    /// Left-to-right Skin lane numbers for default Beat 7-key.
    static let beat7kLaneXs: [Int64] = [8, 1, 2, 3, 4, 5, 6, 7]
    static let laneCount = 8
    /// `SequenceView.cpp` default `zoomY` is `48/240` pixels per pulse.
    static let pixelsPerBeat: CGFloat = 48
    /// Working short-note height only. Not measured from a screenshot.
    static let shortNoteHeight: CGFloat = 8
    static let noteHorizontalInset: CGFloat = 1

    static let beat7kLaneWidths: [CGFloat] = [
        BmsONESequenceLayout.scratchWidth,
        BmsONESequenceLayout.whiteKeyWidth,
        BmsONESequenceLayout.blackKeyWidth,
        BmsONESequenceLayout.whiteKeyWidth,
        BmsONESequenceLayout.blackKeyWidth,
        BmsONESequenceLayout.whiteKeyWidth,
        BmsONESequenceLayout.blackKeyWidth,
        BmsONESequenceLayout.whiteKeyWidth
    ]

    static func laneFrames(in playingPane: CGRect) -> [CGRect] {
        var cursor = playingPane.minX + BmsONESequenceLayout.laneMargin
        return beat7kLaneWidths.map { width in
            let frame = CGRect(
                x: cursor,
                y: playingPane.minY,
                width: width,
                height: playingPane.height
            )
            cursor += width
            return frame
        }
    }

    /// BMSON lane `x` under a point in playing-pane coordinates. Margin hits return nil.
    static func laneX(at point: CGPoint, in playingPane: CGRect) -> Int64? {
        let frames = laneFrames(in: playingPane)
        for (index, frame) in frames.enumerated() {
            if point.x >= frame.minX && point.x < frame.maxX
                && point.y >= playingPane.minY && point.y < playingPane.maxY
            {
                return beat7kLaneXs[index]
            }
        }
        return nil
    }

    static func pulseY(at point: CGPoint, in playingPane: CGRect, resolution: Int) -> Int64 {
        let safeResolution = resolution > 0 ? resolution : BmsONEInfoDefaults.resolution
        let fromBottom = playingPane.maxY - point.y
        let beats = fromBottom / pixelsPerBeat
        let pulse = (beats * CGFloat(safeResolution)).rounded()
        return max(0, Int64(pulse))
    }

    static func noteRect(
        x: Int64,
        y: Int64,
        l: Int64,
        resolution: Int,
        in playingPane: CGRect
    ) -> CGRect? {
        let frames = laneFrames(in: playingPane)
        guard let index = beat7kLaneXs.firstIndex(of: x), index < frames.count else { return nil }
        let lane = frames[index]
        let safeResolution = resolution > 0 ? resolution : BmsONEInfoDefaults.resolution
        let startBeat = CGFloat(y) / CGFloat(safeResolution)
        let lengthBeats = CGFloat(max(l, 0)) / CGFloat(safeResolution)
        let height: CGFloat
        if l <= 0 {
            height = shortNoteHeight
        } else {
            height = max(shortNoteHeight, lengthBeats * pixelsPerBeat)
        }
        let bottom = startBeat * pixelsPerBeat
        return CGRect(
            x: lane.minX + noteHorizontalInset,
            y: playingPane.maxY - bottom - height,
            width: max(lane.width - noteHorizontalInset * 2, 1),
            height: height
        )
    }
}

struct BmsONESequenceFrames: Equatable {
    var timeLine: CGRect
    var masterLane: CGRect
    var playingPane: CGRect
    var footerCorner: CGRect
    var footerMaster: CGRect
    var footerPlaying: CGRect
}

enum BmsONEStatusBarLayout {
    static let height = BmsONEMainWindowLayout.statusBarHeight
    static let absoluteLocation = CGSize(width: 120, height: height)
    static let location = CGSize(width: 180, height: height)
    static let realTime = CGSize(width: 160, height: height)
    static let lane = CGSize(width: 100, height: height)
    /// Size hint only; the object section stretches (`StatusBar.cpp:21-22`).
    static let objectHint = CGSize(width: 320, height: height)
}

enum BmsONEDialogLayout {
    static let bmsImportTitle = "BMS Import"
    static let bmsImportSize = CGSize(width: 640, height: 480)
    static let bmsImportNextTitle = "Next"
    static let bmsImportFinishTitle = "Finish"
    static let bmsImportCancelTitle = "Cancel"
    static let bmsImportCloseTitle = "Close"
    static let bmsImportSkipTitle = "Skip Questions"
    static let bmsImportLoading = "Loading BMS..."
    static let bmsImportSucceeded = "Succeeded to import BMS."
    static let bmsImportFailed = "Failed to import BMS."
    static let bmsImportProgressMaximum = 100
    /// 底栏控件是工作框，源码用 sizer，未截图。
    static let bmsImportSkip = CGRect(x: 8, y: 444, width: 160, height: 24)
    static let bmsImportNext = CGRect(x: 472, y: 444, width: 80, height: 28)
    static let bmsImportCancel = CGRect(x: 556, y: 444, width: 76, height: 28)
    static let bmsImportProgress = CGRect(x: 8, y: 96, width: 624, height: 20)
    static let bmsImportMessage = CGRect(x: 8, y: 8, width: 624, height: 80)
    static let bmsImportLog = CGRect(x: 8, y: 124, width: 624, height: 310)
    /// 对照 `AskGameMode` / `AskTextEncoding` / `AskRandomValue`。交互区是工作框，源码用 sizer，未截图。
    static let bmsImportGameModePrompt = "Select game mode:"
    static let bmsImportEncodingPrompt = "Select text encoding:"
    static let bmsImportEncodingDefaultTitle = "(default)"
    static let bmsImportRandomPrompt = "Select random value:"
    static let bmsImportRandomCheckboxTitle = "Random"
    static let bmsImportGameModeOkMark = "O"
    static let bmsImportGameModeErrorMark = "!"
    static let bmsImportGameModePromptFrame = CGRect(x: 8, y: 8, width: 624, height: 18)
    static let bmsImportGameModeColumnWidth: CGFloat = 104
    static let bmsImportGameModeRadioY: CGFloat = 30
    static let bmsImportGameModeMarkY: CGFloat = 52
    static let bmsImportEncodingColumnWidth: CGFloat = 208
    static let bmsImportEncodingRadioY: CGFloat = 30
    static let bmsImportEncodingPreviewY: CGFloat = 54
    static let bmsImportRandomCheckbox = CGRect(x: 8, y: 30, width: 80, height: 20)
    static let bmsImportRandomSlider = CGRect(x: 96, y: 30, width: 420, height: 20)
    static let bmsImportRandomEdit = CGRect(x: 524, y: 28, width: 100, height: 24)
    static let bmsImportPreviewCharacterCount = 1000

    static func encodingRadio(at index: Int) -> CGRect {
        CGRect(
            x: 8 + CGFloat(index) * bmsImportEncodingColumnWidth,
            y: bmsImportEncodingRadioY,
            width: 200,
            height: 20
        )
    }

    static func encodingPreview(at index: Int) -> CGRect {
        CGRect(
            x: 8 + CGFloat(index) * bmsImportEncodingColumnWidth,
            y: bmsImportEncodingPreviewY,
            width: 200,
            height: 70
        )
    }

    static func gameModeRadio(at index: Int) -> CGRect {
        CGRect(
            x: 8 + CGFloat(index) * bmsImportGameModeColumnWidth,
            y: bmsImportGameModeRadioY,
            width: 100,
            height: 20
        )
    }

    static func gameModeMark(at index: Int) -> CGRect {
        CGRect(
            x: 8 + CGFloat(index) * bmsImportGameModeColumnWidth,
            y: bmsImportGameModeMarkY,
            width: 100,
            height: 18
        )
    }
}

/// 对照 `Bms::Mode` / `LongNameOfMode`。
enum BmsONEBmsMode: Int, CaseIterable {
    case mode5k = 0
    case mode7k = 1
    case mode10k = 2
    case mode14k = 3
    case modePms9k = 4
    case modePms5k = 5

    var longName: String {
        switch self {
        case .mode5k: return "5key (BMS)"
        case .mode7k: return "7key (BMS)"
        case .mode10k: return "10key (BMS)"
        case .mode14k: return "14key (BMS)"
        case .modePms9k: return "9key (PMS)"
        case .modePms5k: return "5key (PMS)"
        }
    }

    var modeHint: String {
        switch self {
        case .mode5k: return "beat-5k"
        case .mode7k: return "beat-7k"
        case .mode10k: return "beat-10k"
        case .mode14k: return "beat-14k"
        case .modePms9k: return "popn-9k"
        case .modePms5k: return "popn-5k"
        }
    }
}

struct BmsONEGameModeChoice: Equatable {
    var mode: BmsONEBmsMode
    var hasErrorChannels: Bool

    var longName: String { mode.longName }
    var mark: String {
        hasErrorChannels
            ? BmsONEDialogLayout.bmsImportGameModeErrorMark
            : BmsONEDialogLayout.bmsImportGameModeOkMark
    }
}

/// 对照 `BmsReaderConfig::AvailableCodecs`。空名字是 `(default)`，macOS 上按 UTF-8 解。
enum BmsONETextEncoding: String, CaseIterable {
    case localeDefault = ""
    case shiftJIS = "Shift-JIS"
    case utf8 = "UTF-8"

    var displayName: String {
        rawValue.isEmpty ? BmsONEDialogLayout.bmsImportEncodingDefaultTitle : rawValue
    }

    var nsEncoding: String.Encoding {
        switch self {
        case .localeDefault, .utf8:
            return .utf8
        case .shiftJIS:
            return .shiftJIS
        }
    }

    func decodedString(from data: Data) -> String {
        if let text = String(data: data, encoding: nsEncoding) {
            return text
        }
        return (NSString(data: data, encoding: nsEncoding.rawValue) as String?) ?? ""
    }

    func decode(_ data: Data) -> Data {
        Data(decodedString(from: data).utf8)
    }

    /// `GenerateEncodingPreviewMap`：解码后取前 1000 个字符，再加 `...`。
    func preview(from data: Data) -> String {
        let text = decodedString(from: data)
        return String(text.prefix(BmsONEDialogLayout.bmsImportPreviewCharacterCount)) + "..."
    }
}

/// 对照 `AskGameMode` / `AskTextEncoding` / `AskRandomValue`。
/// Skip Questions 用各问的 `GetDefaultValue()`：编码空串、RANDOM `1`、模式 `GetMode`。
enum BmsONEImportQuestion {
    static let prompt = BmsONEDialogLayout.bmsImportGameModePrompt
    static let encodingPrompt = BmsONEDialogLayout.bmsImportEncodingPrompt
    static let randomPrompt = BmsONEDialogLayout.bmsImportRandomPrompt
    static let defaultEncoding = BmsONETextEncoding.localeDefault
    static let defaultRandomValue = 1

    static func choices(errorByMode: [BmsONEBmsMode: Bool]) -> [BmsONEGameModeChoice] {
        BmsONEBmsMode.allCases.map { mode in
            BmsONEGameModeChoice(mode: mode, hasErrorChannels: errorByMode[mode] ?? false)
        }
    }

    static func resolvedMode(
        skipQuestions: Bool,
        detected: BmsONEBmsMode,
        selected: BmsONEBmsMode
    ) -> BmsONEBmsMode {
        skipQuestions ? detected : selected
    }

    static func resolvedEncoding(
        skipQuestions: Bool,
        selected: BmsONETextEncoding
    ) -> BmsONETextEncoding {
        skipQuestions ? defaultEncoding : selected
    }

    /// `useRandomValues` 默认 false，所以默认值是 `1`，不是随机。
    /// 勾了 Random 时值为 `0`，交给 C++ 在 `1..max` 里取随机数。
    static func resolvedRandomValue(
        skipQuestions: Bool,
        isRandom: Bool,
        selected: Int
    ) -> Int {
        if skipQuestions {
            return defaultRandomValue
        }
        return isRandom ? 0 : selected
    }

    static func defaultRandomValues(maxima: [Int]) -> [Int] {
        Array(repeating: defaultRandomValue, count: maxima.count)
    }
}

extension BmsONEDialogLayout {
    static let gridSettingTitle = "Grid Setting"
    static let gridSettingSize = CGSize(width: 600, height: 400)
    static let exportWavTitle = "Export WAV"
    static let exportWavSize = CGSize(width: 480, height: 320)
    static let preferencesTitle = "Preferences"
    static let preferencesMenuTitle = "Preferences..."
    static let preferencesCloseTitle = "Close"
    static let preferencesGeneralTitle = "General"
    static let preferencesEditTitle = "Edit"
    static let preferencesPreviewTitle = "Preview"
    static let preferencesBmsImportTitle = "BMS Import"
    static let preferencesLanguageTitle = "Language:"
    static let preferencesLanguageRestart = "(Requires restart)"
    static let preferencesSaveFormatTitle = "Save Format:"
    static let preferencesSaveJsonFormatTitle = "Save JSON Format:"
    static let preferencesUIFontTitle = "UI Font:"
    static let preferencesFontResetTitle = "Reset"
    static let preferencesEnableMasterCache = "Enable Master Cache"
    static let preferencesShowMasterLane = "Show Master Lane"
    static let preferencesShowMiniMap = "Show Mini Map"
    static let preferencesFixMiniMap = "Fix Mini Map"
    static let preferencesMiniMapOpacity = "Mini Map Opacity:"
    static let preferencesEditModeGroup = "Edit Mode"
    static let preferencesAlwaysShowCursor = "Always show cursor line"
    static let preferencesSnappedHitTest = "Enable snapped-to-grid hit test of clicks"
    static let preferencesSnappedSelection = "Enable snapped-to-grid selection"
    static let preferencesChannelPreviewGroup = "Sound Channels / Master Channel"
    static let preferencesTimingAdjustment = "Timing Adjustment:"
    static let preferencesSmoothBar = "Smooth bar motion"
    static let preferencesSoundNotesGroup = "Sound Notes"
    static let preferencesMaxDuration = "Max duration:"
    static let preferencesSoftFadeOut = "Soft fade out"
    static let preferencesConfigureViewers = "Configure External Viewers..."
    static let preferencesDefaultColumn = "Default"
    static let preferencesAskColumn = "Ask"
    static let preferencesTextEncoding = "Text Encoding:"
    static let preferencesRandomCommand = "#RANDOM Command:"
    static let preferencesGenerateRandom = "Generate random values"
    static let preferencesGameMode = "Game Mode:"
    static let preferencesTrustPlayer = "Trust #PLAYER command"
    static let preferencesIgnoreExtension = "Ignore file extension"
    static let preferencesPreferExModes = "Prefer 7/14/9key to 5/10/5key."
    static let preferencesMiscellaneous = "Miscellaneous"
    static let preferencesSkipBetweenRandom = "Skip commands between #RANDOM and #IF"
    static let preferencesConversionGroup = "Conversion to Bmson"
    static let preferencesMinimumResolution = "Minimum resolution"
    static let preferencesMaximumResolution = "Maximum resolution"
    /// Source has no `resize`. Working client size. Not a screenshot.
    static let preferencesSize = CGSize(width: 640, height: 420)
    static let preferencesListMinimum = CGSize(width: 80, height: 80)
    static let preferencesListMaximumWidth: CGFloat = 180
    static let preferencesIconSize = CGSize(width: 32, height: 32)
    static let aboutTitle = "About BmsONE"
    static let helpMenuTitle = "Help"
    static let externalViewerTitle = "External Viewer Configuration"
    /// Source has no `resize`. Working client size. Not a screenshot.
    static let externalViewerSize = CGSize(width: 720, height: 440)
    static let externalViewerListMinimum = CGSize(width: 80, height: 80)
    static let externalViewerListMaximumWidth: CGFloat = 200
    static let externalViewerIconSize = CGSize(width: 32, height: 32)
    static let externalViewerButtonIconSize = CGSize(width: 20, height: 20)
    static let externalViewerNameLabel = "Name:"
    static let externalViewerProgramLabel = "Program Path:"
    static let externalViewerDirectoryLabel = "Working Directory:"
    static let externalViewerArgumentsTitle = "Arguments"
    static let externalViewerPlayBegLabel = "Play from Beginning:"
    static let externalViewerPlayHereLabel = "Play from Here:"
    static let externalViewerStopLabel = "Stop:"
    static let externalViewerVariablesTitle = "Defined variables"
    static let externalViewerFilenameVar = "$(filename)"
    static let externalViewerDirectoryVar = "$(directory)"
    static let externalViewerExeDirVar = "$(exedir)"
    static let externalViewerMeasureVar = "$(measure)"
    static let externalViewerTimeVar = "$(time)"
    static let externalViewerTicksVar = "$(ticks)"
    static let externalViewerFilenameDesc = "file name"
    static let externalViewerDirectoryDesc = "document directory"
    static let externalViewerExeDirDesc = "application directory"
    static let externalViewerMeasureDesc = "current measure"
    static let externalViewerTimeDesc = "current time in seconds"
    static let externalViewerTicksDesc = "current time in ticks"
    static let externalViewerNewName = "New Viewer"
    static let externalViewerDefaultDirectory = "$(exedir)"
    static let externalViewerMenuTitle = "Viewer"
    static let externalViewerErrorTitle = "Error"
    static let externalViewerFailed = "Failed to run the viewer."
    /// F5 / F6 / F7 仍走内置预览。外置播放不用原版快捷键。
    static let externalViewerPlayBegMenu = "Play from Beginning (External Viewer)"
    static let externalViewerPlayHereMenu = "Play from Here (External Viewer)"
    static let externalViewerStopMenu = "Stop (External Viewer)"
    static let convertResolutionTitle = "Convert Resolution"
    static let convertResolutionMenuTitle = "Convert Resolution..."
    static let convertResolutionCurrentLabel = "Current resolution:"
    static let convertResolutionNewLabel = "New resolution:"
    static let convertResolutionWarningTitle = "Warning"
    static let convertResolutionWarning =
        "Some information will be lost through this conversion and it is IRREVERSIBLE. Are you sure?"
    static let convertResolutionMinimum = 48
    static let convertResolutionMaximum = 24000
    static let gridSettingMenuTitle = "Grid Setting..."
    static let gridOkTitle = "OK"
    static let gridCancelTitle = "Cancel"
    static let gridRestoreTitle = "Restore Default"
    static let gridColumnDivision = "Division"
    static let gridColumnLength = "Length"
    static let gridColumnLabel = "Label"
    static let gridColumnAux = "Aux. Grid"
    static let gridAddTitle = "+"
    static let gridRemoveTitle = "-"
    static let exportRangeTitle = "Whole Song"
    static let exportOutputTitle = "Output File:"
    static let exportRangeLabel = "Range:"
    static let exportRefreshTitle = "Refresh Master Cache"
    static let exportVolumeTitle = "Volume:"
    static let exportClippingTitle = "Clipping:"
    static let exportButtonTitle = "Export"
    static let exportCloseTitle = "Close"
    static let exportUntitledBase = "NewProject"
    static let exportGainSteps = 200
    static let exportDefaultGain = 100
    static let exportClipTitles = ["Soft Clip", "Hard Clip", "Normalize"]
    static let exportSampleRate = 44100
    static let exportCannotOpen = "Cannot open file."
    static let exportComplete = "Export complete."
    static let exportNoSample = "No sample was given."
}

enum BmsONEResolutionConvert {
    static let minimum = BmsONEDialogLayout.convertResolutionMinimum
    static let maximum = BmsONEDialogLayout.convertResolutionMaximum

    /// `QString::toInt`：整段都是十进制整数才算。
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }

    static func isAllowed(_ value: Int) -> Bool {
        value >= minimum && value <= maximum
    }
}

struct BmsONEGridSize: Equatable {
    static let standardBeats = 4
    static let componentMaximum = 65536

    var numerator: UInt
    var denominator: UInt

    init(denominator: UInt) {
        self.numerator = UInt(Self.standardBeats)
        self.denominator = denominator
    }

    init(numerator: UInt, denominator: UInt) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// `SequenceTools.cpp` `DefaultGrids()`。
    static let defaultPresets: [BmsONEGridSize] = [
        BmsONEGridSize(denominator: 4),
        BmsONEGridSize(denominator: 8),
        BmsONEGridSize(denominator: 12),
        BmsONEGridSize(denominator: 16),
        BmsONEGridSize(denominator: 24),
        BmsONEGridSize(denominator: 32),
        BmsONEGridSize(denominator: 48),
        BmsONEGridSize(denominator: 64),
        BmsONEGridSize(denominator: 192)
    ]

    static let defaultMedium = BmsONEGridSize(numerator: 4, denominator: 4)
    static let fallbackFine = BmsONEGridSize(denominator: 16)

    /// `SequenceDef.h` `operator==`：交叉相乘。
    static func == (lhs: BmsONEGridSize, rhs: BmsONEGridSize) -> Bool {
        lhs.numerator * rhs.denominator == lhs.denominator * rhs.numerator
    }

    /// `GridSetting::TextForGridSize`。
    var displayText: String {
        let coarsest = BmsONEGridSize(numerator: UInt(Self.standardBeats), denominator: 1)
        if numerator != 0, self <= coarsest {
            return String(Self.standardBeats * Int(denominator) / Int(numerator))
        }
        return "(\(numerator))\(denominator)"
    }

    /// 标准 4 拍小节里有多少条线。对不上整数时是 `nil`。接到共用 `CGDivide` / `CGSub`。
    var linesPerMeasure: Int? {
        let coarsest = BmsONEGridSize(numerator: UInt(Self.standardBeats), denominator: 1)
        guard numerator != 0, self <= coarsest else { return nil }
        return Self.standardBeats * Int(denominator) / Int(numerator)
    }

    static func <= (lhs: BmsONEGridSize, rhs: BmsONEGridSize) -> Bool {
        let small = lhs.numerator * rhs.denominator
        let big = lhs.denominator * rhs.numerator
        return small != 0 && big % small == 0
    }

    /// `SequenceDef.h` `IsIntervalInteger`：`timeBase * n` 能整除 `d`。
    func isIntervalInteger(timeBase: UInt) -> Bool {
        guard denominator != 0 else { return false }
        return (UInt64(timeBase) * UInt64(numerator)) % UInt64(denominator) == 0
    }

    /// `SequenceDef.h` `Interval`：先把 `timeBase * n` 转成实数再除。
    func interval(timeBase: UInt) -> Double {
        guard denominator != 0 else { return 0 }
        return Double(UInt64(timeBase) * UInt64(numerator)) / Double(denominator)
    }

    /// `SequenceDef.h` `NthGrid`：`n * timeBase * n / d` 用整数除法，再转成实数。
    func nthGrid(timeBase: UInt, n: Int) -> Double {
        guard denominator != 0 else { return 0 }
        let product = Int64(n) * Int64(timeBase) * Int64(numerator)
        return Double(product / Int64(denominator))
    }

    /// `SequenceDef.h` `GridNumber`：`int(time * d / (timeBase * n))`，向零取整。
    func gridNumber(timeBase: UInt, time: Double) -> Int {
        let span = Double(timeBase) * Double(numerator)
        guard time.isFinite, span != 0 else { return 0 }
        return Int(time * Double(denominator) / span)
    }
}

/// 对照 `GridSetting` / `SequenceTools::GridSetting` / `UpdateSmallGrid`。
/// 不改谱。确定后写预设，并把当前细格 / 辅助格接到 `CGDivide` / `CGSub`。
struct BmsONEGridSettingDraft: Equatable {
    var grids: [BmsONEGridSize]
    var medium: BmsONEGridSize

    static func makeDefault() -> BmsONEGridSettingDraft {
        BmsONEGridSettingDraft(grids: BmsONEGridSize.defaultPresets, medium: .defaultMedium)
    }

    /// `insertRows`：复制当前行；没有行则用 `GridSize(16)`。
    func inserting(at row: Int) -> BmsONEGridSettingDraft {
        let index = max(0, min(row, grids.count))
        let copy: BmsONEGridSize
        if index < grids.count {
            copy = grids[index]
        } else if index > 0 {
            copy = grids[index - 1]
        } else {
            copy = .fallbackFine
        }
        var next = grids
        next.insert(copy, at: index)
        return BmsONEGridSettingDraft(grids: next, medium: medium)
    }

    func removing(at row: Int) -> BmsONEGridSettingDraft? {
        guard row >= 0, row < grids.count else { return nil }
        var next = grids
        next.remove(at: row)
        return BmsONEGridSettingDraft(grids: next, medium: medium)
    }

    func restoringDefault() -> BmsONEGridSettingDraft {
        .makeDefault()
    }

    func selectingMedium(at row: Int) -> BmsONEGridSettingDraft? {
        guard row >= 0, row < grids.count else { return nil }
        return BmsONEGridSettingDraft(grids: grids, medium: grids[row])
    }

    func settingDenominator(at row: Int, value: Int) -> BmsONEGridSettingDraft? {
        guard let component = BmsONEGridSetting.parseComponent(value), row >= 0, row < grids.count else {
            return nil
        }
        var next = grids
        next[row].denominator = component
        return BmsONEGridSettingDraft(grids: next, medium: medium)
    }

    func settingNumerator(at row: Int, value: Int) -> BmsONEGridSettingDraft? {
        guard let component = BmsONEGridSetting.parseComponent(value), row >= 0, row < grids.count else {
            return nil
        }
        var next = grids
        next[row].numerator = component
        return BmsONEGridSettingDraft(grids: next, medium: medium)
    }
}

struct BmsONEGridApplyResult: Equatable {
    var grids: [BmsONEGridSize]
    var medium: BmsONEGridSize
    var fineGrid: BmsONEGridSize
    var division: Int
    var subDivision: Int
}

enum BmsONEGridSetting {
    static let defaultsKey = "org.ibmsc.native.bmsone.grids"
    static let fallbackDivision = 16

    static func parseComponent(_ value: Int) -> UInt? {
        guard value >= 1, value <= BmsONEGridSize.componentMaximum else { return nil }
        return UInt(value)
    }

    static func serialize(_ grids: [BmsONEGridSize]) -> String {
        let objects: [[String: Int]] = grids.map { grid in
            ["d": Int(grid.denominator), "n": Int(grid.numerator)]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: []),
              let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    /// `DeserializeGrids`。`n` / `d` 为 0 的丢掉。空数组回到默认。
    static func deserialize(_ text: String) -> [BmsONEGridSize] {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return BmsONEGridSize.defaultPresets
        }
        var grids: [BmsONEGridSize] = []
        for object in raw {
            let denominator = intValue(object["d"])
            let numerator = intValue(object["n"])
            if denominator != 0, numerator != 0 {
                grids.append(BmsONEGridSize(numerator: UInt(numerator), denominator: UInt(denominator)))
            }
        }
        return grids.isEmpty ? BmsONEGridSize.defaultPresets : grids
    }

    static func load(from defaults: UserDefaults) -> [BmsONEGridSize] {
        guard let text = defaults.string(forKey: defaultsKey) else {
            return BmsONEGridSize.defaultPresets
        }
        return deserialize(text)
    }

    static func save(_ grids: [BmsONEGridSize], to defaults: UserDefaults) {
        defaults.set(serialize(grids), forKey: defaultsKey)
    }

    /// 空列表按源码换成默认。当前细格不在列表里则落到 `16` 或第一项。
    static func accepted(draft: BmsONEGridSettingDraft, currentDivision: Int) -> BmsONEGridApplyResult {
        let grids = draft.grids.isEmpty ? BmsONEGridSize.defaultPresets : draft.grids
        let small = resolvedSmall(currentDivision: currentDivision, in: grids)
        let division = clampEditorGrid(small.linesPerMeasure ?? currentDivision)
        let subDivision = clampEditorGrid(draft.medium.linesPerMeasure ?? BmsONEGridSize.standardBeats)
        return BmsONEGridApplyResult(
            grids: grids,
            medium: draft.medium,
            fineGrid: small,
            division: division,
            subDivision: subDivision
        )
    }

    static func resolvedSmall(currentDivision: Int, in grids: [BmsONEGridSize]) -> BmsONEGridSize {
        let current = BmsONEGridSize(denominator: UInt(max(1, currentDivision)))
        if grids.contains(current) { return current }
        if grids.contains(.fallbackFine) { return .fallbackFine }
        return grids[0]
    }

    private static func clampEditorGrid(_ value: Int) -> Int {
        min(1920, max(1, value))
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let number = raw as? Int { return number }
        if let number = raw as? NSNumber { return number.intValue }
        return 0
    }
}

enum BmsONEExportWav {
    static func suggestedBaseName(filePath: String?) -> String {
        guard let filePath, !filePath.isEmpty else {
            return BmsONEDialogLayout.exportUntitledBase
        }
        let base = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        return base.isEmpty ? BmsONEDialogLayout.exportUntitledBase : base
    }

    static func uniqueOutputURL(directory: URL, base: String, exists: (URL) -> Bool) -> URL {
        var url = directory.appendingPathComponent(base + ".wav")
        var index = 1
        while exists(url) {
            url = directory.appendingPathComponent("\(base)_\(index).wav")
            index += 1
        }
        return url
    }
}

enum BmsONEInfoDefaults {
    static let modeHint = "beat-7k"
    static let resolution = 240
    static let judgeRank = 100.0
    static let total = 100.0
    static let initialBpm = 120.0
    static let level = 1
    static let subartistsHint = CGSize(width: 200, height: 60)
    static let extraFieldsHint = CGSize(width: 200, height: 180)

    static func loadShowExtraFields(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: BmsONEMainWindowLayout.infoShowExtraFieldsKey) as? Bool ?? false
    }

    static func storeShowExtraFields(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: BmsONEMainWindowLayout.infoShowExtraFieldsKey)
    }
}

/// Read-only BmsONE document surface. This is not `BmsDocument`.
protocol BmsONEDocumentModel: AnyObject {
    var filePath: String? { get }
    var isModified: Bool { get }
    var title: String { get }
    var initialBpm: Double { get }
}

/// Empty BMSON document. Defaults match `ibms::BmsonDocument::empty()`.
final class BmsONEEmptyDocument: BmsONEDocumentModel {
    var filePath: String? { nil }
    var isModified: Bool { false }
    var title: String { "" }
    var initialBpm: Double { BmsONEInfoDefaults.initialBpm }
    var modeHint: String { BmsONEInfoDefaults.modeHint }
    var resolution: Int { BmsONEInfoDefaults.resolution }
    var judgeRank: Double { BmsONEInfoDefaults.judgeRank }
    var total: Double { BmsONEInfoDefaults.total }
    var level: Int { BmsONEInfoDefaults.level }
}

/// 对照 `Document::UpdateTotalLength`、`MiniMapView`、`MasterLaneView`。
/// 几何和颜色可测。逐 tick 的均方在 `BmsONEMasterWaveform`。
enum BmsONEMasterView {
    static let extraEmptyBars = 32
    static let beatsPerBar = 4
    static let masterLaneWidth: CGFloat = 64
    static let miniMapWidth: CGFloat = 50
    static let popInMargin: CGFloat = 8
    static let defaultPixelsPerQuarterBeat: CGFloat = 48
    static let masterBackground: UInt32 = 0xFF222222
    static let miniMapBackground: UInt32 = 0xFF333333
    static let viewportFill: UInt32 = 0x80FFFFFF
    static let peakAvailable: UInt32 = 0xFF009900
    static let peakMissing: UInt32 = 0xFF666666
    static let rmsAvailable: UInt32 = 0xFF66CC66
    static let rmsMasterMissing: UInt32 = 0xFF999999
    static let rmsMiniMissing: UInt32 = 0xFFCCCCCC

    static func viewLength(actualLength: Int, resolution: Int) -> Int {
        actualLength + extraEmptyBars * beatsPerBar * max(resolution, 1)
    }

    static func actualLength(notes: [(y: Int64, l: Int64)]) -> Int {
        notes.map { Int($0.y + $0.l) }.max() ?? 0
    }

    static func zoomY(pixelsPerQuarterBeat: CGFloat, resolution: Int) -> Double {
        Double(pixelsPerQuarterBeat) / Double(max(resolution, 1))
    }

    static func peakColor(available: Bool) -> UInt32 {
        available ? peakAvailable : peakMissing
    }

    static func rmsColor(available: Bool, miniMap: Bool) -> UInt32 {
        if available { return rmsAvailable }
        return miniMap ? rmsMiniMissing : rmsMasterMissing
    }

    /// `UpdateBuffer`：`t = y * viewLength / height`。y 从顶往下，时间 0 在底。
    static func miniMapTime(y: Int, height: Int, viewLength: Int) -> Int {
        guard height > 0 else { return 0 }
        return y * viewLength / height
    }

    /// 点击：`(height - y) * viewLength / height`。
    static func miniMapClickTime(y: Int, height: Int, viewLength: Int) -> Int {
        guard height > 0 else { return 0 }
        return (height - y) * viewLength / height
    }

    /// `int ds = dy * zoomY * viewLength / height`。滚动条单位是像素。
    static func miniMapScrollDelta(dy: Int, zoomY: Double, viewLength: Int, height: Int) -> Int {
        guard height > 0 else { return 0 }
        return Int(Double(dy) * zoomY * Double(viewLength) / Double(height))
    }

    /// `tBegin` 是视口底、`tEnd` 是视口顶。返回 Qt 坐标：`yEnd` 靠上。
    static func viewportBar(
        tBegin: Double,
        tEnd: Double,
        height: Int,
        viewLength: Int
    ) -> (yEnd: Int, yBegin: Int) {
        guard height > 0, viewLength > 0 else { return (0, 0) }
        let yBegin = Int(Double(height) - tBegin * Double(height) / Double(viewLength))
        let yEnd = Int(Double(height) - tEnd * Double(height) / Double(viewLength))
        return (yEnd, yBegin)
    }

    static func showsUnpinnedMiniMap(mouseX: CGFloat, boundsWidth: CGFloat, pinned: Bool) -> Bool {
        if pinned { return true }
        return mouseX >= boundsWidth - miniMapWidth - popInMargin
    }
}

/// 对照 `ViewMode.cpp` `PrepareModeLibrary` / `GetViewMode` / `GetAllViewModes`。
/// 只改显示和点选，不写 `info.modeHint`。共用 iBMSC 列，不为 24k 另做序列窗。
enum BmsONEViewModeKind: String, Equatable {
    case beat5k
    case beat7k
    case beat10k
    case beat14k
    case popn5k
    case popn9k
    case circularSingle
    case circularDouble
    case generic6
    case generic7
    case keyboard24Single
    case keyboard24Double
    case keyboard36
    case keyboard48
    case keyboard60
    case plain
}

struct BmsONEViewMode: Equatable {
    var kind: BmsONEViewModeKind

    static let menuTitle = BmsONEMainWindowLayout.viewModeMenuTitle

    /// 共用 1P + 2P 列，顺序对照 `ChartLanes`。
    static let sharedPlayChannels = [
        "16", "11", "12", "13", "14", "15", "18", "19",
        "21", "22", "23", "24", "25", "28", "29", "26"
    ]

    /// `GetAllViewModes()`：按第一次 `AddViewMode` 的对象顺序，不含 hidden。
    static let menuModes: [BmsONEViewMode] = [
        BmsONEViewMode(kind: .beat7k),
        BmsONEViewMode(kind: .beat14k),
        BmsONEViewMode(kind: .beat5k),
        BmsONEViewMode(kind: .beat10k),
        BmsONEViewMode(kind: .popn5k),
        BmsONEViewMode(kind: .popn9k),
        BmsONEViewMode(kind: .circularSingle),
        BmsONEViewMode(kind: .circularDouble),
        BmsONEViewMode(kind: .generic6),
        BmsONEViewMode(kind: .generic7),
        BmsONEViewMode(kind: .keyboard24Single),
        BmsONEViewMode(kind: .keyboard24Double)
    ]

    /// `GetAllModeHints()`：只含 `AddViewMode`，不含 hidden。
    static let menuHints: [String] = [
        "beat-7k",
        "beat-14k",
        "beat-7k-battle",
        "beat-5k",
        "beat-10k",
        "beat-5k-battle",
        "popn-5k",
        "popn-9k",
        "circularrhythm-single",
        "circularrhythm-double",
        "generic-6keys",
        "generic-7keys",
        "keyboard-24k",
        "keyboard-24k-double"
    ]

    var name: String {
        switch kind {
        case .beat5k: return "Beat 5-key"
        case .beat7k: return "Beat 7-key"
        case .beat10k: return "Beat 10-key"
        case .beat14k: return "Beat 14-key"
        case .popn5k: return "Pop 5-key"
        case .popn9k: return "Pop 9-key"
        case .circularSingle: return "CircularRhythm-single"
        case .circularDouble: return "CircularRhythm-double"
        case .generic6: return "Generic 6 Keys"
        case .generic7: return "Generic 7 Keys"
        case .keyboard24Single: return "Keyboard 24-key (single)"
        case .keyboard24Double: return "Keyboard 24-key (double)"
        case .keyboard36: return "Keyboard 36-key (single)"
        case .keyboard48: return "Keyboard 48-key (single)"
        case .keyboard60: return "Keyboard 60-key (single)"
        case .plain: return "Plain"
        }
    }

    var inMenu: Bool {
        switch kind {
        case .keyboard36, .keyboard48, .keyboard60, .plain:
            return false
        default:
            return true
        }
    }

    var canonicalHint: String {
        switch kind {
        case .beat5k: return "beat-5k"
        case .beat7k: return "beat-7k"
        case .beat10k: return "beat-10k"
        case .beat14k: return "beat-14k"
        case .popn5k: return "popn-5k"
        case .popn9k: return "popn-9k"
        case .circularSingle: return "circularrhythm-single"
        case .circularDouble: return "circularrhythm-double"
        case .generic6: return "generic-6keys"
        case .generic7: return "generic-7keys"
        case .keyboard24Single: return "keyboard-24k"
        case .keyboard24Double: return "keyboard-24k-double"
        case .keyboard36: return "keyboard-36k"
        case .keyboard48: return "keyboard-48k"
        case .keyboard60: return "keyboard-60k"
        case .plain: return ""
        }
    }

    /// `GetViewMode`：精确匹配 hint；空串是 Beat 7-key；未知是 Plain。
    static func resolve(_ modeHint: String) -> BmsONEViewMode {
        if modeHint.isEmpty {
            return BmsONEViewMode(kind: .beat7k)
        }
        switch modeHint {
        case "beat-7k":
            return BmsONEViewMode(kind: .beat7k)
        case "beat-14k", "beat-7k-battle":
            return BmsONEViewMode(kind: .beat14k)
        case "beat-5k":
            return BmsONEViewMode(kind: .beat5k)
        case "beat-10k", "beat-5k-battle":
            return BmsONEViewMode(kind: .beat10k)
        case "popn-5k":
            return BmsONEViewMode(kind: .popn5k)
        case "popn-9k":
            return BmsONEViewMode(kind: .popn9k)
        case "circularrhythm-single":
            return BmsONEViewMode(kind: .circularSingle)
        case "circularrhythm-double":
            return BmsONEViewMode(kind: .circularDouble)
        case "generic-6keys":
            return BmsONEViewMode(kind: .generic6)
        case "generic-7keys":
            return BmsONEViewMode(kind: .generic7)
        case "keyboard-24k", "keyboard-24k-single":
            return BmsONEViewMode(kind: .keyboard24Single)
        case "keyboard-24k-double":
            return BmsONEViewMode(kind: .keyboard24Double)
        case "keyboard-36k", "keyboard-36k-single":
            return BmsONEViewMode(kind: .keyboard36)
        case "keyboard-48k", "keyboard-48k-single":
            return BmsONEViewMode(kind: .keyboard48)
        case "keyboard-60k", "keyboard-60k-single":
            return BmsONEViewMode(kind: .keyboard60)
        default:
            return BmsONEViewMode(kind: .plain)
        }
    }

    /// Skin 键盘列从左到右，给搬列找空位。只含能接到共用列的 `x`。
    var keyLanes: [Int64] {
        switch kind {
        case .beat5k:
            return [8, 1, 2, 3, 4, 5]
        case .beat7k:
            return [8, 1, 2, 3, 4, 5, 6, 7]
        case .beat10k:
            return [8, 1, 2, 3, 4, 5, 16, 9, 10, 11, 12, 13]
        case .beat14k:
            return [8, 1, 2, 3, 4, 5, 6, 7, 16, 9, 10, 11, 12, 13, 14, 15]
        case .popn5k, .circularSingle:
            return [1, 2, 3, 4, 5]
        case .popn9k, .circularDouble:
            return [1, 2, 3, 4, 5, 6, 7, 8, 9]
        case .generic6:
            return [1, 2, 3, 4, 5, 6]
        case .generic7:
            return [1, 2, 3, 4, 5, 6, 7]
        case .keyboard24Double:
            return [1, 2, 3, 4, 5, 6, 7, 8, 27, 28, 29, 30, 31, 32, 33, 34]
        case .keyboard24Single, .keyboard36, .keyboard48, .keyboard60, .plain:
            return [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
        }
    }

    var laneToChannel: [Int64: String] {
        var map: [Int64: String] = [0: "01"]
        switch kind {
        case .beat5k:
            Self.assignBeatKeys(&map, keys: 1...5, scratch: 8, player2: false, extraKeys: false)
        case .beat7k:
            Self.assignBeatKeys(&map, keys: 1...5, scratch: 8, player2: false, extraKeys: true)
        case .beat10k:
            Self.assignBeatKeys(&map, keys: 1...5, scratch: 8, player2: true, extraKeys: false)
        case .beat14k:
            Self.assignBeatKeys(&map, keys: 1...5, scratch: 8, player2: true, extraKeys: true)
        case .popn5k, .circularSingle:
            Self.assignSequential(&map, lanes: 1...5, channels: ["11", "12", "13", "14", "15"])
        case .popn9k, .circularDouble:
            Self.assignSequential(
                &map,
                lanes: 1...9,
                channels: ["11", "12", "13", "14", "15", "18", "19", "16", "21"]
            )
        case .generic6:
            Self.assignSequential(&map, lanes: 1...6, channels: ["11", "12", "13", "14", "15", "18"])
        case .generic7:
            Self.assignSequential(
                &map,
                lanes: 1...7,
                channels: ["11", "12", "13", "14", "15", "18", "19"]
            )
        case .keyboard24Double:
            Self.assignSequential(
                &map,
                lanes: 1...8,
                channels: Array(Self.sharedPlayChannels.prefix(8))
            )
            Self.assignSequential(
                &map,
                lanes: 27...34,
                channels: Array(Self.sharedPlayChannels.suffix(8))
            )
        case .keyboard24Single, .keyboard36, .keyboard48, .keyboard60, .plain:
            Self.assignSequential(&map, lanes: 1...16, channels: Self.sharedPlayChannels)
        }
        return map
    }

    var channelToLane: [String: Int64] {
        var map: [String: Int64] = [:]
        for (lane, channel) in laneToChannel {
            map[channel] = lane
        }
        return map
    }

    var visiblePlayChannels: Set<String> {
        Set(laneToChannel.values.filter { $0 != "01" })
    }

    var hiddenPlayChannels: Set<String> {
        Set(Self.sharedPlayChannels).subtracting(visiblePlayChannels)
    }

    var showsTwoPlayer: Bool {
        visiblePlayChannels.contains { channel in
            ["21", "22", "23", "24", "25", "26", "28", "29"].contains(channel)
        }
    }

    /// `ViewMode.cpp` 各模式 `lanes.insert` 的 `tr(...)`。没有定义的 `x` 是 `nil`。
    func definedLaneName(_ x: Int64) -> String? {
        switch kind {
        case .beat5k:
            return beatLaneName(x, keys: 1...5, extra: false, twoPlayer: false)
        case .beat7k:
            return beatLaneName(x, keys: 1...7, extra: true, twoPlayer: false)
        case .beat10k:
            return beatLaneName(x, keys: 1...5, extra: false, twoPlayer: true)
        case .beat14k:
            return beatLaneName(x, keys: 1...7, extra: true, twoPlayer: true)
        case .popn5k:
            return (1...Int64(5)).contains(x) ? "Key \(x)" : nil
        case .popn9k:
            return (1...Int64(9)).contains(x) ? "Key \(x)" : nil
        case .circularSingle:
            switch x {
            case 1: return "Key Red"
            case 2: return "Key Yellow"
            case 3: return "Key Green"
            case 4: return "Key Blue"
            case 5: return "Space"
            default: return nil
            }
        case .circularDouble:
            switch x {
            case 1: return "Left Key Red"
            case 2: return "Left Key Yellow"
            case 3: return "Left Key Green"
            case 4: return "Left Key Blue"
            case 5: return "Right Key Red"
            case 6: return "Right Key Yellow"
            case 7: return "Right Key Green"
            case 8: return "Right Key Blue"
            case 9: return "Space"
            default: return nil
            }
        case .generic6:
            return (1...Int64(6)).contains(x) ? "Key \(x)" : nil
        case .generic7:
            return (1...Int64(7)).contains(x) ? "Key \(x)" : nil
        case .keyboard24Single:
            return keyboardSingleName(x, keys: 24)
        case .keyboard36:
            return keyboardSingleName(x, keys: 36)
        case .keyboard48:
            return keyboardSingleName(x, keys: 48)
        case .keyboard60:
            return keyboardSingleName(x, keys: 60)
        case .keyboard24Double:
            if (1...Int64(24)).contains(x) {
                return "P1 Key \(BmsONEStatus.noteName(Int(x - 1)))"
            }
            if x == 25 { return "P1 Wheel Up" }
            if x == 26 { return "P1 Wheel Down" }
            if (27...Int64(50)).contains(x) {
                return "P2 Key \(BmsONEStatus.noteName(Int(x - 27)))"
            }
            if x == 51 { return "P2 Wheel Up" }
            if x == 52 { return "P2 Wheel Down" }
            return nil
        case .plain:
            return (1...Int64(99)).contains(x) ? "Lane \(x)" : nil
        }
    }

    private func beatLaneName(
        _ x: Int64,
        keys: ClosedRange<Int64>,
        extra: Bool,
        twoPlayer: Bool
    ) -> String? {
        let prefix = twoPlayer ? "P1 " : ""
        if keys.contains(x) {
            return "\(prefix)Key \(x)"
        }
        if x == 8 {
            return twoPlayer ? "P1 Scratch" : "Scratch"
        }
        if twoPlayer {
            let second: ClosedRange<Int64> = extra ? 9...15 : 9...13
            if second.contains(x) {
                return "P2 Key \(x - 8)"
            }
            if x == 16 {
                return "P2 Scratch"
            }
        }
        return nil
    }

    private func keyboardSingleName(_ x: Int64, keys: Int) -> String? {
        if (1...keys).contains(Int(x)) {
            return "Key \(BmsONEStatus.noteName(Int(x - 1)))"
        }
        if x == Int64(keys + 1) { return "Wheel Up" }
        if x == Int64(keys + 2) { return "Wheel Down" }
        return nil
    }

    private static func assignBeatKeys(
        _ map: inout [Int64: String],
        keys: ClosedRange<Int64>,
        scratch: Int64,
        player2: Bool,
        extraKeys: Bool
    ) {
        let first = ["11", "12", "13", "14", "15"]
        for (offset, lane) in keys.enumerated() {
            map[lane] = first[offset]
        }
        map[scratch] = "16"
        if extraKeys {
            map[6] = "18"
            map[7] = "19"
        }
        if player2 {
            map[9] = "21"
            map[10] = "22"
            map[11] = "23"
            map[12] = "24"
            map[13] = "25"
            map[16] = "26"
            if extraKeys {
                map[14] = "28"
                map[15] = "29"
            }
        }
    }

    private static func assignSequential(
        _ map: inout [Int64: String],
        lanes: ClosedRange<Int64>,
        channels: [String]
    ) {
        for (offset, lane) in lanes.enumerated() where offset < channels.count {
            map[lane] = channels[offset]
        }
    }
}
