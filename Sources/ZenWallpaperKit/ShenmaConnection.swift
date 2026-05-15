import AppKit
import Foundation
import os.log
import Security

private let shenmaLog = Logger(subsystem: "com.zen.wallpaper", category: "Shenma")

struct ShenmaUser: Codable, Equatable {
    let id: String
    let username: String
    let nickname: String
    let avatarUrl: String?
}

struct ShenmaAccount: Codable, Equatable {
    let user: ShenmaUser
    let connectedAt: Date
}

enum ShenmaConnectionError: Error, LocalizedError {
    case badUrl
    case http(Int, String)
    case api(String)
    case decoding(String)
    case denied
    case expired
    case timeout
    case missingToken

    var errorDescription: String? {
        switch self {
        case .badUrl: return "qushenma URL is invalid"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .api(let message): return message
        case .decoding(let message): return "Unable to read qushenma response: \(message)"
        case .denied: return "Connection request was denied"
        case .expired: return "Connection code expired"
        case .timeout: return "Connection timed out"
        case .missingToken: return "Connection response did not include a token"
        }
    }
}

actor ShenmaAuthClient {
    private struct APIEnvelope<T: Decodable>: Decodable {
        let success: Bool?
        let code: String?
        let message: String?
        let data: T
    }

    struct DeviceStartResponse: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String
        let expiresIn: Int
        let interval: Int
    }

    struct DevicePollResponse: Decodable {
        let status: String
        let token: String?
        let user: ShenmaUser?
        let interval: Int
        let expiresIn: Int
    }

    struct ConnectionResponse: Decodable {
        let connected: Bool
        let user: ShenmaUser
    }

    /// Mirrors `CreditDtos.CreditSummaryDto`. We only consume `balance`; the
    /// other fields are ignored but defined here so a strict decoder won't trip.
    struct CreditSummaryResponse: Decodable {
        let balance: Int
    }

    struct CreditTransactionsResponse: Decodable {
        let items: [CreditTransaction]
        let page: Int
        let size: Int
        let total: Int
        let hasMore: Bool
    }

    /// Mirrors `WorkDtos.AssetDto` — only the fields the desktop reads.
    struct WorkAssetDto: Decodable {
        let url: String?
        let mimeType: String?
        let aspectRatio: String?
        let width: Int?
        let height: Int?
    }

    struct WorkTagDto: Decodable {
        let slug: String
        let name: String
    }

    /// Mirrors `WorkDtos.WorkSummaryDto`. Most fields are decoded as optional
    /// because moderation state, publish state, or assets can be missing in
    /// edge cases (e.g. half-saved drafts) — we don't want strict decoding to
    /// crash the popover if the server returns a row in an unusual shape.
    struct WorkSummaryDto: Decodable {
        let id: String
        let title: String?
        let status: String?
        let moderationStatus: String?
        let publishedAt: Date?
        let coverAsset: WorkAssetDto?
        let tags: [WorkTagDto]?
    }

    struct WorksPageResponse: Decodable {
        let items: [WorkSummaryDto]
        let page: Int
        let size: Int
        let total: Int
        let hasMore: Bool
    }

    struct CollectionSummaryDto: Decodable {
        let id: String
        let title: String
        let itemCount: Int
        let isDefault: Bool
    }

    struct CollectionsPageResponse: Decodable {
        let items: [CollectionSummaryDto]
        let page: Int
        let size: Int
        let total: Int
        let hasMore: Bool
    }

    struct CollectionDetailDto: Decodable {
        let id: String
        let title: String
        let itemCount: Int
        let isDefault: Bool
        let works: WorksPageResponse
    }

    func myWorks(
        baseUrl: String,
        token: String,
        page: Int,
        size: Int,
        aspectRatio: String?,
        tagSlug: String?
    ) async throws -> WorksPageResponse {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "\(trimmed)/api/studio/works") else {
            throw ShenmaConnectionError.badUrl
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        if let aspectRatio, !aspectRatio.isEmpty {
            queryItems.append(URLQueryItem(name: "aspectRatio", value: aspectRatio))
        }
        if let tagSlug, !tagSlug.isEmpty {
            queryItems.append(URLQueryItem(name: "tagSlug", value: tagSlug))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw ShenmaConnectionError.badUrl }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: WorksPageResponse.self)
    }

    func collections(
        baseUrl: String,
        token: String,
        userId: String,
        page: Int,
        size: Int
    ) async throws -> CollectionsPageResponse {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "\(trimmed)/api/users/\(userId)/collections") else {
            throw ShenmaConnectionError.badUrl
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "includeDefault", value: "true")
        ]
        guard let url = components.url else { throw ShenmaConnectionError.badUrl }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: CollectionsPageResponse.self)
    }

    func collectionWorks(
        baseUrl: String,
        token: String,
        collectionId: String,
        page: Int,
        size: Int
    ) async throws -> CollectionDetailDto {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "\(trimmed)/api/collections/\(collectionId)") else {
            throw ShenmaConnectionError.badUrl
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        guard let url = components.url else { throw ShenmaConnectionError.badUrl }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: CollectionDetailDto.self)
    }

    func startDeviceAuth(baseUrl: String, deviceName: String, appVersion: String?) async throws -> DeviceStartResponse {
        var req = try request(baseUrl: baseUrl, path: "/api/desktop/auth/device/start")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "deviceName": deviceName,
            "appVersion": appVersion ?? ""
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return try await send(req, as: DeviceStartResponse.self)
    }

    func poll(baseUrl: String, deviceCode: String) async throws -> DevicePollResponse {
        var req = try request(baseUrl: baseUrl, path: "/api/desktop/auth/device/poll")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["deviceCode": deviceCode], options: [])
        return try await send(req, as: DevicePollResponse.self)
    }

    func me(baseUrl: String, token: String) async throws -> ConnectionResponse {
        var req = try request(baseUrl: baseUrl, path: "/api/desktop/connection/me")
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: ConnectionResponse.self)
    }

    func credits(baseUrl: String, token: String) async throws -> CreditSummaryResponse {
        var req = try request(baseUrl: baseUrl, path: "/api/credits/me")
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: CreditSummaryResponse.self)
    }

    func transactions(baseUrl: String, token: String, page: Int, size: Int) async throws -> CreditTransactionsResponse {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "\(trimmed)/api/credits/transactions/me") else {
            throw ShenmaConnectionError.badUrl
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(size))
        ]
        guard let url = components.url else { throw ShenmaConnectionError.badUrl }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(req, as: CreditTransactionsResponse.self)
    }

    private func request(baseUrl: String, path: String) throws -> URLRequest {
        let trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty, let url = URL(string: trimmed + path) else {
            throw ShenmaConnectionError.badUrl
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    func logout(baseUrl: String, token: String) async {
        // Best-effort: ignore errors. The local Keychain entry is the source of truth
        // and the server-side token will eventually expire on its own anyway.
        guard var req = try? request(baseUrl: baseUrl, path: "/api/auth/logout") else { return }
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    private func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ShenmaConnectionError.http(-1, "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ShenmaConnectionError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            let decoder = JSONDecoder()
            // Backend serializes OffsetDateTime as ISO-8601 with offset (e.g. "2026-05-09T12:34:56+00:00").
            decoder.dateDecodingStrategy = .custom { d in
                let container = try d.singleValueContainer()
                let raw = try container.decode(String.self)
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: raw) { return date }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: raw) { return date }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date: \(raw)")
            }
            let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
            if envelope.success == false {
                throw ShenmaConnectionError.api(envelope.message ?? envelope.code ?? "qushenma request failed")
            }
            return envelope.data
        } catch let error as ShenmaConnectionError {
            throw error
        } catch {
            throw ShenmaConnectionError.decoding(error.localizedDescription)
        }
    }
}

