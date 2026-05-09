import Foundation
@testable import ZenWallpaperKit

@MainActor
enum ShenmaEndpointTests {

    static func canonicalProductionUrlMatchesProduction() {
        expectEqual(ShenmaEndpoint.match("https://www.qushenma.com"), .production)
    }

    static func legacyApexUrlMatchesProduction() {
        // Old default shipped without the `www.` prefix — still treated as production
        // so users who never customized their URL aren't bumped to "Custom".
        expectEqual(ShenmaEndpoint.match("https://qushenma.com"), .production)
    }

    static func trailingSlashIsIgnored() {
        expectEqual(ShenmaEndpoint.match("https://www.qushenma.com/"), .production)
        expectEqual(ShenmaEndpoint.match("http://127.0.0.1:5173/"), .localhost)
    }

    static func leadingAndTrailingWhitespaceIsIgnored() {
        expectEqual(ShenmaEndpoint.match("  https://www.qushenma.com  "), .production)
    }

    static func bothLocalhostHostsMatchLocalhostPreset() {
        expectEqual(ShenmaEndpoint.match("http://localhost:5173"), .localhost)
        expectEqual(ShenmaEndpoint.match("http://127.0.0.1:5173"), .localhost)
    }

    static func unknownUrlsFallBackToCustom() {
        expectEqual(ShenmaEndpoint.match("https://staging.qushenma.com"), .custom)
        expectEqual(ShenmaEndpoint.match("http://192.168.1.10:5173"), .custom)
        expectEqual(ShenmaEndpoint.match(""), .custom)
    }

    static func legacyDefaultUrlGetsMigratedToWwwHost() {
        let settings = AppSettings()
        settings.shenmaBaseUrl = "https://qushenma.com"
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        expectEqual(settings.shenmaBaseUrl, "https://www.qushenma.com")
    }

    static func customUrlSurvivesMigration() {
        let settings = AppSettings()
        settings.shenmaBaseUrl = "https://staging.qushenma.com"
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        expectEqual(settings.shenmaBaseUrl, "https://staging.qushenma.com",
                    "migration should only touch the legacy default, not user-set URLs")
    }
}
