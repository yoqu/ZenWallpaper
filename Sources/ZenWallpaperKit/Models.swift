import Foundation

struct Wallpaper: Identifiable, Codable, Hashable {
    let id: String
    let date: String
    let prompt: String
    let style: String
    let mood: String
    let filePath: String
    var remoteWorkId: String?
    /// Server-side moderation state captured at the time the wallpaper landed
    /// in the local cache. One of "pending" / "approved" / "rejected", or nil
    /// for legacy entries saved before the cloud-library integration.
    var reviewStatus: String?

    var fileURL: URL { URL(fileURLWithPath: filePath) }
}

/// One row in the cloud-library list. Mirrors a subset of the backend
/// `WorkSummaryDto` payload — only the fields the popover actually renders.
struct RemoteWork: Identifiable, Hashable {
    let id: String
    let title: String
    let assetUrl: String
    let mimeType: String
    let aspectRatio: String?
    /// One of "pending" / "approved" / "rejected" (lowercased server enum).
    let moderationStatus: String
    let publishedAt: Date?
    let tagNames: [String]
}

/// One row of the qushenma credit ledger. Mirrors the shape returned by
/// `GET /api/credits/transactions/me` — we only surface the four fields the
/// history page actually displays.
struct CreditTransaction: Identifiable, Codable, Hashable {
    let id: String
    let amount: Int
    let type: String
    let reason: String?
    let createdAt: Date
}

enum AutoFreq: String, CaseIterable, Codable {
    case off, daily, hour4, hour1

    @MainActor
    var label: String {
        switch self {
        case .off: return LocalizationManager.shared.t("auto.freq.off")
        case .daily: return LocalizationManager.shared.t("auto.freq.daily")
        case .hour4: return LocalizationManager.shared.t("auto.freq.hour4")
        case .hour1: return LocalizationManager.shared.t("auto.freq.hour1")
        }
    }
}

enum HistoryLayout: String, CaseIterable, Codable {
    case rail, grid
    var label: String { self == .rail ? "rail" : "grid" }
}

/// How the wallpaper is applied when more than one display is connected.
///   - unified:    same image on every display (default; matches old behavior)
///   - perDisplay: each display has its own image, tracked by DisplayAssignmentStore
///   - mainOnly:   only the main display is touched; secondary displays are
///                 left at whatever the system was already showing
enum MultiDisplayMode: String, CaseIterable, Codable, Identifiable {
    case unified
    case perDisplay
    case mainOnly

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .unified:    return LocalizationManager.shared.t("settings.multiDisplay.unified")
        case .perDisplay: return LocalizationManager.shared.t("settings.multiDisplay.perDisplay")
        case .mainOnly:   return LocalizationManager.shared.t("settings.multiDisplay.mainOnly")
        }
    }
}