@MainActor
final class ShenmaConnectionManager: ObservableObject {
    @Published private(set) var account: ShenmaAccount?
    @Published private(set) var isConnecting = false
    @Published private(set) var userCode: String?
    @Published private(set) var creditBalance: Int?
    @Published var lastError: String?
    /// Cached list of the logged-in user's recent works fetched from
    /// `/api/studio/works`. Includes pending / approved / rejected — the
    /// desktop UI annotates each tile with its moderation badge.
    @Published private(set) var cloudWorks: [RemoteWork] = []
    @Published private(set) var isLoadingCloudWorks = false
    @Published var cloudWorksError: String?

    @Published private(set) var collections: [RemoteCollection] = []
    @Published private(set) var isLoadingCollections = false
    /// Per-collection works cache, keyed by collection ID.
    @Published private(set) var collectionWorks: [String: [RemoteWork]] = [:]
    @Published private(set) var isLoadingCollectionWorks = false
    @Published var collectionsError: String?

    private let client = ShenmaAuthClient()
    private var pollTask: Task<Void, Never>?
    private let accountKey = "shenmaAccount"
    /// Device-flow context for the in-flight connect attempt. Set in `connect(...)`,
    /// cleared on any terminal state (approved / denied / expired / cancelled). Used
    /// by `handleConnectCallback(url:)` to validate the deeplink belongs to this
    /// session and to fire a one-shot poll without waiting for the periodic tick.
    private var pendingDeviceCode: String?
    private var pendingBaseUrl: String?

