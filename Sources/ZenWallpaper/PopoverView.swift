import SwiftUI
import AppKit

enum PopoverView {
    case main, settings
}

struct PopoverRoot: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var generator: GenerationCoordinator

    @State private var view: PopoverView = .main

    var body: some View {
        Group {
            if view == .main {
                MainPopoverView(
                    moodEnergy: Binding(
                        get: { settings.moodEnergy },
                        set: { settings.moodEnergy = $0 }
                    ),
                    moodValence: Binding(
                        get: { settings.moodValence },
                        set: { settings.moodValence = $0 }
                    ),
                    style: Binding(
                        get: { settings.selectedStyle },
                        set: { settings.selectedStyle = $0 }
                    ),
                    accent: Binding(
                        get: { settings.selectedAccent },
                        set: { settings.selectedAccent = $0 }
                    ),
                    userPrompt: Binding(
                        get: { settings.userPrompt },
                        set: { settings.userPrompt = $0 }
                    ),
                    openSettings: { view = .settings }
                )
            } else {
                SettingsView(close: { view = .main })
            }
        }
        // System material — adapts to light/dark automatically
        .background(.regularMaterial)
    }
}

// MARK: Main view

struct MainPopoverView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var generator: GenerationCoordinator
    @EnvironmentObject var l10n: LocalizationManager

    @Binding var moodEnergy: Double
    @Binding var moodValence: Double
    @Binding var style: String
    @Binding var accent: String
    @Binding var userPrompt: String

    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 6) {
                Text(l10n.t("popover.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(l10n.t("popover.settings"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TodayHeroView()
                    LunarStripView()

                    Divider()

                    HStack {
                        Text(l10n.t("popover.recent"))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            manager.openCacheDirectory()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help(l10n.t("popover.openAlbumTip"))
                    }
                    if manager.wallpapers.isEmpty {
                        Text(l10n.t("popover.emptyHistory"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        HistoryRailView()
                    }

                    Divider()

                    Text(l10n.t("popover.mood"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    MoodPadView(energy: $moodEnergy, valence: $moodValence)

                    Text(l10n.t("popover.styleSection"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    StylePickerView(style: $style, accent: $accent, userPrompt: $userPrompt)

                    if let err = generator.lastError {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Button(action: triggerGenerate) {
                        HStack(spacing: 6) {
                            if generator.isLoading {
                                ProgressView().controlSize(.small)
                                Text(l10n.t("popover.generating"))
                            } else {
                                Image(systemName: "sparkles")
                                Text(l10n.t("popover.generateButton"))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(generator.isLoading)
                }
                .padding(12)
            }

            Divider()

            // Footer
            HStack {
                Text(l10n.t("popover.footerVersion"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button(l10n.t("common.quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func triggerGenerate() {
        Task {
            await generator.generate(
                settings: settings,
                manager: manager,
                mood: describeMood(energy: moodEnergy, valence: moodValence),
                moodEnergy: moodEnergy,
                moodValence: moodValence,
                style: style,
                accent: accent,
                userPrompt: userPrompt
            )
        }
    }
}

// MARK: Today hero

struct TodayHeroView: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var generator: GenerationCoordinator
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        ZStack {
            if let w = manager.current(), let img = NSImage(contentsOfFile: w.filePath) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.prompt)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(l10n.t("style.\(w.style)")) · \(localizedMoodLabel(forKey: w.mood))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.black.opacity(0.6), .clear],
                                                   startPoint: .bottom, endPoint: .top))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .contextMenu {
                        Button(l10n.t("common.openInFinder")) { manager.revealInFinder(w) }
                    }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.5), .accentColor.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 130)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "moon.stars")
                                .font(.system(size: 22))
                            Text(l10n.t("popover.heroPlaceholder"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            if generator.isLoading {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.black.opacity(0.55))
                    .frame(height: 130)
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    Text(generator.loadingLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    ProgressView(value: generator.loadingProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.white)
                        .frame(width: 140)
                }
            }
        }
        .frame(height: 130)
    }
}

// MARK: Lunar strip

struct LunarStripView: View {
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        let cal = Calendar(identifier: .chinese)
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MMMd"
        let chinese = f.string(from: Date())

        let g = DateFormatter()
        if l10n.effective == .zh {
            g.locale = Locale(identifier: "zh_CN")
            g.dateFormat = "M月d日 EEE"
        } else {
            g.locale = Locale(identifier: "en_US")
            g.dateFormat = "MMM d, EEE"
        }
        let solar = g.string(from: Date())

        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
            Text(solar)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(chinese)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: History rail (with right-click context menu)

struct HistoryRailView: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(manager.wallpapers, id: \Wallpaper.id) { (w: Wallpaper) in
                    let isCurrent = manager.currentId.map { $0 == w.id } ?? false
                    Button(action: { manager.setCurrent(w) }) {
                        ZStack(alignment: .topTrailing) {
                            if let img = NSImage(contentsOfFile: w.filePath) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 72, height: 48)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(.quaternary)
                                    .frame(width: 72, height: 48)
                            }
                            if isCurrent {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white, Color.accentColor)
                                    .padding(2)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(w.prompt)
                    .contextMenu {
                        Button(l10n.t("popover.contextSetWallpaper")) { manager.setCurrent(w) }
                        Button(l10n.t("common.openInFinder")) { manager.revealInFinder(w) }
                        Divider()
                        Button(l10n.t("common.delete"), role: .destructive) { manager.delete(w) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 54)
    }
}

// MARK: Mood pad

struct MoodPadView: View {
    @EnvironmentObject var l10n: LocalizationManager
    @Binding var energy: Double
    @Binding var valence: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: geo.size.height/2))
                        p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height/2))
                        p.move(to: CGPoint(x: geo.size.width/2, y: 0))
                        p.addLine(to: CGPoint(x: geo.size.width/2, y: geo.size.height))
                    }
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)

                    VStack {
                        HStack {
                            Text(l10n.t("popover.moodTired")).font(.system(size: 8)).foregroundStyle(.tertiary)
                            Spacer()
                            Text(l10n.t("popover.moodExcited")).font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        HStack {
                            Text(l10n.t("popover.moodDown")).font(.system(size: 8)).foregroundStyle(.tertiary)
                            Spacer()
                            Text(l10n.t("popover.moodCalm")).font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(4)

                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .shadow(radius: 1)
                        .position(x: valence * geo.size.width,
                                  y: (1 - energy) * geo.size.height)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let x = max(0, min(geo.size.width, value.location.x))
                    let y = max(0, min(geo.size.height, value.location.y))
                    valence = x / geo.size.width
                    energy = 1 - (y / geo.size.height)
                })
            }
            .frame(height: 80)

            HStack {
                Text(localizedMoodLabel(energy: energy, valence: valence))
                    .font(.caption.weight(.medium))
                Spacer()
                Text(l10n.t("popover.moodReadout", Int(energy*100), Int(valence*100)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: Style picker

struct StylePickerView: View {
    @EnvironmentObject var l10n: LocalizationManager
    @Binding var style: String
    @Binding var accent: String
    @Binding var userPrompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6)
            ], spacing: 6) {
                ForEach(STYLE_PRESETS) { preset in
                    StylePresetTile(
                        preset: preset,
                        isSelected: style == preset.id
                    ) {
                        style = preset.id
                    }
                }
            }
            HStack(spacing: 6) {
                Text(l10n.t("popover.accentLabel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(ACCENTS) { a in
                    Button(action: { accent = a.key }) {
                        Circle()
                            .fill(a.color)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle()
                                    .stroke(accent == a.key ? Color.accentColor : .clear,
                                            lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(a.name)
                }
            }
            TextField(l10n.t("popover.userPromptPlaceholder"),
                      text: $userPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            .lineLimit(2...3)
        }
    }
}

// MARK: Style tile

struct StylePresetTile: View {
    let preset: StylePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                StylePresetBackground(assetName: preset.assetName)

                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(preset.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 5)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.accentColor))
                        .overlay(Circle().stroke(.white, lineWidth: 1.2))
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(4.0/3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.12),
                            lineWidth: isSelected ? 1.6 : 0.5)
            )
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08),
                    radius: isSelected ? 3 : 1.5, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help(preset.label)
    }
}

struct StylePresetBackground: View {
    let assetName: String

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image = Self.loadImage(named: assetName) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipped()
        }
    }

    private static func loadImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "StylePresets"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}
