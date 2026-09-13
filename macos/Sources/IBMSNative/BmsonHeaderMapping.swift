import Foundation

/// 主编辑器 Header / Info 栏 ↔ BMSON `info`。对照 BmsONE `InfoView`，不套 BMS 头标签。
struct BmsonInfoFields: Equatable {
    var title: String
    var subtitle: String
    var artist: String
    var subartists: [String]
    var genre: String
    var modeHint: String
    var chartName: String
    var level: Int
    var initBPM: Double
    var judgeRank: Double
    var total: Double
    var resolution: Int

    init(_ snapshot: IBMSBmsonInfoSnapshot) {
        title = snapshot.title
        subtitle = snapshot.subtitle
        artist = snapshot.artist
        subartists = snapshot.subartists.map { $0 }
        genre = snapshot.genre
        modeHint = snapshot.modeHint
        chartName = snapshot.chartName
        level = Int(snapshot.level)
        initBPM = snapshot.initBPM
        judgeRank = snapshot.judgeRank
        total = snapshot.total
        resolution = Int(snapshot.resolution)
    }
}

enum BmsonHeaderMapping {
    /// 官方 BMSON 1.0.0 里、核心当作 extra 保存的图和预览音乐。
    static let bannerJSONKey = "banner"
    static let backImageJSONKey = "backImage"
    static let eyecatchImageJSONKey = "eyecatchImage"
    static let titleImageJSONKey = "titleImage"
    static let previewMusicJSONKey = "previewMusic"

    static let infoExtraJSONKeys = [
        bannerJSONKey, backImageJSONKey, eyecatchImageJSONKey, titleImageJSONKey, previewMusicJSONKey
    ]

    /// Header 侧栏键 → extra JSON 键。STAGEFILE 对 eyecatch，BACKBMP 对 backImage。
    static let headerExtraJSONKeys = [
        "STAGEFILE": eyecatchImageJSONKey,
        "BANNER": bannerJSONKey,
        "BACKBMP": backImageJSONKey,
        "TITLEIMAGE": titleImageJSONKey,
        "PREVIEWMUSIC": previewMusicJSONKey
    ]

    static let editableKeys = [
        "TITLE", "SUBTITLE", "ARTIST", "SUBARTIST", "GENRE", "PLAYLEVEL", "TOTAL",
        "STAGEFILE", "BANNER", "BACKBMP", "CHARTNAME", "JUDGERANK", "MODEHINT",
        "TITLEIMAGE", "PREVIEWMUSIC"
    ]

    static func fields(from snapshot: IBMSBmsonInfoSnapshot, extras: [String: String] = [:]) -> [String: String] {
        [
            "TITLE": snapshot.title,
            "SUBTITLE": snapshot.subtitle,
            "ARTIST": snapshot.artist,
            "SUBARTIST": joinSubartists(snapshot.subartists.map { $0 }),
            "GENRE": snapshot.genre,
            "PLAYLEVEL": String(Int(snapshot.level)),
            "TOTAL": decimalString(snapshot.total),
            "CHARTNAME": snapshot.chartName,
            "JUDGERANK": decimalString(snapshot.judgeRank),
            "MODEHINT": snapshot.modeHint,
            "STAGEFILE": extras[eyecatchImageJSONKey] ?? "",
            "BANNER": extras[bannerJSONKey] ?? "",
            "BACKBMP": extras[backImageJSONKey] ?? "",
            "TITLEIMAGE": extras[titleImageJSONKey] ?? "",
            "PREVIEWMUSIC": extras[previewMusicJSONKey] ?? ""
        ]
    }

    static func infoExtraJSONKey(forHeader key: String) -> String? {
        headerExtraJSONKeys[key]
    }

    /// 只有表里的键才改。PLAYER / RANK / DIFFICULTY / EXRANK / COMMENT / LNOBJ 没有 BMSON `info`。
    static func apply(key: String, value: String, to fields: inout BmsonInfoFields) -> Bool {
        switch key {
        case "TITLE":
            fields.title = value
            return true
        case "SUBTITLE":
            fields.subtitle = value
            return true
        case "ARTIST":
            fields.artist = value
            return true
        case "SUBARTIST":
            fields.subartists = splitSubartists(value)
            return true
        case "GENRE":
            fields.genre = value
            return true
        case "PLAYLEVEL":
            guard let level = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }
            fields.level = level
            return true
        case "TOTAL":
            guard let total = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  total.isFinite else {
                return false
            }
            fields.total = total
            return true
        case "CHARTNAME":
            fields.chartName = value
            return true
        case "MODEHINT":
            fields.modeHint = value
            return true
        case "JUDGERANK":
            guard let rank = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  rank.isFinite else {
                return false
            }
            fields.judgeRank = rank
            return true
        default:
            return false
        }
    }

    /// 预览和列写入一样：必须是正数。
    static func parseBPM(_ decimal: String) -> Double? {
        guard let bpm = Double(decimal.trimmingCharacters(in: .whitespacesAndNewlines)),
              bpm > 0, bpm.isFinite else {
            return nil
        }
        return bpm
    }

    /// `bmson_from_bms` 把一个 `#SUBARTIST` 放进数组。侧栏只有一格，逗号分开。
    static func splitSubartists(_ text: String) -> [String] {
        text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func joinSubartists(_ names: [String]) -> String {
        names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    static func decimalString(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        return String(value)
    }
}