    /// Notification name the AppDelegate posts when a `zenwallpaper://...`
    /// deeplink arrives. Decoupled from the AppDelegate type so the kit doesn't
    /// have to depend on AppKit lifecycle classes.
    public static let urlReceivedNotificationName = Notification.Name("com.zen.wallpaper.UrlReceived")

    init() {
        account = loadAccount()
        // Subscribe to deeplink notifications. Holding the observer in a property
        // would let us cancel on deinit; in practice `ShenmaConnectionManager` is
        // a singleton-lifetime `@StateObject` so leaking the observer for the
        // process lifetime is fine.
        NotificationCenter.default.addObserver(
            forName: ShenmaConnectionManager.urlReceivedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.userInfo?["url"] as? URL else { return }
            Task { @MainActor [weak self] in
                await self?.handleConnectCallback(url: url)
            }
        }
    }

    var isConnected: Bool {
        account != nil && ShenmaKeychain.loadToken() != nil
    }

    func token() -> String? {
        ShenmaKeychain.loadToken()
    }

    /// Validate the cached token against the server. Only clears local state on a
    /// hard 401 — transient network errors leave the cached account in place so
    /// the user isn't bumped offline by a wifi blip.
    func refresh(baseUrl: String) async {
        guard let token = ShenmaKeychain.loadToken() else {
            if account != nil {
                account = nil
                saveAccount(nil)
            }
            creditBalance = nil
            return
        }
        do {
            let response = try await client.me(baseUrl: baseUrl, token: token)
            let next = ShenmaAccount(user: response.user, connectedAt: account?.connectedAt ?? Date())
            account = next
            saveAccount(next)
            // Piggyback a credit refresh on the same wake-up so the popover header
            // is current the moment it appears.
            await fetchCredits(baseUrl: baseUrl)
        } catch ShenmaConnectionError.http(401, _) {
            // Token genuinely revoked / expired. Clear local state.
            ShenmaKeychain.deleteToken()
            account = nil
            creditBalance = nil
            saveAccount(nil)
        } catch {
            // Transient (offline, 5xx, DNS, ...). Keep cached account; surface the error
            // only if the user has no cached account to fall back on.
            if account == nil {
                lastError = error.localizedDescription
            }
        }
    }

    /// Fetch the current credit balance for the logged-in user. Silent no-op if not
    /// connected. Sets `creditBalance` on success; leaves it untouched on transient
    /// failure (so the header doesn't blink between a real value and "—").
    func fetchCredits(baseUrl: String) async {
        guard let token = ShenmaKeychain.loadToken() else {
            creditBalance = nil
            return
        }
        do {
            let summary = try await client.credits(baseUrl: baseUrl, token: token)
            creditBalance = summary.balance
        } catch ShenmaConnectionError.http(401, _) {
            ShenmaKeychain.deleteToken()
            account = nil
            creditBalance = nil
            saveAccount(nil)
        } catch {
            // Quiet failure — keep showing the previous value.
        }
    }

    /// Update the cached balance from a value the server already gave us — used
    /// after a generation completes, since `/api/ai/generations` returns the new
    /// balance in the same response.
    func setCreditBalance(_ value: Int) {
        creditBalance = value
    }

    func fetchTransactions(baseUrl: String, page: Int, size: Int) async throws -> ShenmaAuthClient.CreditTransactionsResponse {
        guard let token = ShenmaKeychain.loadToken() else {
            throw ShenmaConnectionError.missingToken
        }
        return try await client.transactions(baseUrl: baseUrl, token: token, page: page, size: size)
    }

