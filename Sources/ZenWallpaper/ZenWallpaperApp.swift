import SwiftUI
import AppKit

@main
struct ZenWallpaperApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var manager: WallpaperManager
    @StateObject private var generator: GenerationCoordinator
    @StateObject private var autoScheduler: AutoWallpaperScheduler
    @StateObject private var l10n: LocalizationManager

    @MainActor
    init() {
        let settings = AppSettings()
        let l10n = LocalizationManager.shared
        l10n.language = settings.appLanguage

        let manager = WallpaperManager()
        let generator = GenerationCoordinator()
        let autoScheduler = AutoWallpaperScheduler(
            settings: settings,
            manager: manager,
            generator: generator
        )

        _settings = StateObject(wrappedValue: settings)
        _manager = StateObject(wrappedValue: manager)
        _generator = StateObject(wrappedValue: generator)
        _autoScheduler = StateObject(wrappedValue: autoScheduler)
        _l10n = StateObject(wrappedValue: l10n)
    }

    var body: some Scene {
        #if DEBUG
        WindowGroup("ZenWallpaper Preview") {
            PopoverRoot()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(generator)
                .environmentObject(autoScheduler)
                .environmentObject(l10n)
                .frame(width: 260, height: 600)
                .onChange(of: settings.appLanguageRaw) { _, newValue in
                    l10n.language = AppLanguage(rawValue: newValue) ?? .system
                }
        }
        .windowResizability(.contentSize)
        #endif
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(generator)
                .environmentObject(autoScheduler)
                .environmentObject(l10n)
                .frame(width: 260, height: 600)
                .onChange(of: settings.appLanguageRaw) { _, newValue in
                    l10n.language = AppLanguage(rawValue: newValue) ?? .system
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

@MainActor
final class GenerationCoordinator: ObservableObject {
    @Published var isLoading = false
    @Published var loadingLabel = ""
    @Published var loadingProgress: Double = 0
    @Published var lastError: String?

    private let api = APIClient()

    @discardableResult
    func generate(settings: AppSettings,
                  manager: WallpaperManager,
                  mood: String,
                  moodEnergy: Double,
                  moodValence: Double,
                  style: String,
                  accent: String,
                  userPrompt: String) async -> Bool {
        let l10n = LocalizationManager.shared
        guard !isLoading else { return false }
        guard !settings.apiKey.isEmpty else {
            lastError = l10n.t("error.needApiKey")
            return false
        }
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
            loadingProgress = 0
            loadingLabel = ""
        }

        await update(l10n.t("gen.collecting"), 0.15)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let prompt = PromptComposer.compose(
            mood: mood,
            moodEnergy: moodEnergy,
            moodValence: moodValence,
            style: style,
            accent: accent,
            userPrompt: userPrompt,
            useDate: settings.useDate,
            useLunar: settings.useLunar
        )
        await update(l10n.t("gen.composing"), 0.30)

        let size = WallpaperManager.bestSizeForMainScreen()
        await update(l10n.t("gen.calling", settings.model, size), 0.55)
        let result: ImageGenerationResult
        do {
            result = try await api.generate(
                baseUrl: settings.baseUrl,
                apiKey: settings.apiKey,
                model: settings.model,
                prompt: prompt,
                size: size,
                debugLogging: settings.debugLogging,
                progress: { [weak self] label, frac in
                    guard let self else { return }
                    Task { @MainActor in
                        self.loadingLabel = label
                        self.loadingProgress = frac
                    }
                }
            )
        } catch {
            lastError = error.localizedDescription
            return false
        }

        await update(l10n.t("gen.downloading"), 0.80)
        let defaultPrompt = "\(mood) · \(style)"
        guard let wp = manager.addNew(imageData: result.data,
                                       mimeType: result.mimeType,
                                       prompt: userPrompt.isEmpty ? defaultPrompt : userPrompt,
                                       style: style,
                                       mood: mood,
                                       cacheLimit: settings.cacheLimit) else {
            lastError = l10n.t("error.saveImageFailed")
            return false
        }

        await update(l10n.t("gen.applying"), 0.95)
        manager.applyToAllScreens(url: wp.fileURL)

        await update(l10n.t("gen.done"), 1.0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        return true
    }

    @MainActor
    private func update(_ label: String, _ progress: Double) async {
        loadingLabel = label
        loadingProgress = progress
    }
}
