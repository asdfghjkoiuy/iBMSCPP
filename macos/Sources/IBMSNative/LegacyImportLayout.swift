import CoreGraphics
import Foundation

enum ImportSMLayout {
    static let clientSize = CGSize(width: 210, height: 203)
    static let title = "Import *.SM file"
    static let difficultyLabel = CGRect(x: 12, y: 9, width: 58, height: 15)
    static let difficultyTitle = "Difficulty:"
    static let list = CGRect(x: 15, y: 27, width: 183, height: 64)
    static let listItemHeight: CGFloat = 15
    static let note = CGRect(x: 12, y: 96, width: 186, height: 64)
    static let noteText = "Please note that bg musics and STOP values will not be imported."
    static let buttonRow = CGRect(x: 52, y: 162, width: 146, height: 29)
    static let ok = CGRect(x: 55, y: 165, width: 67, height: 23)
    static let cancel = CGRect(x: 128, y: 165, width: 67, height: 23)
}

enum MyO2Layout {
    static let clientSize = CGSize(width: 559, height: 552)
    static let title = "MyO2 工具箱"
    static let bpmLabel = CGRect(x: 35, y: 24, width: 68, height: 15)
    static let bpmTitle = "BPM恒速器"
    static let bpmField = CGRect(x: 109, y: 22, width: 168, height: 23)
    static let applyConst = CGRect(x: 283, y: 21, width: 249, height: 25)
    static let applyConstTitle = "恒速化"
    static let gridLabel = CGRect(x: 24, y: 56, width: 79, height: 15)
    static let gridTitle = "64线检查工具"
    static let applyCheck = CGRect(x: 109, y: 51, width: 196, height: 25)
    static let applyCheckTitle = "检查"
    static let applyAdjust = CGRect(x: 311, y: 51, width: 221, height: 25)
    static let applyAdjustTitle = "自动对齐"
    static let table = CGRect(x: 27, y: 82, width: 505, height: 448)
    static let rowHeaderWidth: CGFloat = 21
    static let bpmRange = 0.0001...65535.9999
    static let defaultBPM = 120.0
    static let bpmDigits = 4
    static let bpmIncrement = 10.0
    static let columns: [(id: String, title: String, width: CGFloat, editable: Bool)] = [
        ("Index", "序号", 45, false),
        ("Measure", "小节", 50, false),
        ("ColumnName", "列", 40, false),
        ("Grid", "格线", 37, false),
        ("LongNote", "面条", 37, false),
        ("Hidden", "隐藏", 37, false),
        ("AdjTo64", "对齐至64线", 73, true),
        ("D64", "64线总偏差", 74, false),
        ("D48", "48线总偏差", 74, false)
    ]
}