    /// Refresh the cloud library — the user's recent works on qushenma. The
    /// `aspectRatio` filter narrows results to wallpapers that fit the current
    /// screen; passing nil disables the ratio filter. `tagSlug` is reserved
    /// for future per-tag filtering and currently always nil.
    ///
    /// On 401 the cached account is wiped (the token is dead). Other errors
    /// surface in `cloudWorksError` and leave the previous list intact so the
    /// UI doesn't blink to empty during a transient hiccup.
    func fetchCloudWorks(baseUrl: String, aspectRatio: String?, tagSlug: String? = nil) async {
        guard let token = ShenmaKeychain.loadToken() else {
            cloudWorks = []
            return
        }
        isLoadingCloudWorks = true
        defer { isLoadingCloudWorks = false }
        do {
            let response = try await client.myWorks(
                baseUrl: baseUrl,
                token: token,
                page: 1,
                size: 24,
                aspectRatio: aspectRatio,
                tagSlug: tagSlug
            )
            cloudWorks = response.items.compactMap { dto in
                guard let url = dto.coverAsset?.url, !url.isEmpty else { return nil }
                return RemoteWork(
                    id: dto.id,
                    title: dto.title ?? "",
                    assetUrl: url,
                    mimeType: dto.coverAsset?.mimeType ?? "image/png",
                    aspectRatio: dto.coverAsset?.aspectRatio,
                    moderationStatus: (dto.moderationStatus ?? "pending").lowercased(),
                    publishedAt: dto.publishedAt,
                    tagNames: (dto.tags ?? []).map { $0.name }
                )
            }
            cloudWorksError = nil
        } catch ShenmaConnectionError.http(401, _) {
            ShenmaKeychain.deleteToken()
            account = nil
            creditBalance = nil
            cloudWorks = []
            saveAccount(nil)
        } catch {
            cloudWorksError = error.localizedDescription
        }
    }

    /// Fetch the user's collection list from qushenma.
    func fetchCollections(baseUrl: String) async {
        guard let token = ShenmaKeychain.loadToken(),
              let userId = account?.user.id else {
            collections = []
            return
        }
        isLoadingCollections = true
        defer { isLoadingCollections = false }
        do {
            let response = try await client.collections(
                baseUrl: baseUrl,
                token: token,
                userId: userId,
                page: 1,
                size: 50
            )
            collections = response.items.map {
                RemoteCollection(
                    id: $0.id,
                    title: $0.title,
                    itemCount: $0.itemCount,
                    isDefault: $0.isDefault
                )
            }
            collectionsError = nil
        } catch ShenmaConnectionError.http(401, _) {
            ShenmaKeychain.deleteToken()
            account = nil
            creditBalance = nil
            collections = []
            collectionWorks = [:]
            saveAccount(nil)
        } catch {
            collectionsError = error.localizedDescription
        }
    }

    /// Fetch works inside a specific collection. Client-side aspect ratio
    /// filtering is applied when `aspectRatio` is non-nil.
    func fetchCollectionWorks(baseUrl: String, collectionId: String, aspectRatio: String?) async {
        guard let token = ShenmaKeychain.loadToken() else {
            collectionWorks[collectionId] = []
            return
        }
        isLoadingCollectionWorks = true
        defer { isLoadingCollectionWorks = false }
        do {
            let response = try await client.collectionWorks(
                baseUrl: baseUrl,
                token: token,
                collectionId: collectionId,
                page: 1,
                size: 50
            )
            collectionWorks[collectionId] = response.works.items.compactMap { dto in
                guard let url = dto.coverAsset?.url, !url.isEmpty else { return nil }
                if let targetSlug = aspectRatio,
                   let w = dto.coverAsset?.width, let h = dto.coverAsset?.height,
                   w > 0 && h > 0 {
                    let ratio = Double(w) / Double(h)
                    let slug = DisplayIdentity.closestRatioSlug(for: ratio)
                    if slug != targetSlug { return nil }
                }
                return RemoteWork(
                    id: dto.id,
                    title: dto.title ?? "",
                    assetUrl: url,
                    mimeType: dto.coverAsset?.mimeType ?? "image/png",
                    aspectRatio: dto.coverAsset?.aspectRatio,
                    moderationStatus: (dto.moderationStatus ?? "approved").lowercased(),
                    publishedAt: dto.publishedAt,
                    tagNames: (dto.tags ?? []).map { $0.name }
                )
            }
        } catch ShenmaConnectionError.http(401, _) {
            ShenmaKeychain.deleteToken()
            account = nil
            creditBalance = nil
            collections = []
            collectionWorks = [:]
            saveAccount(nil)
        } catch {
            collectionsError = error.localizedDescription
        }
    }

