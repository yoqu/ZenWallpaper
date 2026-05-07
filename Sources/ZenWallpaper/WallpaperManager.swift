import Foundation
import AppKit

@MainActor
final class WallpaperManager: ObservableObject {
    @Published var wallpapers: [Wallpaper] = []
    @Published var currentId: String?

    private let fm = FileManager.default

    var cacheDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ZenWallpaper", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var indexFile: URL {
        cacheDir.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let arr = try? JSONDecoder().decode([Wallpaper].self, from: data) else {
            wallpapers = []
            return
        }
        let valid = arr.filter { fm.fileExists(atPath: $0.filePath) }
        wallpapers = valid
        currentId = valid.first?.id
    }

    func save() {
        guard let data = try? JSONEncoder().encode(wallpapers) else { return }
        try? data.write(to: indexFile)
    }

    func addNew(imageData: Data, mimeType: String, prompt: String, style: String, mood: String, cacheLimit: Int) -> Wallpaper? {
        let ext = (mimeType.contains("jpeg") || mimeType.contains("jpg")) ? "jpg" : "png"
        let id = UUID().uuidString
        let url = cacheDir.appendingPathComponent("\(id).\(ext)")
        do {
            try imageData.write(to: url)
        } catch {
            return nil
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let wp = Wallpaper(id: id, date: f.string(from: Date()),
                           prompt: prompt, style: style, mood: mood,
                           filePath: url.path)
        wallpapers.insert(wp, at: 0)
        if wallpapers.count > cacheLimit {
            let removed = wallpapers.suffix(wallpapers.count - cacheLimit)
            for r in removed {
                try? fm.removeItem(atPath: r.filePath)
            }
            wallpapers = Array(wallpapers.prefix(cacheLimit))
        }
        currentId = wp.id
        save()
        return wp
    }

    func current() -> Wallpaper? {
        if let id = currentId, let w = wallpapers.first(where: { $0.id == id }) { return w }
        return wallpapers.first
    }

    func setCurrent(_ w: Wallpaper) {
        currentId = w.id
        applyToAllScreens(url: w.fileURL)
    }

    func delete(_ w: Wallpaper) {
        try? fm.removeItem(atPath: w.filePath)
        wallpapers.removeAll { $0.id == w.id }
        if currentId == w.id { currentId = wallpapers.first?.id }
        save()
    }

    func revealInFinder(_ w: Wallpaper) {
        NSWorkspace.shared.activateFileViewerSelecting([w.fileURL])
    }

    func openCacheDirectory() {
        NSWorkspace.shared.open(cacheDir)
    }

    /// Pick the best generation size for the main screen at the highest resolution
    /// gpt-image-2 supports. Probed values (verified in production):
    ///   2048×1152 (16:9 landscape, max)
    ///   1536×1024 (3:2 landscape — Mac notebooks)
    ///   1024×1024 (square)
    ///   1024×1536 (2:3 portrait)
    static func bestSizeForMainScreen() -> String {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let ratio = frame.width / max(frame.height, 1)

        struct Candidate { let label: String; let ratio: Double }
        let candidates: [Candidate] = [
            Candidate(label: "2048x1152", ratio: 2048.0/1152.0), // 1.778
            Candidate(label: "1536x1024", ratio: 1536.0/1024.0), // 1.500
            Candidate(label: "1024x1024", ratio: 1.0),
            Candidate(label: "1024x1536", ratio: 1024.0/1536.0), // 0.667
        ]
        var best = candidates[0]
        var bestDelta = abs(log(best.ratio / Double(ratio)))
        for c in candidates.dropFirst() {
            let d = abs(log(c.ratio / Double(ratio)))
            if d < bestDelta { best = c; bestDelta = d }
        }
        return best.label
    }

    static func describeMainScreen() -> String {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let scale = screen?.backingScaleFactor ?? 1
        let pw = Int(frame.width * scale)
        let ph = Int(frame.height * scale)
        return "\(pw)×\(ph)"
    }

    func applyToAllScreens(url: URL) {
        let ws = NSWorkspace.shared
        for screen in NSScreen.screens {
            do {
                try ws.setDesktopImageURL(url, for: screen, options: [:])
            } catch {
                NSLog("setDesktopImageURL failed: \(error.localizedDescription)")
            }
        }
    }
}
