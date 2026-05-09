import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system, en, zh
    var id: String { rawValue }

    /// Detect the language to use when "system" is selected.
    static var systemDetected: AppLanguage {
        let id = (Locale.preferredLanguages.first ?? "en").lowercased()
        return id.hasPrefix("zh") ? .zh : .en
    }

    /// Read the user's stored choice and resolve `system` to an actual language.
    /// Safe to call from any thread — reads from UserDefaults.
    static var resolvedFromDefaults: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        let stored = AppLanguage(rawValue: raw) ?? .system
        switch stored {
        case .system: return systemDetected
        case .en: return .en
        case .zh: return .zh
        }
    }
}

/// Non-isolated lookup. Safe to call from any context (e.g. error description on background threads).
func localizedString(_ key: String, language: AppLanguage? = nil) -> String {
    let lang = language ?? AppLanguage.resolvedFromDefaults
    let table = lang == .zh ? zhStrings : enStrings
    return table[key] ?? enStrings[key] ?? key
}

func localizedString(_ key: String, language: AppLanguage? = nil, _ args: CVarArg...) -> String {
    let template = localizedString(key, language: language)
    if args.isEmpty { return template }
    return String(format: template, arguments: args)
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage = .system

    var effective: AppLanguage {
        switch language {
        case .system: return AppLanguage.systemDetected
        case .en: return .en
        case .zh: return .zh
        }
    }

    func t(_ key: String) -> String {
        localizedString(key, language: effective)
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let template = t(key)
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }

    func languageDisplayName(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return t("settings.language.system")
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

// MARK: - Strings tables (Sendable plain dictionaries)

private let enStrings: [String: String] = [
    // common
    "common.back": "Back",
    "common.open": "Open",
    "common.openInFinder": "Show in Finder",
    "common.openInFinderShort": "Open in Finder",
    "common.delete": "Delete",
    "common.quit": "Quit",
    "common.cancel": "Cancel",
    "common.images_count": "%d images",

    // popover
    "popover.title": "Zen",
    "popover.settings": "Settings",
    "popover.recent": "Recent",
    "popover.openAlbumTip": "Open local album folder",
    "popover.emptyHistory": "No history yet — tap below to generate your first one.",
    "popover.mood": "Mood",
    "popover.styleSection": "Style · Accent · Extras",
    "popover.generating": "Generating…",
    "popover.generateButton": "Generate Today's Wallpaper",
    "popover.heroPlaceholder": "From mood, date & lunar calendar — today's piece",
    "popover.contextSetWallpaper": "Set as wallpaper",
    "popover.qushenmaNotConnected": "Not connected — open Settings to connect",
    "popover.qushenmaOpen": "View on qushenma",
    "popover.qushenmaUnavailable": "Not uploaded yet",
    "popover.cloudLibrary": "From Cloud",
    "popover.cloudLibraryRefresh": "Refresh cloud library",
    "popover.cloudLibraryEmpty": "No matching cloud works for this screen",
    "popover.cloudLibraryUntitled": "Untitled",
    "popover.review.pending": "Reviewing",
    "popover.review.approved": "Approved",
    "popover.review.rejected": "Rejected",
    "popover.review.rejectedTip": "Hidden from public site, still settable locally",
    "popover.creditBalance": "%d credits",
    "popover.creditLoading": "loading…",
    "popover.creditHistory": "Credit history",
    "popover.needLoginHint": "Connect to qushenma to generate.",
    "popover.openSettings": "Settings",
    "popover.footerVersion": "Zen · v1.0",
    "popover.accentLabel": "Accent",
    "popover.userPromptPlaceholder": "Extra prompt (optional): ridges, mist, distant lights…",
    "popover.moodTired": "Tired",
    "popover.moodExcited": "Excited",
    "popover.moodDown": "Down",
    "popover.moodCalm": "Calm",
    "popover.moodReadout": "Energy %d  Mood %d",

    // settings
    "settings.title": "Settings",
    "settings.section.generation": "Generation",
    "settings.section.system": "System",
    "settings.section.shenma": "qushenma.com",
    "settings.section.debug": "Debug",
    "settings.section.about": "About",
    "settings.imageSize": "Image Size",
    "settings.fitsScreen": "Fits main screen %@",
    "settings.useDate": "Include date",
    "settings.useLunar": "Include lunar calendar",
    "settings.autoGenerate": "Auto-generate",
    "settings.autoStatus": "Auto status",
    "settings.historyLimit": "History limit",
    "settings.cacheDir": "Cache directory",
    "settings.debugLogging": "Debug logs",
    "settings.logsDir": "Logs directory",
    "settings.logsTip": "Open logs directory in Finder",
    "settings.debugDescription": "When enabled, every backend request/response is written to ~/Library/Application Support/ZenWallpaper/logs/api-YYYY-MM-DD.log. Use only when troubleshooting.",
    "settings.feedback": "Feedback",
    "settings.wechat": "WeChat",
    "settings.wechatTip": "Show WeChat QR code",
    "settings.wechatLabel": "WeChat: yoqu2020",
    "settings.qrMissing": "QR code missing",
    "settings.privacyNote": "Cached images live at ~/Library/Application Support/ZenWallpaper/cache/. Generation runs entirely on qushenma.com.",
    "settings.language": "Language",
    "settings.language.system": "Follow System",
    "settings.shenmaEndpoint": "Endpoint",
    "settings.shenmaEndpoint.production": "Production",
    "settings.shenmaEndpoint.localhost": "Local dev",
    "settings.shenmaEndpoint.custom": "Custom",
    "settings.shenmaBaseUrl": "qushenma URL",
    "settings.shenmaBaseUrlHelp": "Defaults to https://www.qushenma.com. Switch to \"Local dev\" when running the qushenma frontend at http://127.0.0.1:5173.",
    "settings.shenmaStatus": "Connection",
    "settings.shenmaConnecting": "Waiting for browser confirmation",
    "settings.shenmaDisconnected": "Not connected",
    "settings.shenmaConnect": "Connect",
    "settings.shenmaCancel": "Cancel",
    "settings.shenmaDisconnect": "Disconnect",

    // auto status
    "auto.status.idle": "Auto-generation standing by",
    "auto.status.noLogin": "Auto-generation paused: connect qushenma first",
    "auto.status.generating": "Auto-generating…",
    "auto.status.busy": "Generating now — auto task waits for next tick",
    "auto.status.retryAfter": "Last auto-generation incomplete, retry after %@",
    "auto.status.off": "Auto-generation off",
    "auto.status.intervalReady": "%@ auto-generation ready",
    "auto.status.intervalDue": "%@ auto-generation due",
    "auto.status.intervalNext": "%@ auto-generation next at %@",
    "auto.status.dailyNext": "Daily morning auto-generation next at %@",
    "auto.status.dailyReady": "Today's auto-generation ready",

    "auto.freq.off": "Off",
    "auto.freq.daily": "Daily morning",
    "auto.freq.hour4": "Every 4 hours",
    "auto.freq.hour1": "Every hour",
    "auto.label.daily": "Daily morning",
    "auto.label.hour4": "Every 4 hours",
    "auto.label.hour1": "Hourly",

    // styles
    "style.极简": "Minimal",
    "style.水彩": "Watercolor",
    "style.摄影": "Photography",
    "style.赛博朋克": "Cyberpunk",
    "style.胶片": "Film",
    "style.油画": "Oil Painting",

    // accents
    "accent.auto": "Mood",
    "accent.ink": "Ink",
    "accent.sand": "Sand",
    "accent.sea": "Sea",
    "accent.moss": "Moss",
    "accent.ember": "Ember",

    // moods
    "mood.兴奋": "Excited",
    "mood.焦躁": "Restless",
    "mood.愉悦": "Pleasant",
    "mood.专注": "Focused",
    "mood.平静": "Calm",
    "mood.松弛": "Relaxed",
    "mood.疲惫": "Tired",
    "mood.中性": "Neutral",

    // errors
    "error.needLogin": "Connect to qushenma first to generate.",
    "error.saveImageFailed": "Failed to save image.",
    "error.badResponse": "Bad response: %@",
    "error.decoding": "Decoding failed: %@",
    "error.noImage": "No image returned.",
    "error.http": "HTTP %d: %@",
    "error.network": "Network error: %@",
    "error.taskFailed": "Generation failed: %@",
    "error.taskTimeout": "Generation timed out.",
    "error.urlInvalid": "Invalid URL",
    "error.taskUrlInvalid": "Invalid task URL",
    "error.nonHttpResponse": "Non-HTTP response",
    "error.unknown": "Unknown reason",

    // generation labels
    "gen.collecting": "Collecting mood / date / lunar…",
    "gen.composing": "Composing prompt…",
    "gen.calling": "Calling qushenma · %@…",
    "gen.downloading": "Downloading image…",
    "gen.applying": "Applying to displays…",
    "gen.done": "Done",
    "gen.progress": "Generating… (%d%%)",

    // credit history
    "credits.title": "Credit history",
    "credits.empty": "No credit transactions yet.",
    "credits.loadMore": "Load more",
    "credits.type.GENERATION_CHARGE": "AI generation",
    "credits.type.GENERATION_REFUND": "Generation refund",
    "credits.type.CHECKIN": "Daily check-in",
    "credits.type.ADMIN_ADJUSTMENT": "Admin adjustment",
    "credits.type.unknown": "Other",
]

private let zhStrings: [String: String] = [
    // common
    "common.back": "返回",
    "common.open": "打开",
    "common.openInFinder": "在 Finder 中显示",
    "common.openInFinderShort": "在 Finder 中打开",
    "common.delete": "删除",
    "common.quit": "退出",
    "common.cancel": "取消",
    "common.images_count": "%d 张",

    // popover
    "popover.title": "禅 · Zen",
    "popover.settings": "设置",
    "popover.recent": "最近",
    "popover.openAlbumTip": "打开本地相册目录",
    "popover.emptyHistory": "还没有历史，点击下方生成第一张",
    "popover.mood": "心情",
    "popover.styleSection": "风格 · 主色 · 补充",
    "popover.generating": "正在生成…",
    "popover.generateButton": "生成今日壁纸",
    "popover.heroPlaceholder": "由心情、日期与黄历，生成今日一张",
    "popover.contextSetWallpaper": "设为壁纸",
    "popover.qushenmaNotConnected": "未连接神马图鉴 — 在设置中连接",
    "popover.qushenmaOpen": "在网站查看作品",
    "popover.qushenmaUnavailable": "尚未上传到网站",
    "popover.cloudLibrary": "云端作品",
    "popover.cloudLibraryRefresh": "刷新云端列表",
    "popover.cloudLibraryEmpty": "当前屏幕比例下暂无云端作品",
    "popover.cloudLibraryUntitled": "未命名作品",
    "popover.review.pending": "审核中",
    "popover.review.approved": "已通过",
    "popover.review.rejected": "已驳回",
    "popover.review.rejectedTip": "网站上不展示，仍可在本地设为壁纸",
    "popover.creditBalance": "积分 %d",
    "popover.creditLoading": "加载中…",
    "popover.creditHistory": "积分明细",
    "popover.needLoginHint": "需先连接神马图鉴才能生图。",
    "popover.openSettings": "前往设置",
    "popover.footerVersion": "禅 · v1.0",
    "popover.accentLabel": "主色",
    "popover.userPromptPlaceholder": "补充提示词（可选）：山脊、薄雾、远处灯火…",
    "popover.moodTired": "疲惫",
    "popover.moodExcited": "兴奋",
    "popover.moodDown": "低落",
    "popover.moodCalm": "平静",
    "popover.moodReadout": "能量 %d  情绪 %d",

    // settings
    "settings.title": "设置",
    "settings.section.generation": "生成",
    "settings.section.system": "系统",
    "settings.section.shenma": "qushenma.com",
    "settings.section.debug": "调试",
    "settings.section.about": "关于",
    "settings.imageSize": "生成尺寸",
    "settings.fitsScreen": "适配主屏 %@",
    "settings.useDate": "附加日期",
    "settings.useLunar": "附加黄历",
    "settings.autoGenerate": "自动生成",
    "settings.autoStatus": "自动状态",
    "settings.historyLimit": "历史保留",
    "settings.cacheDir": "缓存目录",
    "settings.debugLogging": "调试日志",
    "settings.logsDir": "日志目录",
    "settings.logsTip": "在 Finder 中打开日志目录",
    "settings.debugDescription": "开启后，每次后端请求/响应原文会写入 ~/Library/Application Support/ZenWallpaper/logs/api-YYYY-MM-DD.log。仅在排查问题时启用。",
    "settings.feedback": "反馈",
    "settings.wechat": "微信",
    "settings.wechatTip": "显示微信二维码",
    "settings.wechatLabel": "微信号:yoqu2020",
    "settings.qrMissing": "二维码资源缺失",
    "settings.privacyNote": "缓存目录：~/Library/Application Support/ZenWallpaper/cache/。生图全部在 qushenma.com 上完成。",
    "settings.language": "语言",
    "settings.language.system": "跟随系统",
    "settings.shenmaEndpoint": "环境",
    "settings.shenmaEndpoint.production": "生产",
    "settings.shenmaEndpoint.localhost": "本地调试",
    "settings.shenmaEndpoint.custom": "自定义",
    "settings.shenmaBaseUrl": "qushenma 地址",
    "settings.shenmaBaseUrlHelp": "默认走 https://www.qushenma.com。本地调试时切到「本地调试」会用 http://127.0.0.1:5173。",
    "settings.shenmaStatus": "连接状态",
    "settings.shenmaConnecting": "等待浏览器确认",
    "settings.shenmaDisconnected": "未连接",
    "settings.shenmaConnect": "连接",
    "settings.shenmaCancel": "取消",
    "settings.shenmaDisconnect": "断开连接",

    // auto status
    "auto.status.idle": "自动生成待命中",
    "auto.status.noLogin": "自动生成已暂停：请先连接神马图鉴",
    "auto.status.generating": "自动生成中…",
    "auto.status.busy": "正在生成中，自动任务等待下一轮检查",
    "auto.status.retryAfter": "上次自动生成未完成，%@ 后重试",
    "auto.status.off": "自动生成已关闭",
    "auto.status.intervalReady": "%@自动生成准备开始",
    "auto.status.intervalDue": "%@自动生成到点",
    "auto.status.intervalNext": "%@自动生成下次 %@",
    "auto.status.dailyNext": "每日清晨自动生成下次 %@",
    "auto.status.dailyReady": "今日自动生成准备开始",

    "auto.freq.off": "关闭",
    "auto.freq.daily": "每日清晨",
    "auto.freq.hour4": "每 4 小时",
    "auto.freq.hour1": "每小时",
    "auto.label.daily": "每日清晨",
    "auto.label.hour4": "每 4 小时",
    "auto.label.hour1": "每小时",

    // styles
    "style.极简": "极简",
    "style.水彩": "水彩",
    "style.摄影": "摄影",
    "style.赛博朋克": "赛博朋克",
    "style.胶片": "胶片",
    "style.油画": "油画",

    // accents
    "accent.auto": "随心情",
    "accent.ink": "墨",
    "accent.sand": "沙",
    "accent.sea": "海",
    "accent.moss": "苔",
    "accent.ember": "炭火",

    // moods
    "mood.兴奋": "兴奋",
    "mood.焦躁": "焦躁",
    "mood.愉悦": "愉悦",
    "mood.专注": "专注",
    "mood.平静": "平静",
    "mood.松弛": "松弛",
    "mood.疲惫": "疲惫",
    "mood.中性": "中性",

    // errors
    "error.needLogin": "请先连接神马图鉴再生图",
    "error.saveImageFailed": "保存图像失败",
    "error.badResponse": "服务返回异常: %@",
    "error.decoding": "解析失败: %@",
    "error.noImage": "未返回图像",
    "error.http": "HTTP %d: %@",
    "error.network": "网络错误: %@",
    "error.taskFailed": "生成失败: %@",
    "error.taskTimeout": "生成超时",
    "error.urlInvalid": "URL 无效",
    "error.taskUrlInvalid": "任务 URL 无效",
    "error.nonHttpResponse": "非 HTTP 响应",
    "error.unknown": "未知原因",

    // generation labels
    "gen.collecting": "采集 心情·日期·黄历…",
    "gen.composing": "组装 prompt…",
    "gen.calling": "调用神马图鉴 · %@…",
    "gen.downloading": "下载图像…",
    "gen.applying": "应用到显示器…",
    "gen.done": "完成",
    "gen.progress": "生成中…(%d%%)",

    // credit history
    "credits.title": "积分明细",
    "credits.empty": "还没有积分变动记录",
    "credits.loadMore": "加载更多",
    "credits.type.GENERATION_CHARGE": "AI 生图扣分",
    "credits.type.GENERATION_REFUND": "生图退分",
    "credits.type.CHECKIN": "每日签到",
    "credits.type.ADMIN_ADJUSTMENT": "管理员调整",
    "credits.type.unknown": "其他",
]