    func connect(baseUrl: String) async {
        guard !isConnecting else {
            shenmaLog.notice("[Shenma] connect: already connecting, ignoring")
            return
        }
        shenmaLog.notice("[Shenma] connect: starting device auth flow, baseUrl=\(baseUrl)")
        isConnecting = true
        lastError = nil
        userCode = nil

        do {
            let start = try await client.startDeviceAuth(
                baseUrl: baseUrl,
                deviceName: Host.current().localizedName ?? "Mac",
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            )
            userCode = start.userCode
            shenmaLog.notice("[Shenma] connect: got userCode=\(start.userCode), expiresIn=\(start.expiresIn), interval=\(start.interval)")
            // Stash device-flow context so an incoming `zenwallpaper://connected?code=...`
            // deeplink can verify + accelerate this same session.
            pendingDeviceCode = start.deviceCode
            pendingBaseUrl = baseUrl
            if let url = URL(string: start.verificationUriComplete) {
                shenmaLog.notice("[Shenma] connect: opening browser to \(url)")
                NSWorkspace.shared.open(url)
            }
            startPolling(baseUrl: baseUrl, deviceCode: start.deviceCode, interval: start.interval, expiresIn: start.expiresIn)
        } catch {
            shenmaLog.notice("[Shenma] connect: startDeviceAuth failed: \(error)")
            isConnecting = false
            lastError = error.localizedDescription
        }
    }

