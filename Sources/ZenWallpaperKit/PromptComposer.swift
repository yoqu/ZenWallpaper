import Foundation

struct PromptComposer {
    static func compose(mood: String,
                        moodEnergy: Double,
                        moodValence: Double,
                        style: String,
                        accent: String,
                        userPrompt: String,
                        useDate: Bool,
                        useLunar: Bool) -> String {
        var lines: [String] = []
        lines.append("A serene desktop wallpaper, photographic-quality digital art.")
        lines.append("Style: \(translateStyle(style)).")
        lines.append("Mood: \(mood) (energy=\(Int(moodEnergy*100)), valence=\(Int(moodValence*100))).")
        if accent != "auto" {
            lines.append("Dominant color tone: \(translateAccent(accent)).")
        }
        if useDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            lines.append("Date inspiration: \(f.string(from: Date())).")
        }
        if useLunar {
            lines.append("Cultural undertone: subtle Eastern lunar-calendar aesthetic, evoking 节气 / 物候 of the season.")
        }
        if !userPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Additional cues: \(userPrompt).")
        }
        lines.append("Composition: cinematic, balanced negative space suitable as a desktop wallpaper, no text, no watermark, no people-faces.")
        return lines.joined(separator: " ")
    }

    private static func translateStyle(_ s: String) -> String {
        switch s {
        case "极简": return "minimalist, clean lines, soft gradients"
        case "水彩": return "watercolor painting, gentle washes"
        case "摄影": return "ultra realistic photography, shallow depth of field"
        case "赛博朋克": return "cyberpunk, neon-lit cityscape, vibrant"
        case "胶片": return "analog film photography, grain, warm tones"
        case "油画": return "oil painting, textured brush strokes"
        default: return s
        }
    }

    private static func translateAccent(_ a: String) -> String {
        switch a {
        case "ink":   return "deep ink black"
        case "sand":  return "warm sand beige"
        case "sea":   return "ocean blue"
        case "moss":  return "moss green"
        case "ember": return "ember orange-red"
        default: return "balanced palette"
        }
    }
}
