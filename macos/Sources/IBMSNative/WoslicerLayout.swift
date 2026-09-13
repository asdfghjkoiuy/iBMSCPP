import CoreGraphics
import Foundation

enum WoslicerEdition: String, CaseIterable, Sendable {
    case ii = "II"
    case iii = "III"
}

struct WoslicerObservedCommand: Equatable, Sendable {
    let edition: WoslicerEdition
    let id: String
    let keys: String
    let officialHelp: String

    var listingLine: String {
        "\(edition.rawValue)  \(keys)  \(officialHelp)"
    }
}

enum WoslicerLayout {
    static let windowTitle = "woslicer II / III"
    static let iiProductName = "woslicerII"
    static let iiiProductName = "woslicerIII"
    static let author = "wosderge"

    /// Official client size is unknown. The zip has no source and was not measured on Windows.
    static let originalClientSize: CGSize? = nil
    static let originalClientSizeNote = "待运行时从 Windows 原版量"
    /// 裁断线切 PCM16、BMSE 剪贴板、预览、波形和末端全 0 帧已接到共用切片窗。`.wos`、边缘检测还没有。
    static let slicingImplemented = true
    static let clipboardImplemented = true
    static let previewImplemented = true
    static let waveformImplemented = true
    static let trimImplemented = true
    static let wosFormatKnown = false
    static let wosFileNameRule = "読み込んだ音の.wavを.wosに代えたものになります。"
    static let shellStatus = "切片、BMSE 剪贴板、预览和波形走共用 Audio Slicer 窗，模式是 woslicer。woslicer 路径会去掉末端全 0 帧。共用窗已能画波形。客户区尺寸：待运行时从 Windows 原版量。没有 .wos，没有边缘检测。"

    static let iiOverview = "BMS用に特化したwavスライサーです。"
    static let iiDropAudio = "wavファイルをD&D（起動時でも起動後でも）"
    static let iiMove = "上下左右で移動"
    static let iiPlaceCutMark = "[Z]で裁断線設置"
    static let iiAdjustBPM = "BPMを[1][2][3][4]で合せる。"
    static let iiPreview = "[P]or[Enter]でプレビュー"
    static let iiSelectGrid = "[Q][W]でグリッドを選択可能です。"
    static let iiExportSlicedWAV = "出力名は元ファイル名_xxx.wavになります。"
    static let iiExportBMSEClipboard = "[V]で裁断線をBMSE形式クリップデータに出力できます。番号は連番になります。"
    static let iiSetClipboardSequenceStart = "[A][S]でクリップ連番の起点を設定"
    static let iiToggleFFDefinition = "[N]でFF定義か否かを選択できます。"
    static let iiImportBMSEClipboard = "[B]によるクリップ読み込み"
    static let iiReadWriteWos = "[T][Y]で簡易読み書きが出来ます。"
    static let iiClear = "新しいwavを読み込むときは[C]ですっきりさせる"
    static let iiShiftGlobalOffset = "[8][7]で全体をずらすことができます。"
    static let iiTrimTrailingSilence = "末端無音除去機能追加"
    static let iiLoadOGG = "ogg読み込めるようになりました"
    static let iiRights = "金銭が絡まない＋作者の明示　を条件に二次使用を許可します。内容改変は禁止です。"

    static let iiiOverview = "BMS用に特化したwavスライサーです。"
    static let iiiMove = "方向キー：移動"
    static let iiiPlaceOrDeleteMark = "Z：配置/削除"
    static let iiiPreviewCurrent = "P：現在の箇所のプレビュー再生"
    static let iiiPreviewPrevious = "O：現在の箇所の１つ前のプレビュー再生"
    static let iiiShowWaveform = "波形みれるように"
    static let iiiImportClip = "クリップ読み込み追加"
    static let iiiDetectEdges = "エッジ検出追加！！！！"
    static let iiiExportAll = "総出力ボタン"
    static let iiiRights = "金銭が絡まない＋作者の明示　を条件に二次使用を許可します。"

