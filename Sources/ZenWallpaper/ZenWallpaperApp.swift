import SwiftUI
import AppKit

@main
struct ZenWallpaperApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var manager = WallpaperManager()
    @StateObject private var generator = GenerationCoordinator()

    var body: some Scene {
        #if DEBUG
        WindowGroup("ZenWallpaper Preview") {
            PopoverRoot()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(generator)
                .frame(width: 260, height: 600)
        }
        .windowResizability(.contentSize)
        #endif
        MenuBarExtra {
            PopoverRoot()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(generator)
                .frame(width: 260, height: 600)
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

    func generate(settings: AppSettings,
                  manager: WallpaperManager,
                  mood: String,
                  moodEnergy: Double,
                  moodValence: Double,
                  style: String,
                  accent: String,
                  userPrompt: String) async {
        guard !isLoading else { return }
        guard !settings.apiKey.isEmpty else {
            lastError = "请先在设置中填入 API Key"
            return
        }
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
            loadingProgress = 0
            loadingLabel = ""
        }

        await update("采集 心情·日期·黄历…", 0.15)
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
        await update("组装 prompt…", 0.30)

        let size = WallpaperManager.bestSizeForMainScreen()
        await update("调用 \(settings.model) · \(size)…", 0.55)
        let result: ImageGenerationResult
        do {
            result = try await api.generate(
                baseUrl: settings.baseUrl,
                apiKey: settings.apiKey,
                model: settings.model,
                prompt: prompt,
                size: size,
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
            return
        }

        await update("下载图像…", 0.80)
        guard let wp = manager.addNew(imageData: result.data,
                                       mimeType: result.mimeType,
                                       prompt: userPrompt.isEmpty ? "\(mood) · \(style) · 今日生成" : userPrompt,
                                       style: style,
                                       mood: mood,
                                       cacheLimit: settings.cacheLimit) else {
            lastError = "保存图像失败"
            return
        }

        await update("应用到显示器…", 0.95)
        manager.applyToAllScreens(url: wp.fileURL)

        await update("完成", 1.0)
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    @MainActor
    private func update(_ label: String, _ progress: Double) async {
        loadingLabel = label
        loadingProgress = progress
    }
}
