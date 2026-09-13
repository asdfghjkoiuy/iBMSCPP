import Foundation

/// BmsONE Preferences keys. Contrasts `App` / `BmsonIO` / `EditConfig` / `PreviewConfig` / `BmsReaderConfig`.
enum BmsONEPreferenceKey {
    static let language = "Language"
    static let saveFormat = "File/SaveFormat"
    static let saveJsonFormat = "File/SaveJsonFormat"
    static let uiFont = "UIFont"
    static let uiFontIsDefault = "UIFontIsDefault"
    static let enableMasterChannel = "Edit/EnableMasterChannel"
    static let showMasterLane = "SequenceView/ShowMasterLane"
    static let showMiniMap = "SequenceView/ShowMiniMap"
    static let fixMiniMap = "SequenceView/FixMiniMap"
    static let miniMapOpacity = "SequenceView/MiniMapOpacity"
    static let snappedHitTestInEditMode = "SequenceView/SnappedHitTestInEditMode"
    static let alwaysShowCursorLineInEditMode = "SequenceView/AlwaysShowCursorLineInEditMode"
    static let snappedSelectionInEditMode = "SequenceView/SnappedSelectionInEditMode"
    static let previewDelayRatio = "Preview/DelayRatio"
    static let previewSmoothing = "Preview/Smoothing"
    static let singleMaxDuration = "Preview/SingleMaxDuration"
    static let singleSoftFadeOut = "Preview/SingleSoftFadeOut"
    static let askTextEncoding = "BmsReader/AskTextEncoding"
    static let askRandomValues = "BmsReader/AskRandomValues"
    static let askGameMode = "BmsReader/AskGameMode"
    static let defaultTextEncoding = "BmsReader/DefaultTextEncoding"
    static let useRandomValues = "BmsReader/UseRandomValues"
    static let trustPlayerCommand = "BmsReader/TrustPlayerCommand"
    static let ignoreExtension = "BmsReader/IgnoreExtension"
    static let preferExModes = "BmsReader/PreferExModes"
    static let minimumResolution = "BmsReader/MinimumResolution"
    static let maximumResolution = "BmsReader/MaximumResolution"
    static let skipBetweenRandomAndIf = "BmsReader/SkipBetweenRandomAndIf"
}

/// BMS Import flags that `GetMode` / `apply_bms_random` / Ask* already understand.
struct BmsONEImportOptions: Equatable {
    var trustPlayerCommand = false
    var ignoreExtension = false
    var preferExModes = false
    var skipBetweenRandomAndIf = false
    var askTextEncoding = true
    var askRandomValues = true
    var askGameMode = true
    var defaultTextEncoding = BmsONETextEncoding.localeDefault
    var useRandomValues = false

    func shouldAskEncoding(skipQuestions: Bool) -> Bool {
        askTextEncoding && !skipQuestions
    }

    func shouldAskRandom(skipQuestions: Bool) -> Bool {
        askRandomValues && !skipQuestions
    }

    func shouldAskGameMode(skipQuestions: Bool) -> Bool {
        askGameMode && !skipQuestions
    }

    func resolvedEncoding(skipQuestions: Bool, selected: BmsONETextEncoding) -> BmsONETextEncoding {
        if skipQuestions || !askTextEncoding {
            return defaultTextEncoding
        }
        return selected
    }

    func resolvedRandomValue(skipQuestions: Bool, isRandom: Bool, selected: Int) -> Int {
        if skipQuestions || !askRandomValues {
            return useRandomValues ? 0 : BmsONEImportQuestion.defaultRandomValue
        }
        return isRandom ? 0 : selected
    }

    func defaultRandomValues(maxima: [Int]) -> [Int] {
        Array(
            repeating: useRandomValues ? 0 : BmsONEImportQuestion.defaultRandomValue,
            count: maxima.count
        )
    }
}

/// Stored Preferences. Close writes; show reads. No `resize` in source.
struct BmsONEPreferences: Equatable {
    var languageKey = ""
    var saveFormat = "Default"
    var saveJsonFormat = "Default"
    var uiFontDefault = true
    var uiFontFamily = ""
    var uiFontPointSize = 0.0
    var enableMasterChannel = true
    var showMasterLane = true
    var showMiniMap = true
    var fixMiniMap = false
    var miniMapOpacity = 0.67
    var snappedHitTestInEditMode = false
    var alwaysShowCursorLineInEditMode = false
    var snappedSelectionInEditMode = true
    var previewDelayRatio = 1.0
    var previewSmoothing = true
    var singleMaxDuration = 0.0
    var singleSoftFadeOut = true
    var askTextEncoding = true
    var askRandomValues = true
    var askGameMode = true
    var defaultTextEncodingKey = ""
    var useRandomValues = false
    var trustPlayerCommand = false
    var ignoreExtension = false
    var preferExModes = false
    var minimumResolution = 240
    var maximumResolution = 10000
    var skipBetweenRandomAndIf = false

