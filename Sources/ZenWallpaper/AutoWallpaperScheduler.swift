import AppKit
import Foundation

@MainActor
final class AutoWallpaperScheduler: ObservableObject {
    @Published private(set) var statusText: String = LocalizationManager.shared.t("auto.status.idle")

    private let settings: AppSettings
    private let manager: WallpaperManager
    private let generator: GenerationCoordinator
    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current
    private var l10n: LocalizationManager { LocalizationManager.shared }

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var defaultsObserver: NSObjectProtocol?
    private var isChecking = false

    private let lastAutoGenerationKey = "lastAutoGenerationAt"
    private let lastAutoAttemptKey = "lastAutoAttemptAt"
    private let retryInterval: TimeInterval = 15 * 60
    private let tickInterval: TimeInterval = 60

    init(settings: AppSettings,
         manager: WallpaperManager,
         generator: GenerationCoordinator) {
        self.settings = settings
        self.manager = manager
        self.generator = generator
        start()
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    private func start() {
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluate(reason: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluate(reason: "wake")
            }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.evaluate(reason: "settings")
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await evaluate(reason: "launch")
        }
    }

    private func evaluate(reason: String) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let now = Date()
        guard !settings.apiKey.isEmpty else {
            statusText = l10n.t("auto.status.noKey")
            return
        }

        let decision = generationDecision(now: now)
        guard decision.shouldGenerate else {
            statusText = decision.status
            return
        }

        if let lastAttempt = defaults.object(forKey: lastAutoAttemptKey) as? Date,
           now.timeIntervalSince(lastAttempt) < retryInterval {
            let retryAt = lastAttempt.addingTimeInterval(retryInterval)
            statusText = l10n.t("auto.status.retryAfter", timeString(retryAt))
            return
        }

        guard !generator.isLoading else {
            statusText = l10n.t("auto.status.busy")
            return
        }

        defaults.set(now, forKey: lastAutoAttemptKey)
        statusText = l10n.t("auto.status.generating")

        let succeeded = await generator.generate(
            settings: settings,
            manager: manager,
            mood: describeMood(energy: settings.moodEnergy, valence: settings.moodValence),
            moodEnergy: settings.moodEnergy,
            moodValence: settings.moodValence,
            style: settings.selectedStyle,
            accent: settings.selectedAccent,
            userPrompt: settings.userPrompt
        )

        if succeeded {
            defaults.set(Date(), forKey: lastAutoGenerationKey)
            defaults.removeObject(forKey: lastAutoAttemptKey)
        }

        statusText = generationDecision(now: Date()).status
    }

    private func generationDecision(now: Date) -> GenerationDecision {
        switch settings.autoFreq {
        case .off:
            return GenerationDecision(false, l10n.t("auto.status.off"))
        case .hour1:
            return intervalDecision(now: now, seconds: 60 * 60, label: l10n.t("auto.label.hour1"))
        case .hour4:
            return intervalDecision(now: now, seconds: 4 * 60 * 60, label: l10n.t("auto.label.hour4"))
        case .daily:
            return dailyDecision(now: now)
        }
    }

    private func intervalDecision(now: Date, seconds: TimeInterval, label: String) -> GenerationDecision {
        guard let latest = latestActivityDate() else {
            return GenerationDecision(true, l10n.t("auto.status.intervalReady", label))
        }

        let next = latest.addingTimeInterval(seconds)
        if now >= next {
            return GenerationDecision(true, l10n.t("auto.status.intervalDue", label))
        }

        return GenerationDecision(false, l10n.t("auto.status.intervalNext", label, timeString(next)))
    }

    private func dailyDecision(now: Date) -> GenerationDecision {
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        if now < morning {
            return GenerationDecision(false, l10n.t("auto.status.dailyNext", timeString(morning)))
        }

        if let latest = latestActivityDate(), latest >= morning {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning) ?? now.addingTimeInterval(24 * 60 * 60)
            return GenerationDecision(false, l10n.t("auto.status.dailyNext", timeString(tomorrow)))
        }

        return GenerationDecision(true, l10n.t("auto.status.dailyReady"))
    }

    private func latestActivityDate() -> Date? {
        var dates: [Date] = []
        if let lastAuto = defaults.object(forKey: lastAutoGenerationKey) as? Date {
            dates.append(lastAuto)
        }
        dates.append(contentsOf: manager.wallpapers.compactMap { wallpaper in
            let attrs = try? FileManager.default.attributesOfItem(atPath: wallpaper.filePath)
            return attrs?[.modificationDate] as? Date
        })
        return dates.max()
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        if l10n.effective == .zh {
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "M月d日 HH:mm"
        } else {
            formatter.locale = Locale(identifier: "en_US")
            formatter.dateFormat = calendar.isDateInToday(date) ? "HH:mm" : "MMM d HH:mm"
        }
        return formatter.string(from: date)
    }
}

private struct GenerationDecision {
    let shouldGenerate: Bool
    let status: String

    init(_ shouldGenerate: Bool, _ status: String) {
        self.shouldGenerate = shouldGenerate
        self.status = status
    }
}
