import SwiftUI
import AppKit

enum PopoverView {
    case main, settings, credits
}

struct PopoverRoot: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var generator: GenerationCoordinator
    @EnvironmentObject var shenma: ShenmaConnectionManager

    @State private var view: PopoverView = .main

    var body: some View {
        Group {
            switch view {
            case .main:
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
                    openSettings: { view = .settings },
                    openCredits: { view = .credits }
                )
            case .settings:
                SettingsView(close: { view = .main })
            case .credits:
                CreditHistoryView(close: { view = .main })
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
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var l10n: LocalizationManager

    @Binding var moodEnergy: Double
    @Binding var moodValence: Double
    @Binding var style: String
    @Binding var accent: String
    @Binding var userPrompt: String

    let openSettings: () -> Void
    let openCredits: () -> Void

    /// In per-display mode, which display the next Generate call should target.
    /// Lazily defaulted to the main display's UUID the first time the picker
    /// renders; we don't pull it from AppStorage because the user's "default
    /// target" is naturally "whichever screen the menu bar happens to be on".
    @State private var targetDisplayUUID: String?
    @State private var screenChangeTick: Int = 0

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
                    AccountHeaderView(openCredits: openCredits)

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

                    if let current = manager.current(),
                       let url = makeWorkDetailUrl(workId: current.remoteWorkId,
                                                   baseUrl: settings.shenmaBaseUrl) {
                        HStack {
                            Spacer()
                            Link(destination: url) {
                                Label(l10n.t("popover.qushenmaOpen"), systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }

                    if shenma.isConnected {
                        Divider()
                        CloudLibrarySection()
                        Divider()
                        CloudFavoritesSection()
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

                    if !shenma.isConnected {
                        // Reaching the generate button is meaningless without a token —
                        // call this out plainly so users know to hit Settings → Connect first.
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .imageScale(.small)
                            Text(l10n.t("popover.needLoginHint"))
                            Spacer()
                            Button(l10n.t("popover.openSettings")) { openSettings() }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                    }

                    targetDisplayPicker

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
                    .disabled(generator.isLoading || !shenma.isConnected)
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
        // Only forward a target when per-display mode is on; in unified /
        // main-only modes the coordinator routes through `applyCurrent()`
        // which already does the right thing.
        let target: String? = settings.multiDisplayMode == .perDisplay
            ? (targetDisplayUUID ?? mainDisplayUUID())
            : nil
        Task {
            await generator.generate(
                settings: settings,
                manager: manager,
                shenma: shenma,
                mood: describeMood(energy: moodEnergy, valence: moodValence),
                moodEnergy: moodEnergy,
                moodValence: moodValence,
                style: style,
                accent: accent,
                userPrompt: userPrompt,
                targetDisplayUUID: target
            )
        }
    }

    @ViewBuilder
    private var targetDisplayPicker: some View {
        let displays = DisplayIdentity.allConnected()
        if settings.multiDisplayMode == .perDisplay && displays.count > 1 {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.on.rectangle")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(l10n.t("popover.targetDisplay"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding<String>(
                    get: { targetDisplayUUID ?? mainDisplayUUID() ?? displays.first?.uuid ?? "" },
                    set: { targetDisplayUUID = $0 }
                )) {
                    ForEach(displays) { d in
                        Text(d.localizedName).tag(d.uuid)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 140)
            }
            .id(screenChangeTick)
            .onReceive(NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screenChangeTick &+= 1
                if let uuid = targetDisplayUUID,
                   !displays.contains(where: { $0.uuid == uuid }) {
                    targetDisplayUUID = nil
                }
            }
        }
    }

    private func mainDisplayUUID() -> String? {
        guard let main = NSScreen.main else { return nil }
        return DisplayIdentity.from(main)?.uuid
    }
}

/// Compact account row at the top of the popover. Shows the connected username
/// + current credit balance, with a chevron-shaped button on the right that
/// opens the credit-history page. When not logged in, falls back to a hint.
struct AccountHeaderView: View {
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var settings: AppSettings

    let openCredits: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                if let account = shenma.account {
                    Text("@\(account.user.username)")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        Image(systemName: "leaf.circle.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green)
                        if let balance = shenma.creditBalance {
                            Text(l10n.t("popover.creditBalance", balance))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(l10n.t("popover.creditLoading"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    Text(l10n.t("popover.qushenmaNotConnected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if shenma.isConnected {
                Button(action: openCredits) {
                    Image(systemName: "list.bullet.rectangle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help(l10n.t("popover.creditHistory"))
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .task {
            // Refresh the cached balance whenever this view appears. Cheap, idempotent.
            await shenma.fetchCredits(baseUrl: settings.shenmaBaseUrl)
        }
    }
}

// MARK: Today hero

struct TodayHeroView: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var generator: GenerationCoordinator
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var settings: AppSettings

    @State private var screenChangeTick: Int = 0

    var body: some View {
        ZStack {
            if shouldUseSplit {
                splitHero
            } else {
                singleHero
            }

            if generator.isLoading {
                loadingOverlay
            }
        }
        // Height is set inside `singleHero` (130pt) but left flexible for
        // `splitHero`, which shrinks proportionally to keep each tile at the
        // image's true aspect ratio (so 16:9 wallpapers don't get cropped
        // into square thumbnails when two displays render side-by-side).
        .id(screenChangeTick)
        .onReceive(NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenChangeTick &+= 1
        }
    }

    /// Split into per-display tiles only when the user is in per-display mode,
    /// has multiple displays connected, AND at least two of them are showing
    /// different wallpapers right now. Otherwise the single big hero stays —
    /// no point in shrinking it to show three identical tiles.
    private var shouldUseSplit: Bool {
        guard settings.multiDisplayMode == .perDisplay else { return false }
        let displays = DisplayIdentity.allConnected()
        guard displays.count > 1 else { return false }
        let ids: [String] = displays.compactMap { d in
            (manager.wallpaperForDisplay(d.uuid) ?? manager.current())?.id
        }
        return Set(ids).count > 1
    }

    @ViewBuilder
    private var splitHero: some View {
        // Plain HStack: each tile claims `maxWidth: .infinity` so the HStack
        // divides the available 236pt-ish row evenly. We deliberately avoid
        // `GeometryReader` here — under `MenuBarExtra(.window)` it can fire
        // with size=(0,0) on the first layout pass and trip the SwiftUI scene
        // cache (KEY_TYPE_OF_DICTIONARY_VIOLATES_HASHABLE_REQUIREMENTS crash).
        HStack(spacing: 6) {
            ForEach(DisplayIdentity.allConnected()) { display in
                DisplayHeroTile(display: display)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var singleHero: some View {
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
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        ZStack {
            // No fixed height: matches whatever the hero (single or split) is.
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.55))
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
}

/// Single tile in the split hero. Two key constraints:
///
///   1. Each tile owns its image's true aspect ratio. We never crop a 16:9
///      wallpaper into a near-square thumbnail just because we split the row.
///   2. The tile width is whatever the HStack hands us. We never echo the
///      Image's intrinsic pixel size back to the parent (would widen the
///      popover window).
///
/// Both come from the same primitive: `Color.clear.aspectRatio(imgRatio,
/// contentMode: .fit)`. Color.clear accepts any proposed width without
/// pushing back, and `aspectRatio` then makes the *frame* match the image —
/// so the Image overlay fills exactly with no letterbox and no crop.
private struct DisplayHeroTile: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var l10n: LocalizationManager

    let display: DisplayIdentity

    var body: some View {
        let wallpaper = manager.wallpaperForDisplay(display.uuid) ?? manager.current()
        let nsImage: NSImage? = wallpaper.flatMap { NSImage(contentsOfFile: $0.filePath) }
        let aspect: CGFloat = {
            if let img = nsImage, img.size.height > 0 {
                return max(img.size.width / img.size.height, 0.1)
            }
            // No image yet — fall back to the display's own aspect so the
            // placeholder tile still has the right shape.
            return max(display.frame.width / max(display.frame.height, 1), 0.1)
        }()

        ZStack(alignment: .bottom) {
            Color.clear
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    if let img = nsImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(colors: [.accentColor.opacity(0.45),
                                                .accentColor.opacity(0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay {
                                Image(systemName: "moon.stars")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 3) {
                Image(systemName: display.isMain ? "display.2" : "display")
                    .font(.system(size: 9))
                Text(display.localizedName)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if display.isMain {
                    Text(l10n.t("settings.displayMain"))
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.25), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear],
                                       startPoint: .bottom, endPoint: .top))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .help(wallpaper?.prompt ?? "")
        .contextMenu {
            if let w = wallpaper {
                Button(l10n.t("common.openInFinder")) { manager.revealInFinder(w) }
            }
        }
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

// MARK: Per-display submenu builder

/// "Set on display" context-menu entry. In single-display setups (or non-
/// per-display modes) this collapses to a plain "Set as wallpaper" button so
/// the right-click menu doesn't gain a useless nested level. In per-display
/// mode with 2+ screens it becomes a submenu with one entry per display plus
/// an "All displays" shortcut.
struct SetOnDisplayMenu: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var l10n: LocalizationManager

    let wallpaper: Wallpaper
    var onApply: (() -> Void)? = nil

    var body: some View {
        let displays = DisplayIdentity.allConnected()
        if settings.multiDisplayMode == .perDisplay && displays.count > 1 {
            Menu(l10n.t("popover.setOnDisplay")) {
                ForEach(displays) { d in
                    Button(rowLabel(for: d)) {
                        manager.setForDisplay(wallpaper, displayUUID: d.uuid)
                        onApply?()
                    }
                }
                Divider()
                Button(l10n.t("popover.setOnAllDisplays")) {
                    manager.setForAllDisplays(wallpaper)
                    onApply?()
                }
            }
        } else {
            Button(l10n.t("popover.contextSetWallpaper")) {
                manager.setCurrent(wallpaper)
                onApply?()
            }
        }
    }

    private func rowLabel(for display: DisplayIdentity) -> String {
        if display.isMain {
            return "\(display.localizedName) · \(l10n.t("settings.displayMain"))"
        }
        return display.localizedName
    }
}

// MARK: History rail (with right-click context menu)

struct HistoryRailView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(manager.wallpapers, id: \Wallpaper.id) { (w: Wallpaper) in
                    HistoryRailItem(wallpaper: w)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 78)
    }
}

private struct HistoryRailItem: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var settings: AppSettings

    let wallpaper: Wallpaper

    var body: some View {
        let isCurrent = manager.currentId.map { $0 == wallpaper.id } ?? false
        VStack(spacing: 3) {
            Button(action: { manager.setCurrent(wallpaper) }) {
                ZStack(alignment: .topTrailing) {
                    if let img = NSImage(contentsOfFile: wallpaper.filePath) {
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
                    } else if let status = wallpaper.reviewStatus {
                        reviewBadge(for: status)
                            .padding(2)
                    } else if wallpaper.remoteWorkId != nil {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.white, Color.green)
                            .padding(2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isCurrent ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .help(wallpaper.prompt)

            HStack(spacing: 4) {
                Button {
                    manager.revealInFinder(wallpaper)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(l10n.t("common.openInFinder"))

                if let url = makeWorkDetailUrl(workId: wallpaper.remoteWorkId,
                                               baseUrl: settings.shenmaBaseUrl) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(l10n.t("popover.qushenmaOpen"))
                } else {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary.opacity(0.4))
                        .frame(width: 18, height: 16)
                        .help(l10n.t("popover.qushenmaUnavailable"))
                }
            }
            .frame(width: 72)
        }
        .contextMenu {
            SetOnDisplayMenu(wallpaper: wallpaper)
            Button(l10n.t("common.openInFinder")) { manager.revealInFinder(wallpaper) }
            if let url = makeWorkDetailUrl(workId: wallpaper.remoteWorkId,
                                           baseUrl: settings.shenmaBaseUrl) {
                Link(destination: url) {
                    Text(l10n.t("popover.qushenmaOpen"))
                }
            }
            Divider()
            Button(l10n.t("common.delete"), role: .destructive) { manager.delete(wallpaper) }
        }
    }

    private func reviewBadge(for status: String) -> some View {
        let icon: String
        let color: Color
        switch status.lowercased() {
        case "approved": icon = "checkmark.seal.fill"; color = .green
        case "rejected": icon = "xmark.seal.fill";    color = .red
        default:         icon = "clock.fill";          color = .orange
        }
        return Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(.white, color)
            .shadow(color: .black.opacity(0.3), radius: 1)
    }
}

// MARK: Cloud library

/// Section showing the logged-in user's recent works on qushenma. Filters by
/// the current screen's aspect ratio so what's listed actually fits as a
/// wallpaper. Each tile carries a moderation badge (pending / approved /
/// rejected) — rejected works are still settable locally even though the
/// public site won't display them.
struct CloudLibrarySection: View {
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(l10n.t("popover.cloudLibrary"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if shenma.isLoadingCloudWorks {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(l10n.t("popover.cloudLibraryRefresh"))
                }
            }
            if let err = shenma.cloudWorksError, shenma.cloudWorks.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            if shenma.cloudWorks.isEmpty && !shenma.isLoadingCloudWorks {
                Text(l10n.t("popover.cloudLibraryEmpty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 6) {
                        ForEach(shenma.cloudWorks) { item in
                            CloudLibraryItem(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 80)
            }
        }
        .task {
            // First open of the popover: load the cloud library. Cached in the
            // manager so re-opening the popover doesn't refetch.
            if shenma.cloudWorks.isEmpty {
                await refresh()
            }
        }
    }

    private func refresh() async {
        await shenma.fetchCloudWorks(
            baseUrl: settings.shenmaBaseUrl,
            aspectRatio: WallpaperScreenPolicy.currentAspectRatioSlug(),
            tagSlug: nil
        )
    }
}

struct CloudFavoritesSection: View {
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var l10n: LocalizationManager

    @State private var selectedCollectionId: String?

    private var currentWorks: [RemoteWork] {
        guard let id = selectedCollectionId else { return [] }
        return shenma.collectionWorks[id] ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Text(l10n.t("popover.cloudFavorites"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if shenma.isLoadingCollections || shenma.isLoadingCollectionWorks {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help(l10n.t("popover.cloudFavoritesRefresh"))
                }
            }

            // Collection tabs
            if !shenma.collections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(shenma.collections) { collection in
                            CollectionTabButton(
                                title: collection.isDefault
                                    ? l10n.t("popover.collectionDefault")
                                    : collection.title,
                                count: collection.itemCount,
                                isSelected: selectedCollectionId == collection.id
                            ) {
                                selectedCollectionId = collection.id
                                Task { await refreshWorks(collectionId: collection.id) }
                            }
                        }
                    }
                }
            }

            // Error
            if let err = shenma.collectionsError, shenma.collections.isEmpty {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            // Works grid
            if shenma.collections.isEmpty && !shenma.isLoadingCollections {
                Text(l10n.t("popover.cloudFavoritesEmpty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if currentWorks.isEmpty && !shenma.isLoadingCollectionWorks && selectedCollectionId != nil {
                Text(l10n.t("popover.cloudFavoritesEmpty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if !currentWorks.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 6) {
                        ForEach(currentWorks) { item in
                            CloudLibraryItem(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 80)
            }
        }
        .task {
            if shenma.collections.isEmpty {
                await refreshAll()
            }
        }
    }

    private func refreshAll() async {
        await shenma.fetchCollections(baseUrl: settings.shenmaBaseUrl)
        // Auto-select first collection if none selected
        if selectedCollectionId == nil || !shenma.collections.contains(where: { $0.id == selectedCollectionId }) {
            selectedCollectionId = shenma.collections.first?.id
        }
        if let id = selectedCollectionId {
            await refreshWorks(collectionId: id)
        }
    }

    private func refreshWorks(collectionId: String) async {
        // Skip if already cached
        if shenma.collectionWorks[collectionId] != nil { return }
        await shenma.fetchCollectionWorks(
            baseUrl: settings.shenmaBaseUrl,
            collectionId: collectionId,
            aspectRatio: WallpaperScreenPolicy.currentAspectRatioSlug()
        )
    }
}

private struct CollectionTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(title) (\(count))")
                .font(.caption)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
    }
}

struct CloudLibraryItem: View {
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var l10n: LocalizationManager

    let item: RemoteWork

    @State private var thumbnail: NSImage?
    @State private var isApplying = false

    var body: some View {
        VStack(spacing: 3) {
            Button(action: { Task { await apply() } }) {
                ZStack(alignment: .topTrailing) {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 48)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    } else {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.quaternary)
                            .frame(width: 72, height: 48)
                            .overlay { ProgressView().controlSize(.small) }
                    }
                    statusBadge
                        .padding(2)
                    if isApplying {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.black.opacity(0.55))
                            .frame(width: 72, height: 48)
                            .overlay {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help(tooltip)

            Text(statusLabel)
                .font(.system(size: 9))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .frame(width: 72)
        }
        .contextMenu {
            Button(l10n.t("popover.contextSetWallpaper")) { Task { await apply() } }
            if item.moderationStatus != "rejected",
               let url = makeWorkDetailUrl(workId: item.id,
                                           baseUrl: settings.shenmaBaseUrl) {
                Link(destination: url) { Text(l10n.t("popover.qushenmaOpen")) }
            }
        }
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private var tooltip: String {
        let title = item.title.isEmpty ? l10n.t("popover.cloudLibraryUntitled") : item.title
        if item.moderationStatus == "rejected" {
            return "\(title) · \(l10n.t("popover.review.rejectedTip"))"
        }
        return title
    }

    private var statusLabel: String {
        switch item.moderationStatus {
        case "approved": return l10n.t("popover.review.approved")
        case "rejected": return l10n.t("popover.review.rejected")
        default:         return l10n.t("popover.review.pending")
        }
    }

    private var statusColor: Color {
        switch item.moderationStatus {
        case "approved": return .green
        case "rejected": return .red
        default:         return .orange
        }
    }

    private var statusBadge: some View {
        let icon: String
        let color: Color
        switch item.moderationStatus {
        case "approved":
            icon = "checkmark.seal.fill"; color = .green
        case "rejected":
            icon = "xmark.seal.fill"; color = .red
        default:
            icon = "clock.fill"; color = .orange
        }
        return Image(systemName: icon)
            .font(.system(size: 11))
            .foregroundStyle(.white, color)
            .shadow(color: .black.opacity(0.3), radius: 1)
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, let url = URL(string: item.assetUrl) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return }
        thumbnail = image
    }

    private func apply() async {
        guard !isApplying, let url = URL(string: item.assetUrl) else { return }
        isApplying = true
        defer { isApplying = false }
        // Skip re-download if this cloud work is already cached locally.
        if let existing = manager.wallpapers.first(where: {
            $0.remoteWorkId == item.id
                && FileManager.default.fileExists(atPath: $0.filePath)
        }) {
            manager.setCurrent(existing)
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let mime = (response as? HTTPURLResponse)?.mimeType ?? item.mimeType
            let prompt = item.title.isEmpty
                ? l10n.t("popover.cloudLibraryUntitled")
                : item.title
            if let saved = manager.addNew(
                imageData: data,
                mimeType: mime,
                prompt: prompt,
                style: settings.selectedStyle,
                mood: "中性",
                cacheLimit: settings.cacheLimit,
                remoteWorkId: item.id,
                reviewStatus: item.moderationStatus
            ) {
                manager.setCurrent(saved)
            }
        } catch {
        }
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
            ScrollableTextEditor(
                text: $userPrompt,
                placeholder: l10n.t("popover.userPromptPlaceholder")
            )
            .frame(height: 60)
        }
    }
}

// MARK: Scrollable text editor (AppKit-backed)
//
// NSTextView wrapped in NSScrollView so wheel scrolling stays inside the
// input instead of bubbling up to the surrounding popover ScrollView.
struct ScrollableTextEditor: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ScrollEatingScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.drawsBackground = false
        textView.string = text
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        context.coordinator.textView = textView
        context.coordinator.applyPlaceholder()

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.applyPlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScrollableTextEditor
        weak var textView: NSTextView?

        init(_ parent: ScrollableTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            applyPlaceholder()
        }

        func applyPlaceholder() {
            guard let tv = textView else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            ]
            tv.setValue(NSAttributedString(string: parent.placeholder, attributes: attrs),
                        forKey: "placeholderAttributedString")
        }
    }
}

// NSScrollView subclass that swallows scroll-wheel events whenever the
// cursor is inside the input. When content can scroll, super scrolls it;
// when it can't, we still avoid forwarding the event up the responder
// chain so the surrounding SwiftUI ScrollView stays put.
final class ScrollEatingScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
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