    var languageIndex: Int { BmsONEPreferenceFormat.languageIndex(languageKey) }

    var defaultTextEncoding: BmsONETextEncoding {
        BmsONEPreferenceFormat.encoding(from: defaultTextEncodingKey)
    }

    var canShowMasterLane: Bool { enableMasterChannel && showMasterLane }
    var canShowMiniMap: Bool { enableMasterChannel && showMiniMap }
    var miniMapGroupEnabled: Bool { enableMasterChannel && showMiniMap }
    var miniMapOpacityEnabled: Bool { !fixMiniMap && showMiniMap && enableMasterChannel }
    var masterGroupEnabled: Bool { enableMasterChannel }
    var singleSoftFadeOutEnabled: Bool { singleMaxDuration > 0 }

    var importOptions: BmsONEImportOptions {
        BmsONEImportOptions(
            trustPlayerCommand: trustPlayerCommand,
            ignoreExtension: ignoreExtension,
            preferExModes: preferExModes,
            skipBetweenRandomAndIf: skipBetweenRandomAndIf,
            askTextEncoding: askTextEncoding,
            askRandomValues: askRandomValues,
            askGameMode: askGameMode,
            defaultTextEncoding: defaultTextEncoding,
            useRandomValues: useRandomValues
        )
    }

    static func load(from defaults: UserDefaults = .standard) -> BmsONEPreferences {
        var value = BmsONEPreferences()
        if let language = defaults.object(forKey: BmsONEPreferenceKey.language) as? String {
            value.languageKey = language
        }
        if let format = defaults.object(forKey: BmsONEPreferenceKey.saveFormat) as? String {
            value.saveFormat = BmsONEPreferenceFormat.normalizedSaveFormat(format)
        }
        if let format = defaults.object(forKey: BmsONEPreferenceKey.saveJsonFormat) as? String {
            value.saveJsonFormat = BmsONEPreferenceFormat.normalizedJsonFormat(format)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.uiFontIsDefault) != nil {
            value.uiFontDefault = defaults.bool(forKey: BmsONEPreferenceKey.uiFontIsDefault)
        }
        if let font = defaults.object(forKey: BmsONEPreferenceKey.uiFont) as? String {
            let decoded = BmsONEPreferenceFormat.decodeFont(font)
            value.uiFontFamily = decoded.family
            value.uiFontPointSize = decoded.pointSize
        }
        if defaults.object(forKey: BmsONEPreferenceKey.enableMasterChannel) != nil {
            value.enableMasterChannel = defaults.bool(forKey: BmsONEPreferenceKey.enableMasterChannel)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.showMasterLane) != nil {
            value.showMasterLane = defaults.bool(forKey: BmsONEPreferenceKey.showMasterLane)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.showMiniMap) != nil {
            value.showMiniMap = defaults.bool(forKey: BmsONEPreferenceKey.showMiniMap)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.fixMiniMap) != nil {
            value.fixMiniMap = defaults.bool(forKey: BmsONEPreferenceKey.fixMiniMap)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.miniMapOpacity) != nil {
            value.miniMapOpacity = defaults.double(forKey: BmsONEPreferenceKey.miniMapOpacity)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.snappedHitTestInEditMode) != nil {
            value.snappedHitTestInEditMode = defaults.bool(forKey: BmsONEPreferenceKey.snappedHitTestInEditMode)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.alwaysShowCursorLineInEditMode) != nil {
            value.alwaysShowCursorLineInEditMode =
                defaults.bool(forKey: BmsONEPreferenceKey.alwaysShowCursorLineInEditMode)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.snappedSelectionInEditMode) != nil {
            value.snappedSelectionInEditMode = defaults.bool(forKey: BmsONEPreferenceKey.snappedSelectionInEditMode)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.previewDelayRatio) != nil {
            value.previewDelayRatio = defaults.double(forKey: BmsONEPreferenceKey.previewDelayRatio)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.previewSmoothing) != nil {
            value.previewSmoothing = defaults.bool(forKey: BmsONEPreferenceKey.previewSmoothing)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.singleMaxDuration) != nil {
            value.singleMaxDuration = defaults.double(forKey: BmsONEPreferenceKey.singleMaxDuration)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.singleSoftFadeOut) != nil {
            value.singleSoftFadeOut = defaults.bool(forKey: BmsONEPreferenceKey.singleSoftFadeOut)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.askTextEncoding) != nil {
            value.askTextEncoding = defaults.bool(forKey: BmsONEPreferenceKey.askTextEncoding)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.askRandomValues) != nil {
            value.askRandomValues = defaults.bool(forKey: BmsONEPreferenceKey.askRandomValues)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.askGameMode) != nil {
            value.askGameMode = defaults.bool(forKey: BmsONEPreferenceKey.askGameMode)
        }
        if let encoding = defaults.object(forKey: BmsONEPreferenceKey.defaultTextEncoding) as? String {
            value.defaultTextEncodingKey = BmsONEPreferenceFormat.normalizedEncodingKey(encoding)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.useRandomValues) != nil {
            value.useRandomValues = defaults.bool(forKey: BmsONEPreferenceKey.useRandomValues)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.trustPlayerCommand) != nil {
            value.trustPlayerCommand = defaults.bool(forKey: BmsONEPreferenceKey.trustPlayerCommand)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.ignoreExtension) != nil {
            value.ignoreExtension = defaults.bool(forKey: BmsONEPreferenceKey.ignoreExtension)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.preferExModes) != nil {
            value.preferExModes = defaults.bool(forKey: BmsONEPreferenceKey.preferExModes)
        }
        if defaults.object(forKey: BmsONEPreferenceKey.minimumResolution) != nil {
            value.minimumResolution = BmsONEPreferenceFormat.clampResolution(
                defaults.integer(forKey: BmsONEPreferenceKey.minimumResolution)
            )
        }
        if defaults.object(forKey: BmsONEPreferenceKey.maximumResolution) != nil {
            value.maximumResolution = BmsONEPreferenceFormat.clampMaximum(
                minimum: value.minimumResolution,
                maximum: defaults.integer(forKey: BmsONEPreferenceKey.maximumResolution)
            )
        } else {
            value.maximumResolution = BmsONEPreferenceFormat.clampMaximum(
                minimum: value.minimumResolution,
                maximum: value.maximumResolution
            )
        }
        if defaults.object(forKey: BmsONEPreferenceKey.skipBetweenRandomAndIf) != nil {
            value.skipBetweenRandomAndIf = defaults.bool(forKey: BmsONEPreferenceKey.skipBetweenRandomAndIf)
        }
        return value
    }

