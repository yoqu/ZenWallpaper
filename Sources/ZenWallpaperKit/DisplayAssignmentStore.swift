import Foundation

/// Persistent map: display UUID → wallpaper id. Lets per-display mode survive
/// relaunches and hot-plugs (`NSScreen.screens` indexes are not stable, but
/// the CG UUID is).
@MainActor
final class DisplayAssignmentStore {
    private(set) var assignments: [String: String] = [:]

    private let storeFile: URL
    private let fm = FileManager.default

    init(storeFile: URL) {
        self.storeFile = storeFile
        load()
    }

    func wallpaperId(for displayUUID: String) -> String? {
        assignments[displayUUID]
    }

    func assign(wallpaperId: String, to displayUUID: String) {
        assignments[displayUUID] = wallpaperId
        save()
    }

    func unassign(displayUUID: String) {
        assignments.removeValue(forKey: displayUUID)
        save()
    }

    /// Drop entries that point at wallpapers no longer in the cache. Called
    /// when a wallpaper is deleted so we don't keep dangling references.
    func purge(missingWallpaperIds: Set<String>) {
        var changed = false
        for (uuid, wid) in assignments where missingWallpaperIds.contains(wid) {
            assignments.removeValue(forKey: uuid)
            changed = true
        }
        if changed { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeFile),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            assignments = [:]
            return
        }
        assignments = dict
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        try? data.write(to: storeFile)
    }
}
