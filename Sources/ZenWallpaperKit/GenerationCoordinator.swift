import Foundation
import SwiftUI

// Internal access on purpose — the app and the test runner both reach this through
// `@testable import ZenWallpaperKit`, which is debug-only via Package.swift.
@MainActor
final class GenerationCoordinator: ObservableObject {
    @Published var isLoading = false
    @Published var loadingLabel = ""
    @Published var loadingProgress: Double = 0
    @Published var lastError: String?

    private let api = APIClient()
    private var progressTimer: Task<Void, Never>?

    // The qushenma backend generation endpoint is synchronous and typically
    // takes 25–60s. Pace the simulator toward a 99% cap over this window, then
    // hold until the real call returns.
    private static let simulatedDurationSeconds: Double = 35
    private static let simulatedCap: Double = 0.99

    @discardableResult
    func generate(settings: AppSettings,
                  manager: WallpaperManager,
                  shenma: ShenmaConnectionManager,
                  mood: String,
                  moodEnergy: Double,
                  moodValence: Double,
                  style: String,
                  accent: String,
                  userPrompt: String,
                  targetDisplayUUID: String? = nil) async -> Bool {
        let l10n = LocalizationManager.shared
        guard !isLoading else { return false }
        // Generation is gated on a live qushenma session: the website's API does
        // the credit deduction + work creation, so without a Bearer token there's
        // nothing for us to call.
        guard shenma.isConnected, let token = shenma.token() else {
            lastError = l10n.t("error.needLogin")
            return false
        }
        isLoading = true
        lastError = nil
        defer {
            stopSimulatedProgress()
            isLoading = false
            loadingProgress = 0
            loadingLabel = ""
        }

        await update(l10n.t("gen.collecting"), 0.05)
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
        await update(l10n.t("gen.composing"), 0.08)

        // In per-display mode the caller hands us the screen the generation is
        // for, so we can size the prompt to that monitor's aspect ratio
        // instead of always biasing toward the main display.
        let targetScreen: NSScreen = {
            if let uuid = targetDisplayUUID,
               let identity = DisplayIdentity.allConnected().first(where: { $0.uuid == uuid }),
               let screen = identity.screen {
                return screen
            }
            return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        }()
        let size = WallpaperScreenPolicy.bestSize(for: targetScreen)
        await update(l10n.t("gen.calling", size), 0.10)

        startSimulatedProgress(from: 0.10,
                               to: Self.simulatedCap,
                               durationSeconds: Self.simulatedDurationSeconds)

        let result: ImageGenerationResult
        do {
            result = try await api.generate(
                shenmaBaseUrl: settings.shenmaBaseUrl,
                token: token,
                prompt: prompt,
                size: size,
                debugLogging: settings.debugLogging
            )
        } catch let error as APIError {
            stopSimulatedProgress()
            // 401 → the cached account is dead, kick it out so the UI prompts to reconnect.
            if case .unauthorized = error {
                shenma.clearAfterUnauthorized()
            }
            lastError = error.localizedDescription
            return false
        } catch {
            stopSimulatedProgress()
            lastError = error.localizedDescription
            return false
        }

        stopSimulatedProgress()

        // Server already deducted the credit — pull the new balance directly off
        // the response so we don't waste a round-trip.
        shenma.setCreditBalance(result.balance)

        await update(l10n.t("gen.downloading"), 0.97)
        let defaultPrompt = "\(mood) · \(style)"
        guard let wp = manager.addNew(imageData: result.data,
                                       mimeType: result.mimeType,
                                       prompt: userPrompt.isEmpty ? defaultPrompt : userPrompt,
                                       style: style,
                                       mood: mood,
                                       cacheLimit: settings.cacheLimit,
                                       remoteWorkId: result.workId,
                                       reviewStatus: "pending") else {
            lastError = l10n.t("error.saveImageFailed")
            return false
        }

        await update(l10n.t("gen.applying"), Self.simulatedCap)
        if let uuid = targetDisplayUUID {
            // Explicit target → pin to that display only, regardless of mode.
            manager.setForDisplay(wp, displayUUID: uuid)
        } else {
            manager.applyCurrent()
        }

        await update(l10n.t("gen.done"), 1.0)
        try? await Task.sleep(nanoseconds: 200_000_000)
        return true
    }

    @MainActor
    private func update(_ label: String, _ progress: Double) async {
        loadingLabel = label
        // Monotonic: never let a later checkpoint backslide the bar. The
        // simulator and backend callbacks may have already moved past `progress`.
        if progress > loadingProgress {
            loadingProgress = progress
        }
    }

    private func startSimulatedProgress(from start: Double,
                                        to cap: Double,
                                        durationSeconds: Double) {
        stopSimulatedProgress()
        let begin = Date()
        progressTimer = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(begin)
                let t = min(elapsed / durationSeconds, 1.0)
                // Ease-out cubic: starts brisk, slows as it approaches the cap.
                let eased = 1.0 - pow(1.0 - t, 3.0)
                let target = start + (cap - start) * eased
                await MainActor.run {
                    guard let self else { return }
                    if target > self.loadingProgress {
                        self.loadingProgress = target
                    }
                }
                if elapsed >= durationSeconds {
                    // Held at cap — slow down ticks; the real call will end us.
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
    }

    private func stopSimulatedProgress() {
        progressTimer?.cancel()
        progressTimer = nil
    }
}
