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
        case "极简":
            return "minimalist desktop wallpaper, clean lines, soft gradients, simple geometry, abundant negative space"
        case "自然景观":
            return "serene nature landscape, mountains, forest, lake, morning mist, golden-hour cinematic light, calm negative space"
        case "抽象渐变":
            return "abstract flowing gradients, soft organic shapes, glassy light, calm color fields, icon-friendly negative space"
        case "水彩":
            return "watercolor painting, gentle washes, airy texture, delicate natural scene, soft calm composition"
        case "摄影":
            return "ultra realistic photography, natural light, shallow depth of field, polished desktop wallpaper composition"
        case "日系动画":
            return "anime-inspired scenic background, luminous sky, quiet town or countryside, painterly clouds, no characters, no IP references"
        case "科幻空间":
            return "sci-fi deep space wallpaper, nebula, distant planets, star field, cinematic cosmic scale, quiet dark atmosphere"
        case "赛博朋克":
            return "cyberpunk wallpaper, neon-lit futuristic city, rainy reflections, moody skyline, controlled contrast"
        case "梦幻奇幻":
            return "fantasy landscape, ethereal magical forest, ancient ruins, distant floating islands, soft epic light, peaceful dreamlike mood"
        case "像素艺术":
            return "high-resolution pixel art landscape, cozy scene, crisp pixels, limited palette, mature desktop wallpaper composition"
        case "胶片":
            return "analog film photography, warm grain, nostalgic color grading, soft contrast, quiet cinematic mood"
        case "油画":
            return "oil painting, textured brush strokes, painterly landscape, rich but calm color harmony"
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
