import Foundation
@testable import ZenWallpaperKit

@MainActor
enum ShenmaEndpointTests {

    static func canonicalProductionUrlMatchesProduction() {
        expectEqual(ShenmaEndpoint.match("https://www.uyoqu.com"), .production)
    }

    static func legacyApexUrlMatchesProduction() {
        // Old defaults shipped with uyoqu.com — still treated as production
        // so users who never customized their URL aren't bumped to "Custom".
        expectEqual(ShenmaEndpoint.match("https://uyoqu.com"), .production)
        expectEqual(ShenmaEndpoint.match("https://www.uyoqu.com"), .production)
    }

    static func trailingSlashIsIgnored() {
        expectEqual(ShenmaEndpoint.match("https://www.uyoqu.com/"), .production)
        expectEqual(ShenmaEndpoint.match("http://127.0.0.1:5173/"), .localhost)
    }

    static func leadingAndTrailingWhitespaceIsIgnored() {
        expectEqual(ShenmaEndpoint.match("  https://www.uyoqu.com  "), .production)
    }

    static func bothLocalhostHostsMatchLocalhostPreset() {
        expectEqual(ShenmaEndpoint.match("http://localhost:5173"), .localhost)
        expectEqual(ShenmaEndpoint.match("http://127.0.0.1:5173"), .localhost)
    }

    static func unknownUrlsFallBackToCustom() {
        expectEqual(ShenmaEndpoint.match("https://staging.uyoqu.com"), .custom)
        expectEqual(ShenmaEndpoint.match("http://192.168.1.10:5173"), .custom)
        expectEqual(ShenmaEndpoint.match(""), .custom)
    }

    static func legacyDefaultUrlGetsMigratedToNewHost() {
        let settings = AppSettings()
        settings.shenmaBaseUrl = "https://uyoqu.com"
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        expectEqual(settings.shenmaBaseUrl, "https://www.uyoqu.com")

        settings.shenmaBaseUrl = "https://www.uyoqu.com"
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        expectEqual(settings.shenmaBaseUrl, "https://www.uyoqu.com")
    }

    static func customUrlSurvivesMigration() {
        let settings = AppSettings()
        settings.shenmaBaseUrl = "https://staging.uyoqu.com"
        settings.migrateLegacyShenmaBaseUrlIfNeeded()
        expectEqual(settings.shenmaBaseUrl, "https://staging.uyoqu.com",
                    "migration should only touch the legacy default, not user-set URLs")
    }
}
