import Foundation
import AppKit

@MainActor
final class WallpaperManager: ObservableObject {
    @Published var wallpapers: [Wallpaper] = []
    @Published var currentId: String?
    /// Mirror of the assignment store so SwiftUI re-renders when assignments
    /// change. Don't mutate this directly — go through `setForDisplay` etc.
    @Published private(set) var displayAssignments: [String: String] = [:]

    private let fm = FileManager.default
    private let assignmentStore: DisplayAssignmentStore
    private var screenChangeObserver: NSObjectProtocol?

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
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = base.appendingPathComponent("ZenWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.assignmentStore = DisplayAssignmentStore(
            storeFile: root.appendingPathComponent("displays.json")
        )
        self.displayAssignments = assignmentStore.assignments
        load()
        subscribeScreenChanges()
    }

    deinit {
        if let obs = screenChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: History / cache

    func load() {
        guard let data = try? Data(contentsOf: indexFile),
              let arr = try? JSONDecoder().decode([Wallpaper].self, from: data) else {
            wallpapers = []
            return
        }
        let valid = arr.filter { fm.fileExists(atPath: $0.filePath) }
        wallpapers = valid
        currentId = valid.first?.id
        // Drop assignments whose target file got pruned out of the cache.
        let liveIds = Set(valid.map { $0.id })
        let missing = Set(assignmentStore.assignments.values).subtracting(liveIds)
        if !missing.isEmpty {
            assignmentStore.purge(missingWallpaperIds: missing)
            displayAssignments = assignmentStore.assignments
        }
    }

    func save() {
        guard let data = try? JSONEncoder().encode(wallpapers) else { return }
        try? data.write(to: indexFile)
    }

    func addNew(imageData: Data,
                mimeType: String,
                prompt: String,
                style: String,
                mood: String,
                cacheLimit: Int,
                remoteWorkId: String? = nil,
                reviewStatus: String? = nil) -> Wallpaper? {
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
                           filePath: url.path,
                           remoteWorkId: remoteWorkId,
                           reviewStatus: reviewStatus)
        wallpapers.insert(wp, at: 0)
        if wallpapers.count > cacheLimit {
            let removed = wallpapers.suffix(wallpapers.count - cacheLimit)
            for r in removed {
                try? fm.removeItem(atPath: r.filePath)
            }
            let evictedIds = Set(removed.map { $0.id })
            wallpapers = Array(wallpapers.prefix(cacheLimit))
            // Don't leave per-display entries pointing at files we just deleted.
            assignmentStore.purge(missingWallpaperIds: evictedIds)
            displayAssignments = assignmentStore.assignments
        }
        currentId = wp.id
        save()
        return wp
    }

    func current() -> Wallpaper? {
        if let id = currentId, let w = wallpapers.first(where: { $0.id == id }) { return w }
        return wallpapers.first
    }

    /// Mark `w` as the current selection and apply through the configured
    /// multi-display routing. In per-display mode this only affects the main
    /// display — use `setForDisplay` / `setForAllDisplays` to target others.
    func setCurrent(_ w: Wallpaper) {
        currentId = w.id
        switch currentMode {
        case .unified:
            applyUnified(url: w.fileURL)
        case .mainOnly:
            applyMainOnly(url: w.fileURL)
        case .perDisplay:
            // Left-click = quick action for the main display. Right-click menu
            // covers the "send to specific monitor" case.
            if let main = NSScreen.main,
               let identity = DisplayIdentity.from(main) {
                assignmentStore.assign(wallpaperId: w.id, to: identity.uuid)
                displayAssignments = assignmentStore.assignments
                apply(url: w.fileURL, to: main)
            }
        }
    }

    /// Pin `wallpaper` to one specific display, persisting the choice in the
    /// per-display store. Caller is responsible for switching mode to
    /// `.perDisplay` if they want the binding to win out on relaunch.
    func setForDisplay(_ wallpaper: Wallpaper, displayUUID: String) {
        assignmentStore.assign(wallpaperId: wallpaper.id, to: displayUUID)
        displayAssignments = assignmentStore.assignments
        if let identity = DisplayIdentity.allConnected().first(where: { $0.uuid == displayUUID }),
           let screen = identity.screen {
            apply(url: wallpaper.fileURL, to: screen)
        }
    }

    /// Apply `wallpaper` to every connected display and pin it for each one
    /// in the store. Used by the "all displays" submenu entry.
    func setForAllDisplays(_ wallpaper: Wallpaper) {
        currentId = wallpaper.id
        for identity in DisplayIdentity.allConnected() {
            assignmentStore.assign(wallpaperId: wallpaper.id, to: identity.uuid)
            if let screen = identity.screen {
                apply(url: wallpaper.fileURL, to: screen)
            }
        }
        displayAssignments = assignmentStore.assignments
    }

    func wallpaperForDisplay(_ uuid: String) -> Wallpaper? {
        guard let wid = assignmentStore.wallpaperId(for: uuid) else { return nil }
        return wallpapers.first(where: { $0.id == wid })
    }

    func delete(_ w: Wallpaper) {
        try? fm.removeItem(atPath: w.filePath)
        wallpapers.removeAll { $0.id == w.id }
        if currentId == w.id { currentId = wallpapers.first?.id }
        save()
        assignmentStore.purge(missingWallpaperIds: [w.id])
        displayAssignments = assignmentStore.assignments
    }

    func revealInFinder(_ w: Wallpaper) {
        NSWorkspace.shared.activateFileViewerSelecting([w.fileURL])
    }

    func openCacheDirectory() {
        NSWorkspace.shared.open(cacheDir)
    }

    var logsDir: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ZenWallpaper", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func openLogsDirectory() {
        NSWorkspace.shared.open(logsDir)
    }

    // MARK: Routing

    /// Re-apply whatever the current state implies — used after the mode
    /// setting changes and after a display hot-plug.
    func applyCurrent() {
        switch currentMode {
        case .unified:
            if let w = current() { applyUnified(url: w.fileURL) }
        case .mainOnly:
            if let w = current() { applyMainOnly(url: w.fileURL) }
        case .perDisplay:
            applyPerDisplay()
        }
    }

    private var currentMode: MultiDisplayMode {
        // Read straight from defaults so we stay in sync with @AppStorage in
        // AppSettings without needing a back-channel reference.
        let raw = UserDefaults.standard.string(forKey: "multiDisplay")
            ?? MultiDisplayMode.unified.rawValue
        return MultiDisplayMode(rawValue: raw) ?? .unified
    }

    private func applyUnified(url: URL) {
        for screen in NSScreen.screens {
            apply(url: url, to: screen)
        }
    }

    private func applyMainOnly(url: URL) {
        guard let screen = NSScreen.main else { return }
        apply(url: url, to: screen)
    }

    private func applyPerDisplay() {
        let fallbackURL = current()?.fileURL
        for identity in DisplayIdentity.allConnected() {
            guard let screen = identity.screen else { continue }
            if let pinned = wallpaperForDisplay(identity.uuid),
               fm.fileExists(atPath: pinned.filePath) {
                apply(url: pinned.fileURL, to: screen)
            } else if let fallbackURL {
                // New or unpinned display — show the latest generated piece
                // until the user explicitly assigns something for it.
                apply(url: fallbackURL, to: screen)
            }
        }
    }

    private func apply(url: URL, to screen: NSScreen) {
        do {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true
            ])
        } catch {
            NSLog("setDesktopImageURL failed: \(error.localizedDescription)")
        }
    }

    private func subscribeScreenChanges() {
        // Fires whenever a display is added, removed, or has its mode changed.
        // Re-apply so freshly plugged-in monitors pick up the right wallpaper.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyCurrent()
            }
        }
    }
}