    func store(to defaults: UserDefaults = .standard) {
        defaults.set(languageKey, forKey: BmsONEPreferenceKey.language)
        defaults.set(saveFormat, forKey: BmsONEPreferenceKey.saveFormat)
        defaults.set(saveJsonFormat, forKey: BmsONEPreferenceKey.saveJsonFormat)
        defaults.set(BmsONEPreferenceFormat.encodeFont(family: uiFontFamily, pointSize: uiFontPointSize),
                     forKey: BmsONEPreferenceKey.uiFont)
        defaults.set(uiFontDefault, forKey: BmsONEPreferenceKey.uiFontIsDefault)
        defaults.set(enableMasterChannel, forKey: BmsONEPreferenceKey.enableMasterChannel)
        defaults.set(showMasterLane, forKey: BmsONEPreferenceKey.showMasterLane)
        defaults.set(showMiniMap, forKey: BmsONEPreferenceKey.showMiniMap)
        defaults.set(fixMiniMap, forKey: BmsONEPreferenceKey.fixMiniMap)
        defaults.set(miniMapOpacity, forKey: BmsONEPreferenceKey.miniMapOpacity)
        defaults.set(snappedHitTestInEditMode, forKey: BmsONEPreferenceKey.snappedHitTestInEditMode)
        defaults.set(alwaysShowCursorLineInEditMode, forKey: BmsONEPreferenceKey.alwaysShowCursorLineInEditMode)
        defaults.set(snappedSelectionInEditMode, forKey: BmsONEPreferenceKey.snappedSelectionInEditMode)
        defaults.set(previewDelayRatio, forKey: BmsONEPreferenceKey.previewDelayRatio)
        defaults.set(previewSmoothing, forKey: BmsONEPreferenceKey.previewSmoothing)
        defaults.set(singleMaxDuration, forKey: BmsONEPreferenceKey.singleMaxDuration)
        defaults.set(singleSoftFadeOut, forKey: BmsONEPreferenceKey.singleSoftFadeOut)
        defaults.set(askTextEncoding, forKey: BmsONEPreferenceKey.askTextEncoding)
        defaults.set(askRandomValues, forKey: BmsONEPreferenceKey.askRandomValues)
        defaults.set(askGameMode, forKey: BmsONEPreferenceKey.askGameMode)
        defaults.set(defaultTextEncodingKey, forKey: BmsONEPreferenceKey.defaultTextEncoding)
        defaults.set(useRandomValues, forKey: BmsONEPreferenceKey.useRandomValues)
        defaults.set(trustPlayerCommand, forKey: BmsONEPreferenceKey.trustPlayerCommand)
        defaults.set(ignoreExtension, forKey: BmsONEPreferenceKey.ignoreExtension)
        defaults.set(preferExModes, forKey: BmsONEPreferenceKey.preferExModes)
        defaults.set(minimumResolution, forKey: BmsONEPreferenceKey.minimumResolution)
        defaults.set(maximumResolution, forKey: BmsONEPreferenceKey.maximumResolution)
        defaults.set(skipBetweenRandomAndIf, forKey: BmsONEPreferenceKey.skipBetweenRandomAndIf)
    }
}

