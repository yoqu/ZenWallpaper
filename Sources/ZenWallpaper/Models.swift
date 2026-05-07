import Foundation
import SwiftUI

struct Wallpaper: Identifiable, Codable, Hashable {
    let id: String
    let date: String
    let prompt: String
    let style: String
    let mood: String
    let filePath: String

    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

struct MoodOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let emoji: String
}

struct AccentOption: Identifiable, Hashable {
    let id = UUID()
    let key: String
    let name: String
    let color: Color
}

struct StylePreset: Identifiable, Hashable {
    let id: String
    let label: String
    let assetName: String
}

enum AutoFreq: String, CaseIterable, Codable {
    case off, daily, hour4, hour1
    var label: String {
        switch self {
        case .off: return "关闭"
        case .daily: return "每日清晨"
        case .hour4: return "每 4 小时"
        case .hour1: return "每小时"
        }
    }
}

enum HistoryLayout: String, CaseIterable, Codable {
    case rail, grid
    var label: String { self == .rail ? "横向" : "网格" }
}

let MOODS: [MoodOption] = [
    MoodOption(key: "平静", emoji: "🌿"),
    MoodOption(key: "开心", emoji: "☀️"),
    MoodOption(key: "专注", emoji: "🎯"),
    MoodOption(key: "焦虑", emoji: "🌧"),
    MoodOption(key: "兴奋", emoji: "✨"),
    MoodOption(key: "怀旧", emoji: "🕯"),
]

let STYLE_PRESETS: [StylePreset] = [
    StylePreset(id: "极简", label: "极简", assetName: "style-minimal"),
    StylePreset(id: "水彩", label: "水彩", assetName: "style-watercolor"),
    StylePreset(id: "摄影", label: "摄影", assetName: "style-photo"),
    StylePreset(id: "赛博朋克", label: "赛博朋克", assetName: "style-cyberpunk"),
    StylePreset(id: "胶片", label: "胶片", assetName: "style-film"),
    StylePreset(id: "油画", label: "油画", assetName: "style-oil"),
]

let DEFAULT_STYLE = STYLE_PRESETS.first?.id ?? "极简"

func stylePreset(for style: String) -> StylePreset {
    STYLE_PRESETS.first(where: { $0.id == style }) ?? STYLE_PRESETS[0]
}

let ACCENTS: [AccentOption] = [
    AccentOption(key: "auto",  name: "随心情", color: Color(red: 0.85, green: 0.48, blue: 0.29)),
    AccentOption(key: "ink",   name: "墨",     color: Color(red: 0.11, green: 0.11, blue: 0.12)),
    AccentOption(key: "sand",  name: "沙",     color: Color(red: 0.85, green: 0.72, blue: 0.54)),
    AccentOption(key: "sea",   name: "海",     color: Color(red: 0.23, green: 0.48, blue: 0.67)),
    AccentOption(key: "moss",  name: "苔",     color: Color(red: 0.35, green: 0.48, blue: 0.29)),
    AccentOption(key: "ember", name: "炭火",   color: Color(red: 0.78, green: 0.32, blue: 0.16)),
]

func describeMood(energy: Double, valence: Double) -> String {
    let e = energy > 0.66 ? "高" : energy > 0.33 ? "中" : "低"
    let v = valence > 0.66 ? "积极" : valence > 0.33 ? "中和" : "低落"
    if e == "高" && v == "积极" { return "兴奋" }
    if e == "高" && v == "低落" { return "焦躁" }
    if e == "中" && v == "积极" { return "愉悦" }
    if e == "中" && v == "中和" { return "专注" }
    if e == "低" && v == "积极" { return "平静" }
    if e == "低" && v == "中和" { return "松弛" }
    if e == "低" && v == "低落" { return "疲惫" }
    return "中性"
}
