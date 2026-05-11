import Foundation
@testable import ZenWallpaperKit

@MainActor
enum WallpaperCatalogTests {
    static func detailUrlIsBuiltFromCurrentBaseUrl() {
        let url = makeWorkDetailUrl(workId: "abc123", baseUrl: "https://www.qushenma.com/")
        expectEqual(url?.absoluteString, "https://www.qushenma.com/works/abc123")
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
}
