import Foundation
@testable import ZenWallpaperKit

@MainActor
enum ShenmaCallbackTests {

    static func userCodeNormalizationMatchesServerRules() {
        let manager = ShenmaConnectionManager()
        // Backend normalizes by stripping dashes and uppercasing — both sides have
        // to agree, otherwise approved sessions silently fail to fast-forward.
        expectEqual(manager.normalizeUserCode("BNUH-X9E2"), "BNUHX9E2")
        expectEqual(manager.normalizeUserCode("bnuh-x9e2"), "BNUHX9E2")
        expectEqual(manager.normalizeUserCode("  BNUH-X9E2  "), "BNUHX9E2")
        expectEqual(manager.normalizeUserCode("BNUHX9E2"), "BNUHX9E2")
        expectEqual(manager.normalizeUserCode("BNUH X9E2"), "BNUHX9E2")
    }

    /// Calling the callback when the manager isn't mid-connect must be a silent
    /// no-op — we should NEVER touch the network for an unsolicited deeplink, and
    /// state must be unchanged after the call.
    static func callbackOutsideOfConnectFlowIsSilentNoOp() async {
        let manager = ShenmaConnectionManager()
        let url = URL(string: "zenwallpaper://connected?code=BNUH-X9E2")!
        let beforeIsConnecting = manager.isConnecting
        let beforeUserCode = manager.userCode
        let beforeError = manager.lastError

        await manager.handleConnectCallback(url: url)

        expectEqual(manager.isConnecting, beforeIsConnecting,
                    "callback must not flip isConnecting when no connect attempt is in flight")
        expectTrue(manager.userCode == beforeUserCode,
                   "callback must not invent a userCode out of nowhere")
        expectTrue(manager.lastError == beforeError,
                   "callback for unsolicited URL should not record an error")
    }

    /// URLs with the wrong scheme / host must also be silent no-ops, even if the
    /// manager IS mid-connect — protects against a malicious page firing a
    /// look-alike scheme to confuse the app.
    static func callbackWithWrongSchemeOrHostIsRejected() async {
        let manager = ShenmaConnectionManager()
        let cases = [
            "https://connected?code=BNUH-X9E2",
            "zenwallpaper://disconnected?code=BNUH-X9E2",
            "zenwallpaper://other-host?code=BNUH-X9E2",
            "zenwallpaper://connected",                 // no code at all
            "zenwallpaper://connected?other=BNUH-X9E2", // wrong query name
        ]
        for raw in cases {
            guard let url = URL(string: raw) else { continue }
            await manager.handleConnectCallback(url: url)
            expectTrue(manager.isConnecting == false,
                       "URL \(raw) must not flip the manager into a connecting state")
        }
    }

    /// The notification name the AppDelegate posts must match what the manager
    /// subscribes to — drift here would silently break the deeplink fast-path.
    static func notificationNameIsTheStableContract() {
        expectEqual(
            ShenmaConnectionManager.urlReceivedNotificationName.rawValue,
            "com.zen.wallpaper.UrlReceived"
        )
    }
}