enum BmsONEPreferenceFormat {
    static let languageTitles = ["(System)", "English", "Japanese"]
    static let saveFormatKeys = ["Default", "Latest", "1.0", "0.21"]
    /// Native and Latest are both `BMSON_V_1_0`.
    static let saveFormatTitles = ["Default(1.0)", "Latest(1.0)", "1.0", "0.21"]
    static let saveJsonFormats = ["Default", "Compact"]
    static let delayRatioSliderLevels = 16
    static let miniMapOpacitySliderMinimum = 4096
    static let miniMapOpacitySliderMaximum = 65536
    static let resolutionLimit = 1_000_000
    static let defaultMinimumResolution = 240
    static let defaultMaximumResolution = 10000
    static let infiniteDurationTitle = "+inf"

    /// `PrefPreviewPage` duration slider, last item is 0 = +inf.
    static let notePreviewDurations: [Double] = {
        var values = [0.05]
        for index in 0..<9 {
            values.append(0.1 + 0.1 * Double(index))
        }
        for index in 0..<5 {
            values.append(1.0 + 0.2 * Double(index))
        }
        for index in 0..<5 {
            values.append(2.0 + 1.0 * Double(index))
        }
        values.append(0.0)
        return values
    }()

    static func languageKey(index: Int) -> String {
        switch index {
        case 1:
            return "en"
        case 2:
            return "ja"
        default:
            return ""
        }
    }

    static func languageIndex(_ key: String) -> Int {
        if key == "en" {
            return 1
        }
        if key == "ja" {
            return 2
        }
        return 0
    }

    static func normalizedSaveFormat(_ text: String) -> String {
        saveFormatKeys.contains(text) ? text : "Default"
    }

    static func normalizedJsonFormat(_ text: String) -> String {
        text == "Compact" ? "Compact" : "Default"
    }

    static func encoding(from key: String) -> BmsONETextEncoding {
        BmsONETextEncoding(rawValue: key) ?? .localeDefault
    }

    static func normalizedEncodingKey(_ key: String) -> String {
        encoding(from: key).rawValue
    }

    static func delayRatio(slider: Int) -> Double {
        2.0 * Double(slider) / Double(delayRatioSliderLevels)
    }

    /// Qt `setValue(int)` truncates toward zero.
    static func delaySlider(ratio: Double) -> Int {
        Int(ratio / 2.0 * Double(delayRatioSliderLevels))
    }

    static func miniMapOpacity(slider: Int) -> Double {
        Double(slider) / 65536.0
    }

    static func miniMapOpacitySlider(opacity: Double) -> Int {
        Int(opacity * 65536.0)
    }

    static func durationIndex(_ duration: Double) -> Int {
        if duration > 999_999_999.999_999_999 || duration <= 0 {
            return notePreviewDurations.count - 1
        }
        var best = 0
        var error = Double.greatestFiniteMagnitude
        for index in 0..<(notePreviewDurations.count - 1) {
            let delta = abs(notePreviewDurations[index] - duration)
            if delta < error {
                best = index
                error = delta
            }
        }
        return best
    }

