import SwiftUI
import AppKit
import os.log
// All app code lives in ZenWallpaperKit so the test runner can reach it through
// `@testable import` — see Package.swift for context.
@testable import ZenWallpaperKit

private let appLog = Logger(subsystem: "com.zen.wallpaper", category: "App")

/// Bridge AppKit's `application(_:open:)` into a SwiftUI-friendly notification.
/// Why not `.onOpenURL`? In a `MenuBarExtra`-only app the SwiftUI scene tree only
/// exists while the popover is showing, so `.onOpenURL` silently misses URLs
/// that arrive while it's closed. The AppDelegate, by contrast, is alive for the
/// entire process lifetime — it captures the URL no matter what the UI is doing
/// and re-broadcasts it through `NotificationCenter` so any subscriber (in our
/// case `ShenmaConnectionManager`) can react.
final class ZenWallpaperAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        appLog.notice("[Shenma] AppDelegate: received \(urls.count) URL(s): \(urls)")
        for url in urls {
            NotificationCenter.default.post(
                name: ShenmaConnectionManager.urlReceivedNotificationName,
                object: nil,
                userInfo: ["url": url]
            )
        }
    }
}

@main
struct ZenWallpaperApp: App {
    @NSApplicationDelegateAdaptor(ZenWallpaperAppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var manager: WallpaperManager
    @StateObject private var generator: GenerationCoordinator
    @StateObject private var autoScheduler: AutoWallpaperScheduler
    @StateObject private var l10n: LocalizationManager
    @StateObject private var shenma: ShenmaConnectionManager

    @MainActor
    init() {
        let settings = AppSettings()
        // Bump anyone still on old uyoqu.com defaults to the canonical
        // `https://www.uyoqu.com`. No-op for users who set their own URL.
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        // Drop dead "NSWindow Frame ...ZenWallpaper.PopoverRoot..." entries
        // left over from when PopoverRoot lived in the executable target.
        settings.purgeStaleWindowFrameDefaultsIfNeeded()
        let l10n = LocalizationManager.shared
        l10n.language = settings.appLanguage

        let manager = WallpaperManager()
        let generator = GenerationCoordinator()
        let shenma = ShenmaConnectionManager()
        let autoScheduler = AutoWallpaperScheduler(
            settings: settings,
            manager: manager,
            generator: generator,
            shenma: shenma
        )

        _settings = StateObject(wrappedValue: settings)
        _manager = StateObject(wrappedValue: manager)
        _generator = StateObject(wrappedValue: generator)
        _autoScheduler = StateObject(wrappedValue: autoScheduler)
        _l10n = StateObject(wrappedValue: l10n)
        _shenma = StateObject(wrappedValue: shenma)
    }

    var body: some Scene {
        // NOTE: The DEBUG-only `WindowGroup("ZenWallpaper Preview") { ... }`
        // that used to live here was removed — under macOS 26 / SwiftUI 7.4
        // having both a WindowGroup and a MenuBarExtra(.window) scene against
        // the same `PopoverRoot` type trips PlatformSceneCache's internal
        // dictionary with a KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS
        // crash the first time the menu bar icon is clicked.
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(generator)
                .environmentObject(autoScheduler)
                .environmentObject(l10n)
                .environmentObject(shenma)
                .frame(width: 260, height: 600)
                .onChange(of: settings.appLanguageRaw) { _, newValue in
                    l10n.language = AppLanguage(rawValue: newValue) ?? .system
                }
                .task {
                    // Validate the cached qushenma token against the server once the popover
                    // appears. refresh() only clears local state on a real 401 — transient
                    // errors leave the cached account in place.
                    await shenma.refresh(baseUrl: settings.shenmaBaseUrl)
                }
        } label: {
            MenuBarIconView(isLoading: generator.isLoading)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIconView: View {
    let isLoading: Bool

    var body: some View {
        let image = MenuBarIconProvider.menuBarImage()
        Image(nsImage: image)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .opacity(isLoading ? 0.92 : 1.0)
    }
}

enum MenuBarIconProvider {
    static let menuBarPointSize: CGFloat = 18

    static func menuBarImage() -> NSImage {
        if let image = load(named: "menubar-icon") {
            return image
        }

        let fallback = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: nil) ?? NSImage()
        fallback.isTemplate = true
        fallback.size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        return fallback
    }

    private static func load(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Branding"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: menuBarPointSize, height: menuBarPointSize)
        return image
    }
}
