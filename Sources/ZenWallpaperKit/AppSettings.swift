import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("useDate") var useDate: Bool = true
    @AppStorage("useLunar") var useLunar: Bool = true
    @AppStorage("autoFreqRaw") var autoFreqRaw: String = AutoFreq.daily.rawValue
    @AppStorage("multiDisplay") var multiDisplay: String = MultiDisplayMode.unified.rawValue
    @AppStorage("cacheLimit") var cacheLimit: Int = 12
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false
    @AppStorage("historyLayoutRaw") var historyLayoutRaw: String = HistoryLayout.rail.rawValue
    @AppStorage("moodEnergy") var moodEnergy: Double = 0.4
    @AppStorage("moodValence") var moodValence: Double = 0.65
    @AppStorage("selectedStyle") var selectedStyle: String = DEFAULT_STYLE
    @AppStorage("selectedAccent") var selectedAccent: String = "auto"
    @AppStorage("userPrompt") var userPrompt: String = ""
    @AppStorage("debugLogging") var debugLogging: Bool = false
    @AppStorage("appLanguage") var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("shenmaBaseUrl") var shenmaBaseUrl: String = ShenmaEndpoint.production.url

    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .system }
        set { appLanguageRaw = newValue.rawValue }
    }

    var autoFreq: AutoFreq {
        get { AutoFreq(rawValue: autoFreqRaw) ?? .daily }
        set { autoFreqRaw = newValue.rawValue }
    }

    var multiDisplayMode: MultiDisplayMode {
        get { MultiDisplayMode(rawValue: multiDisplay) ?? .unified }
        set { multiDisplay = newValue.rawValue }
    }
    var historyLayout: HistoryLayout {
        get { HistoryLayout(rawValue: historyLayoutRaw) ?? .rail }
        set { historyLayoutRaw = newValue.rawValue }
    }

    /// One-time migration from older defaults. Earlier builds shipped with
    /// `https://qushenma.com` (no `www.`); the canonical production URL is now
    /// `https://www.qushenma.com`. If the user is still on the old default, bump
    /// them automatically — anyone who deliberately changed it keeps their value.
    func migrateLegacyShenmaBaseUrlIfNeeded() {
        let stale = ["https://qushenma.com", "https://qushenma.com/"]
        if stale.contains(shenmaBaseUrl) {
            shenmaBaseUrl = ShenmaEndpoint.production.url
        }
    }

    /// SwiftUI persists window frames keyed by the fully-qualified view type
    /// chain. Two situations leave behind stale keys that SwiftUI's
    /// `PlatformSceneCache` will still try to deserialize on launch —
    /// tripping `KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS` inside
    /// `addHost` the first time the menu bar icon is clicked:
    ///   1. `PopoverRoot` migrated `ZenWallpaper → ZenWallpaperKit` module.
    ///   2. We replaced the legacy `WindowGroup` preview scene with an
    ///      explicitly-id'd `Window(_:id:)`, leaving the old auto-generated
    ///      "...AppWindow-1" key dangling.
    /// Strip any frame key that references a `PopoverRoot` we no longer use.
    func purgeStaleWindowFrameDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let dict = defaults.dictionaryRepresentation()
        let stale = dict.keys.filter { key in
            guard key.hasPrefix("NSWindow Frame") else { return false }
            // Anything that references the old executable-module PopoverRoot
            // or the now-removed WindowGroup-style AppWindow suffix is dead.
            return key.contains("ZenWallpaper.PopoverRoot")
                || key.hasSuffix("-AppWindow-1")
        }
        for key in stale {
            defaults.removeObject(forKey: key)
        }
    }
}

/// Canonical qushenma deployments. The settings UI exposes these as one-tap presets;
/// users can still type any URL by hand if they're on a staging environment.
enum ShenmaEndpoint: String, CaseIterable, Identifiable {
    case production
    case localhost
    case custom

    var id: String { rawValue }

    /// The URL string that backs this preset. `.custom` returns empty — the caller
    /// should preserve whatever the user typed.
    var url: String {
        switch self {
        case .production: return "https://www.qushenma.com"
        case .localhost:  return "http://127.0.0.1:5173"
        case .custom:     return ""
        }
    }

    /// Reverse-lookup: which preset (if any) does an arbitrary URL match? Used by
    /// the settings UI to highlight the right segment when the field is edited
    /// manually.
    static func match(_ url: String) -> ShenmaEndpoint {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if trimmed == ShenmaEndpoint.production.url
            || trimmed == "https://qushenma.com" {
            return .production
        }
        // Treat 127.0.0.1 and localhost as the same preset on common dev ports.
        let localPresets: Set<String> = ["http://localhost:5173", "http://127.0.0.1:5173"]
        if localPresets.contains(trimmed) {
            return .localhost
        }
        return .custom
    }
}
