import AppKit
import Foundation

enum WallpaperScreenPolicy {
    /// Pick the closest backend-supported image size for `screen`'s aspect ratio.
    static func bestSize(for screen: NSScreen) -> String {
        let ratio = aspectRatio(for: screen)

        struct Candidate { let label: String; let ratio: Double }
        let candidates: [Candidate] = [
            Candidate(label: "2048x1152", ratio: 2048.0 / 1152.0),
            Candidate(label: "1536x1024", ratio: 1536.0 / 1024.0),
            Candidate(label: "1024x1024", ratio: 1.0),
            Candidate(label: "1024x1536", ratio: 1024.0 / 1536.0),
        ]
        var best = candidates[0]
        var bestDelta = abs(log(best.ratio / ratio))
        for c in candidates.dropFirst() {
            let d = abs(log(c.ratio / ratio))
            if d < bestDelta { best = c; bestDelta = d }
        }
        return best.label
    }

    static func bestSizeForMainScreen() -> String {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return "1536x1024"
        }
        return bestSize(for: screen)
    }

    /// Aspect-ratio slug ("16:9", "3:2", ...) used by the cloud-library filter.
    static func aspectRatioSlug(for screen: NSScreen) -> String {
        let ratio = aspectRatio(for: screen)
        struct Candidate { let slug: String; let value: Double }
        let candidates: [Candidate] = [
            Candidate(slug: "16:9", value: 16.0 / 9.0),
            Candidate(slug: "3:2",  value: 3.0 / 2.0),
            Candidate(slug: "4:3",  value: 4.0 / 3.0),
            Candidate(slug: "5:4",  value: 5.0 / 4.0),
            Candidate(slug: "1:1",  value: 1.0),
            Candidate(slug: "4:5",  value: 4.0 / 5.0),
            Candidate(slug: "3:4",  value: 3.0 / 4.0),
            Candidate(slug: "2:3",  value: 2.0 / 3.0),
            Candidate(slug: "9:16", value: 9.0 / 16.0)
        ]
        var best = candidates[0]
        var bestDelta = abs(log(best.value / ratio))
        for c in candidates.dropFirst() {
            let d = abs(log(c.value / ratio))
            if d < bestDelta { best = c; bestDelta = d }
        }
        return best.slug
    }

    static func currentAspectRatioSlug() -> String {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return "16:9"
        }
        return aspectRatioSlug(for: screen)
    }

    /// Pixel-accurate description of `screen` ("3024×1964").
    static func describe(_ screen: NSScreen) -> String {
        let scale = screen.backingScaleFactor
        let pw = Int(screen.frame.width * scale)
        let ph = Int(screen.frame.height * scale)
        return "\(pw)×\(ph)"
    }

    static func describeMainScreen() -> String {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return "1920×1080" }
        return describe(screen)
    }

    private static func aspectRatio(for screen: NSScreen) -> Double {
        Double(screen.frame.width / max(screen.frame.height, 1))
    }
}