    static func durationValue(index: Int) -> Double {
        guard notePreviewDurations.indices.contains(index) else {
            return 0
        }
        return notePreviewDurations[index]
    }

    static func durationTitle(_ duration: Double) -> String {
        if duration <= 0 {
            return infiniteDurationTitle
        }
        return String(duration)
    }

    static func clampResolution(_ value: Int) -> Int {
        max(1, min(resolutionLimit, value))
    }

    static func clampMaximum(minimum: Int, maximum: Int) -> Int {
        max(clampResolution(minimum), min(resolutionLimit, maximum))
    }

    /// Qt `QString::toInt` yields 0 on junk.
    static func parseResolution(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? 0
    }

    static func acceptedResolutions(minimumText: String, maximumText: String) -> (Int, Int) {
        let minimum = clampResolution(parseResolution(minimumText))
        let maximum = clampMaximum(minimum: minimum, maximum: parseResolution(maximumText))
        return (minimum, maximum)
    }

    static func encodeFont(family: String, pointSize: Double) -> String {
        "\(family)\t\(pointSize)"
    }

    static func decodeFont(_ text: String) -> (family: String, pointSize: Double) {
        let parts = text.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, let size = Double(parts[1]) {
            return (String(parts[0]), size)
        }
        return (text, 0)
    }

    /// `PrefGeneralPage::UpdateUIFont`. Default uses integer pt; custom uses the stored size.
    static func fontButtonTitle(family: String, pointSize: Double, isDefault: Bool) -> String {
        var display = String(family.prefix(12))
        if display.count < family.count {
            display += "..."
        }
        if isDefault {
            return "Default (\(display), \(Int(pointSize))pt)"
        }
        return "\(display), \(pointSize)pt"
    }
}

/// 对照 `PreviewConfig` / `SoundChannelPreview` / `MasterPlayer` / `AudioPlayerInternal`。
enum BmsONEPreviewTiming {
    /// `AudioPlayerInternal::BufferSampleCount`。
    static let bufferSampleCount = 4096
    static let sampleRate = 44100.0
    /// `GetSingleSoftFadeOut` 为真。
    static let softFadeRate = 0.9998
    static let hardFadeRate = 0.9992

    /// `Delay(ratio * BufferSampleCount / (44100 / 1000.0))`，`int` 向零取整。
    /// 只推迟播放头报告，不推迟出声。
    static func delayMilliseconds(ratio: Double) -> Int {
        guard ratio.isFinite, ratio > 0 else { return 0 }
        return Int(ratio * Double(bufferSampleCount) / (sampleRate / 1000.0))
    }

    /// 画面上的秒数 = 已经播出的秒数减去缓冲延迟。
    static func playheadSeconds(audioSeconds: Double, ratio: Double) -> Double {
        guard audioSeconds.isFinite else { return 0 }
        let delayed = audioSeconds - Double(delayMilliseconds(ratio: ratio)) / 1000.0
        return delayed > 0 ? delayed : 0
    }

    /// `int durationInSamples = duration * 44100`。`0` 表示不限。
    static func durationInSamples(_ duration: Double) -> Int {
        guard duration.isFinite, duration > 0 else { return 0 }
        return Int(duration * sampleRate)
    }

    static func fadeRate(soft: Bool) -> Double {
        soft ? softFadeRate : hardFadeRate
    }

    /// `currentSampleCount + samplesRead > durationInSamples` 才开始淡出。
    static func shouldStartFade(currentSampleCount: Int, samplesRead: Int, duration: Double) -> Bool {
        let limit = durationInSamples(duration)
        return limit > 0 && currentSampleCount + samplesRead > limit
    }

    /// 淡出开始后，这一缓冲里第 `index` 个样本的增益。第一个样本仍是 `1`。
    static func fadeGain(index: Int, soft: Bool) -> Double {
        guard index > 0 else { return 1 }
        return pow(fadeRate(soft: soft), Double(index))
    }

    /// 增益落到 `floor` 所需秒数，给点音符预听停播用。
    static func fadeOutSeconds(soft: Bool, floor: Double = 0.001) -> Double {
        let rate = fadeRate(soft: soft)
        guard floor > 0, floor < 1, rate > 0, rate < 1 else { return 0 }
        return log(floor) / log(rate) / sampleRate
    }
}