    static let commands: [WoslicerObservedCommand] = [
        WoslicerObservedCommand(edition: .ii, id: "iiDropAudio", keys: "D&D", officialHelp: iiDropAudio),
        WoslicerObservedCommand(edition: .ii, id: "iiMove", keys: "[←][↓][↑][→]", officialHelp: iiMove),
        WoslicerObservedCommand(edition: .ii, id: "iiPlaceCutMark", keys: "[Z]", officialHelp: iiPlaceCutMark),
        WoslicerObservedCommand(edition: .ii, id: "iiAdjustBPM", keys: "[1][2][3][4]", officialHelp: iiAdjustBPM),
        WoslicerObservedCommand(edition: .ii, id: "iiPreview", keys: "[P]/[Enter]", officialHelp: iiPreview),
        WoslicerObservedCommand(edition: .ii, id: "iiSelectGrid", keys: "[Q][W]", officialHelp: iiSelectGrid),
        WoslicerObservedCommand(edition: .ii, id: "iiExportSlicedWAV", keys: "[M]", officialHelp: iiExportSlicedWAV),
        WoslicerObservedCommand(edition: .ii, id: "iiExportBMSEClipboard", keys: "[V]", officialHelp: iiExportBMSEClipboard),
        WoslicerObservedCommand(edition: .ii, id: "iiSetClipboardSequenceStart", keys: "[A][S]", officialHelp: iiSetClipboardSequenceStart),
        WoslicerObservedCommand(edition: .ii, id: "iiToggleFFDefinition", keys: "[N]", officialHelp: iiToggleFFDefinition),
        WoslicerObservedCommand(edition: .ii, id: "iiImportBMSEClipboard", keys: "[B]", officialHelp: iiImportBMSEClipboard),
        WoslicerObservedCommand(edition: .ii, id: "iiReadWriteWos", keys: "[T][Y]", officialHelp: iiReadWriteWos),
        WoslicerObservedCommand(edition: .ii, id: "iiClear", keys: "[C]", officialHelp: iiClear),
        WoslicerObservedCommand(edition: .ii, id: "iiShiftGlobalOffset", keys: "[8][7]", officialHelp: iiShiftGlobalOffset),
        WoslicerObservedCommand(edition: .ii, id: "iiTrimTrailingSilence", keys: "—", officialHelp: iiTrimTrailingSilence),
        WoslicerObservedCommand(edition: .ii, id: "iiLoadOGG", keys: "—", officialHelp: iiLoadOGG),
        WoslicerObservedCommand(edition: .iii, id: "iiiMove", keys: "方向キー", officialHelp: iiiMove),
        WoslicerObservedCommand(edition: .iii, id: "iiiPlaceOrDeleteMark", keys: "[Z]", officialHelp: iiiPlaceOrDeleteMark),
        WoslicerObservedCommand(edition: .iii, id: "iiiPreviewCurrent", keys: "[P]", officialHelp: iiiPreviewCurrent),
        WoslicerObservedCommand(edition: .iii, id: "iiiPreviewPrevious", keys: "[O]", officialHelp: iiiPreviewPrevious),
        WoslicerObservedCommand(edition: .iii, id: "iiiShowWaveform", keys: "—", officialHelp: iiiShowWaveform),
        WoslicerObservedCommand(edition: .iii, id: "iiiImportClip", keys: "—", officialHelp: iiiImportClip),
        WoslicerObservedCommand(edition: .iii, id: "iiiDetectEdges", keys: "—", officialHelp: iiiDetectEdges),
        WoslicerObservedCommand(edition: .iii, id: "iiiExportAll", keys: "総出力ボタン", officialHelp: iiiExportAll)
    ]

    static var observedCapabilityCount: Int { commands.count }

    static var commandListing: String {
        commands.map(\.listingLine).joined(separator: "\n")
    }
}

enum WoslicerCommand: String, CaseIterable {
    case iiDropAudio
    case iiMove
    case iiPlaceCutMark
    case iiAdjustBPM
    case iiPreview
    case iiSelectGrid
    case iiExportSlicedWAV
    case iiExportBMSEClipboard
    case iiSetClipboardSequenceStart
    case iiToggleFFDefinition
    case iiImportBMSEClipboard
    case iiReadWriteWos
    case iiClear
    case iiShiftGlobalOffset
    case iiTrimTrailingSilence
    case iiLoadOGG
    case iiiMove
    case iiiPlaceOrDeleteMark
    case iiiPreviewCurrent
    case iiiPreviewPrevious
    case iiiShowWaveform
    case iiiImportClip
    case iiiDetectEdges
    case iiiExportAll
}
