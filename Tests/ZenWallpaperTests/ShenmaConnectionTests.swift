import Foundation
@testable import ZenWallpaperKit

@MainActor
enum ShenmaConnectionTests {

    static func everyErrorCaseHasNonEmptyDescription() {
        let cases: [ShenmaConnectionError] = [
            .badUrl,
            .http(401, "unauthorized"),
            .api("server says no"),
            .decoding("malformed"),
            .denied,
            .expired,
            .timeout,
            .missingToken
        ]
        for error in cases {
            let message = error.errorDescription
            expectNotNil(message, "\(error) should have a description")
            expectTrue(!(message?.isEmpty ?? true), "\(error) description must not be empty")
        }
    }

    static func httpErrorIncludesStatusCodeInDescription() {
        let error = ShenmaConnectionError.http(429, "too many")
        expectTrue(error.errorDescription?.contains("429") == true,
                   "HTTP error description should surface the status code, got \(error.errorDescription ?? "nil")")
    }

    static func shenmaAccountRoundTripsThroughCodable() throws {
        let user = ShenmaUser(id: "42", username: "yoqu", nickname: "Yoqu", avatarUrl: nil)
        let original = ShenmaAccount(user: user, connectedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ShenmaAccount.self, from: encoded)
        expectEqual(decoded, original)
    }

    static func shenmaUserDecodesNullAvatarAsNil() throws {
        let json = #"{"id":"1","username":"u","nickname":"n","avatarUrl":null}"#.data(using: .utf8)!
        let user = try JSONDecoder().decode(ShenmaUser.self, from: json)
        expectTrue(user.avatarUrl == nil, "expected avatarUrl to decode as nil")
    }
}