    /// Handle a `zenwallpaper://connected?code=BNUH-X9E2` deeplink fired by the
    /// browser after the user approves the connection. Validates the URL belongs
    /// to the in-flight session, then runs a one-shot poll so we pick up the token
    /// immediately instead of waiting for the next 3-second tick.
    ///
    /// Safe to call when no connect attempt is in flight — it just returns silently.
    func handleConnectCallback(url: URL) async {
        shenmaLog.notice("[Shenma] handleConnectCallback: received URL \(url)")
        guard isConnecting else {
            shenmaLog.notice("[Shenma] handleConnectCallback: not connecting, ignoring")
            return
        }
        guard url.scheme?.lowercased() == "zenwallpaper" else {
            shenmaLog.notice("[Shenma] handleConnectCallback: wrong scheme \(url.scheme ?? "nil")")
            return
        }
        // Accept both `url.host` (authority component) and the first path component
        // as "connected" — on some macOS versions / URL parsers the host can be nil
        // for custom-scheme URLs while the path holds the value.
        let hostValue = url.host?.lowercased()
            ?? url.pathComponents.first(where: { $0 != "/" })?.lowercased()
        guard hostValue == "connected" else {
            shenmaLog.notice("[Shenma] handleConnectCallback: unexpected host/path '\(hostValue ?? "nil")' (url.host=\(url.host ?? "nil"), path=\(url.path))")
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlCode = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let expected = userCode,
              normalizeUserCode(urlCode) == normalizeUserCode(expected),
              let deviceCode = pendingDeviceCode,
              let baseUrl = pendingBaseUrl
        else {
            let dbgUrlCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value ?? "nil"
            let dbgExpected = userCode ?? "nil"
            let dbgHasDevice = pendingDeviceCode != nil
            let dbgHasBase = pendingBaseUrl != nil
            shenmaLog.notice("[Shenma] handleConnectCallback: code mismatch or missing context (urlCode=\(dbgUrlCode), expected=\(dbgExpected), hasDeviceCode=\(dbgHasDevice), hasBaseUrl=\(dbgHasBase))")
            return
        }

        shenmaLog.notice("[Shenma] handleConnectCallback: codes match, firing one-shot poll")
        do {
            let response = try await client.poll(baseUrl: baseUrl, deviceCode: deviceCode)
            shenmaLog.notice("[Shenma] handleConnectCallback: poll returned status=\(response.status), hasToken=\(response.token != nil), hasUser=\(response.user != nil)")
            await applyPollResponse(response, baseUrl: baseUrl)
        } catch {
            shenmaLog.notice("[Shenma] handleConnectCallback: poll error \(error)")
            // Swallow — the periodic poll loop is still running and will retry on
            // its own schedule. The deeplink is best-effort UX, not a hard path.
        }
    }

    /// Common terminal-state handler shared by the periodic poll loop and the
    /// deeplink callback. Idempotent: calling it twice with the same approved
    /// response is a no-op (Keychain.save replaces the token; account stays the same).
    private func applyPollResponse(_ response: ShenmaAuthClient.DevicePollResponse, baseUrl: String) async {
        shenmaLog.notice("[Shenma] applyPollResponse: status=\(response.status), hasToken=\(response.token != nil), hasUser=\(response.user != nil)")
        switch response.status {
        case "approved":
            guard let token = response.token, let user = response.user else {
                shenmaLog.notice("[Shenma] applyPollResponse: approved but token or user is nil!")
                return
            }
            ShenmaKeychain.saveToken(token)
            // Verify the token actually persisted — if the Keychain rejected it
            // we need to know immediately rather than showing "not connected" later.
            let verified = ShenmaKeychain.loadToken() != nil
            shenmaLog.notice("[Shenma] applyPollResponse: token saved, verified=\(verified), user=\(user.username)")
            let next = ShenmaAccount(user: user, connectedAt: Date())
            account = next
            saveAccount(next)
            isConnecting = false
            userCode = nil
            pendingDeviceCode = nil
            pendingBaseUrl = nil
            pollTask?.cancel()
            pollTask = nil
            // Now that we have a token, prime the credit balance so the popover
            // header doesn't show "—" right after a fresh login.
            await fetchCredits(baseUrl: baseUrl)
        case "access_denied":
            lastError = ShenmaConnectionError.denied.localizedDescription
            isConnecting = false
            userCode = nil
            pendingDeviceCode = nil
            pendingBaseUrl = nil
            pollTask?.cancel()
            pollTask = nil
        case "expired_token":
            lastError = ShenmaConnectionError.expired.localizedDescription
            isConnecting = false
            userCode = nil
            pendingDeviceCode = nil
            pendingBaseUrl = nil
            pollTask?.cancel()
            pollTask = nil
        default:
            // "authorization_pending" — keep waiting.
            break
        }
    }

    /// Internal (not private) so unit tests can pin the comparison rules. Both the
    /// server's user-code normalization and this client's deeplink validation must
    /// agree, otherwise approved sessions can fail to fast-forward via the URL
    /// callback.
    func normalizeUserCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    func disconnect(baseUrl: String) {
        pollTask?.cancel()
        pollTask = nil
        let token = ShenmaKeychain.loadToken()
        ShenmaKeychain.deleteToken()
        account = nil
        userCode = nil
        creditBalance = nil
        collections = []
        collectionWorks = [:]
        isConnecting = false
        pendingDeviceCode = nil
        pendingBaseUrl = nil
        saveAccount(nil)
        // Best-effort server-side revoke. Fire and forget — local state is already cleared.
        if let token, !baseUrl.isEmpty {
            Task.detached { [client] in
                await client.logout(baseUrl: baseUrl, token: token)
            }
        }
    }

    /// Force a 401-style cleanup when callers (e.g. the generation flow) discover
    /// the token is dead. Same effect as `disconnect` minus the server-side revoke,
    /// since 401 already proved the server doesn't recognize the token.
    func clearAfterUnauthorized() {
        pollTask?.cancel()
        pollTask = nil
        ShenmaKeychain.deleteToken()
        account = nil
        creditBalance = nil
        collections = []
        collectionWorks = [:]
        userCode = nil
        isConnecting = false
        pendingDeviceCode = nil
        pendingBaseUrl = nil
        saveAccount(nil)
    }

    private func startPolling(baseUrl: String, deviceCode: String, interval: Int, expiresIn: Int) {
        pollTask?.cancel()
        shenmaLog.notice("[Shenma] startPolling: interval=\(interval)s, expiresIn=\(expiresIn)s, baseUrl=\(baseUrl)")
        pollTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(TimeInterval(max(30, expiresIn)))
            let sleepSeconds = max(2, interval)
            // Tolerate up to N consecutive transient failures before giving up — wifi
            // hiccups during a 10-minute device flow shouldn't kill the connect attempt.
            let maxTransientFailures = 5
            var transientFailures = 0
            while !Task.isCancelled && Date() < deadline {
                try? await Task.sleep(nanoseconds: UInt64(sleepSeconds) * 1_000_000_000)
                guard let self else { return }
                do {
                    let response = try await self.client.poll(baseUrl: baseUrl, deviceCode: deviceCode)
                    shenmaLog.notice("[Shenma] poll: status=\(response.status), hasToken=\(response.token != nil), hasUser=\(response.user != nil)")
                    transientFailures = 0
                    if response.status == "approved" && (response.token == nil || response.user == nil) {
                        // Server signaled approved but the payload is missing required
                        // fields — treat as a transient/decoding failure.
                        throw ShenmaConnectionError.missingToken
                    }
                    await self.applyPollResponse(response, baseUrl: baseUrl)
                    if response.status != "authorization_pending" {
                        // Terminal state — applyPollResponse already cleared isConnecting
                        // and tore the loop down. Bail.
                        return
                    }
                    // Pending — keep waiting.
                    continue
                } catch let error as ShenmaConnectionError {
                    shenmaLog.notice("[Shenma] poll error (ShenmaConnectionError): \(error)")
                    // 4xx (404/410/...) from the server is terminal; back-off + retry on
                    // network/decoding errors.
                    if case .http(let code, _) = error, (400..<500).contains(code) {
                        self.lastError = error.localizedDescription
                        self.isConnecting = false
                        self.userCode = nil
                        return
                    }
                    transientFailures += 1
                    if transientFailures >= maxTransientFailures {
                        self.lastError = error.localizedDescription
                        self.isConnecting = false
                        self.userCode = nil
                        return
                    }
                } catch {
                    shenmaLog.notice("[Shenma] poll error (other): \(error)")
                    transientFailures += 1
                    if transientFailures >= maxTransientFailures {
                        self.lastError = error.localizedDescription
                        self.isConnecting = false
                        self.userCode = nil
                        return
                    }
                }
            }
            await MainActor.run {
                guard let self else { return }
                if self.isConnecting {
                    self.lastError = ShenmaConnectionError.timeout.localizedDescription
                    self.isConnecting = false
                    self.userCode = nil
                }
            }
        }
    }

