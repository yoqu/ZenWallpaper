import Foundation
@testable import ZenWallpaperKit

// `main.swift` is a top-level script. Test bodies are MainActor-isolated (because
// LocalizationManager and WallpaperManager live on the main actor) — top-level
// `await` is fine in Swift 5.5+ and avoids the semaphore-vs-Task deadlock we hit
// when trying to bridge async work from a synchronous `exit(...)` driver.
@MainActor
func runAll() async -> Int {
    TestReporter.reset()

    print("ShenmaConnection")
    _ = TestReporter.run("every error case has a non-empty errorDescription") {
        ShenmaConnectionTests.everyErrorCaseHasNonEmptyDescription()
    }
    _ = TestReporter.run("HTTP error includes status code in description") {
        ShenmaConnectionTests.httpErrorIncludesStatusCodeInDescription()
    }
    _ = TestReporter.run("ShenmaAccount round-trips through Codable") {
        try ShenmaConnectionTests.shenmaAccountRoundTripsThroughCodable()
    }
    _ = TestReporter.run("ShenmaUser decodes a null avatarUrl as nil") {
        try ShenmaConnectionTests.shenmaUserDecodesNullAvatarAsNil()
    }

    print("\nShenmaEndpoint")
    _ = TestReporter.run("canonical https://www.qushenma.com matches production preset") {
        ShenmaEndpointTests.canonicalProductionUrlMatchesProduction()
    }
    _ = TestReporter.run("legacy https://qushenma.com (no www) still matches production") {
        ShenmaEndpointTests.legacyApexUrlMatchesProduction()
    }
    _ = TestReporter.run("trailing slash is ignored when matching presets") {
        ShenmaEndpointTests.trailingSlashIsIgnored()
    }
    _ = TestReporter.run("leading/trailing whitespace is ignored when matching presets") {
        ShenmaEndpointTests.leadingAndTrailingWhitespaceIsIgnored()
    }
    _ = TestReporter.run("both localhost and 127.0.0.1 map to the localhost preset") {
        ShenmaEndpointTests.bothLocalhostHostsMatchLocalhostPreset()
    }
    _ = TestReporter.run("unknown URLs fall back to custom") {
        ShenmaEndpointTests.unknownUrlsFallBackToCustom()
    }
    _ = TestReporter.run("legacy default URL is migrated to the www host") {
        ShenmaEndpointTests.legacyDefaultUrlGetsMigratedToWwwHost()
    }
    _ = TestReporter.run("user-customized URL survives migration") {
        ShenmaEndpointTests.customUrlSurvivesMigration()
    }

    print("\nShenmaConnectionManager.handleConnectCallback")
    _ = TestReporter.run("user-code normalization matches the server's rules") {
        ShenmaCallbackTests.userCodeNormalizationMatchesServerRules()
    }
    _ = await TestReporter.runAsync("callback outside of an active connect flow is a silent no-op") {
        await ShenmaCallbackTests.callbackOutsideOfConnectFlowIsSilentNoOp()
    }
    _ = await TestReporter.runAsync("callback with wrong scheme / host / missing code is rejected") {
        await ShenmaCallbackTests.callbackWithWrongSchemeOrHostIsRejected()
    }
    _ = TestReporter.run("notification name is the documented stable string") {
        ShenmaCallbackTests.notificationNameIsTheStableContract()
    }

    print("")
    return TestReporter.summarize()
}

let exitCode = await runAll()
exit(Int32(exitCode))
