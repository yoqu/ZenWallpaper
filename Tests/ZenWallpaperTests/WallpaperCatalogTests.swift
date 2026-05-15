import Foundation
@testable import ZenWallpaperKit

@MainActor
enum WallpaperCatalogTests {
    static func detailUrlIsBuiltFromCurrentBaseUrl() {
        let url = makeWorkDetailUrl(workId: "abc123", baseUrl: "https://www.uyoqu.com/")
        expectEqual(url?.absoluteString, "https://www.uyoqu.com/works/abc123")
    }

    static func moodKeyMapsEnergyAndValence() {
        expectEqual(moodKey(energy: 0.9, valence: 0.9), "兴奋")
        expectEqual(moodKey(energy: 0.2, valence: 0.1), "疲惫")
    }

    static func promptComposerIncludesSelectedFields() {
        let prompt = PromptComposer.compose(
            mood: "专注",
            moodEnergy: 0.42,
            moodValence: 0.63,
            style: "摄影",
            accent: "sea",
            userPrompt: "quiet lake",
            useDate: true,
            useLunar: false
        )
        expectTrue(prompt.contains("Style: ultra realistic photography"), "prompt should include translated style")
        expectTrue(prompt.contains("Dominant color tone: ocean blue"), "prompt should include translated accent")
        expectTrue(prompt.contains("Additional cues: quiet lake."), "prompt should include user prompt")
    }

    static func styleCatalogIncludesExpandedWallpaperStyles() {
        let expected = [
            ("极简", "style-minimal"),
            ("自然景观", "style-nature"),
            ("抽象渐变", "style-abstract-gradient"),
            ("水彩", "style-watercolor"),
            ("摄影", "style-photo"),
            ("日系动画", "style-anime-scenery"),
            ("科幻空间", "style-sci-fi-space"),
            ("赛博朋克", "style-cyberpunk"),
            ("梦幻奇幻", "style-fantasy"),
            ("像素艺术", "style-pixel-art"),
            ("胶片", "style-film"),
            ("油画", "style-oil"),
        ]

        expectEqual(STYLE_PRESETS.count, expected.count)
        for (index, item) in expected.enumerated() {
            expectEqual(STYLE_PRESETS[index].id, item.0)
            expectEqual(STYLE_PRESETS[index].assetName, item.1)
        }
    }

    static func promptComposerTranslatesExpandedStyles() {
        let cases = [
            ("自然景观", "serene nature landscape"),
            ("抽象渐变", "abstract flowing gradients"),
            ("日系动画", "anime-inspired scenic background"),
            ("科幻空间", "sci-fi deep space wallpaper"),
            ("梦幻奇幻", "fantasy landscape"),
            ("像素艺术", "high-resolution pixel art landscape"),
        ]

        for item in cases {
            let prompt = PromptComposer.compose(
                mood: "平静",
                moodEnergy: 0.2,
                moodValence: 0.8,
                style: item.0,
                accent: "auto",
                userPrompt: "",
                useDate: false,
                useLunar: false
            )
            expectTrue(prompt.contains(item.1), "prompt should translate style \(item.0)")
        }
    }
}