    private func loadAccount() -> ShenmaAccount? {
        guard let data = UserDefaults.standard.data(forKey: accountKey) else { return nil }
        return try? JSONDecoder().decode(ShenmaAccount.self, from: data)
    }

    private func saveAccount(_ account: ShenmaAccount?) {
        if let account, let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: accountKey)
        } else {
            UserDefaults.standard.removeObject(forKey: accountKey)
        }
    }
}

enum ShenmaKeychain {
    private static let service = "com.yoqu.ZenWallpaper.shenma"
    private static let account = "authToken"

    /// Whether the data-protection keychain is available. Cached once at launch
    /// to avoid probing on every save/load. Ad-hoc signed apps (no Keychain
    /// Access Groups entitlement) get `-34018 errSecMissingEntitlement`.
    private static let canUseDataProtection: Bool = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yoqu.ZenWallpaper.probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("x".utf8),
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        if status == errSecSuccess || status == errSecDuplicateItem {
            // Clean up probe entry.
            let del: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.yoqu.ZenWallpaper.probe",
                kSecAttrAccount as String: "probe",
                kSecUseDataProtectionKeychain as String: true
            ]
            SecItemDelete(del as CFDictionary)
            return true
        }
        shenmaLog.notice("[Shenma] data-protection keychain unavailable (probe returned \(status)), using standard keychain")
        return false
    }()

    static func saveToken(_ token: String) {
        deleteToken()
        guard let data = token.data(using: .utf8) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        if canUseDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            shenmaLog.notice("[Shenma] saveToken failed: \(status)")
        }
    }

    static func loadToken() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if canUseDataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let token = String(data: data, encoding: .utf8) {
            return token
        }
        // If using data-protection, also check the standard keychain for
        // tokens saved before the migration and migrate them forward.
        if canUseDataProtection {
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var legacyResult: AnyObject?
            if SecItemCopyMatching(legacyQuery as CFDictionary, &legacyResult) == errSecSuccess,
               let data = legacyResult as? Data,
               let token = String(data: data, encoding: .utf8) {
                saveToken(token)
                // Delete the old entry.
                let del: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(del as CFDictionary)
                return token
            }
        }
        return nil
    }

    static func deleteToken() {
        // Delete from both keychains to be safe.
        if canUseDataProtection {
            let dpQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecUseDataProtectionKeychain as String: true
            ]
            SecItemDelete(dpQuery as CFDictionary)
        }
        let stdQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(stdQuery as CFDictionary)
    }
}
