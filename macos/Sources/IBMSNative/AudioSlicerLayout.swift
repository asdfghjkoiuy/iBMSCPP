import CoreGraphics
import Foundation

/// 共用切片窗。波形区是主视觉，其他项目使用紧凑的分组表单。
/// 不是 woslicer 原版客户区。未截图。
enum AudioSlicerLayout {
    static let title = "Audio Slicer"
    static let clientSize = CGSize(width: 960, height: 600)
    static let minimumSize = CGSize(width: 820, height: 520)
    static let waveformMinimumHeight: CGFloat = 160
    static let contentInset: CGFloat = 16
    static let spacing: CGFloat = 12
    /// 初始 frame；实际尺寸由可缩放窗口在 `layout()` 中计算。
    static let waveformSize = CGSize(width: 928, height: 200)
    static let waveformX: CGFloat = 16
    static let waveformY: CGFloat = 82
    static let splitButtonY: CGFloat = 548

    static func waveformFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: contentInset,
            y: waveformY,
            width: max(size.width - contentInset * 2, 0),
            height: max(waveformMinimumHeight, size.height - 360)
        )
    }
    static let originalClientSize: CGSize? = nil
    static let originalClientSizeNote = "woslicer 客户区待运行时从 Windows 原版量"
    static let bmhelperModeTitle = "bmhelper"
    static let woslicerModeTitle = "woslicer"
    static let modeLabel = "Cut points:"
    static let marksTitle = "Cut marks (seconds):"
    static let addMarkTitle = "Add mark"
    static let clearMarksTitle = "Clear marks"
    static let sequenceStartTitle = "Sequence start:"
    static let ffDefinitionTitle = "FF definition"
    static let exportBMSETitle = "Export BMSE"
    static let importBMSETitle = "Import BMSE"
    static let menuTitle = "Audio Slicer…"
}
