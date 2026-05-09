import Foundation
import AppKit

private enum APILog {
    static let tag = "[ZenWallpaper.API]"
    private static let queue = DispatchQueue(label: "zenwallpaper.apilog", qos: .utility)
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func req(enabled: Bool, url: URL, body: [String: Any]) {
        guard enabled else { return }
        let bodyStr = (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "<unencodable>"
        emit("→ POST \(url.absoluteString)\nbody:\n\(bodyStr)")
    }

    static func resp(enabled: Bool, url: URL, status: Int, data: Data) {
        guard enabled else { return }
        let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
        emit("← \(status) \(url.absoluteString)\nbody:\n\(body)")
    }

    static func info(enabled: Bool, _ msg: String) {
        guard enabled else { return }
        emit(msg)
    }

    private static func emit(_ msg: String) {
        let line = "\(iso.string(from: Date())) \(tag) \(msg)\n"
        NSLog("\(tag) \(msg)")
        queue.async {
            let url = currentLogFile()
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path),
               let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func currentLogFile() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ZenWallpaper", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("api-\(dayFmt.string(from: Date())).log")
    }
}

enum APIError: Error, LocalizedError {
    case badResponse(String)
    case decoding(String)
    case noImage
    case http(Int, String)
    case network(String)
    case taskFailed(String)
    case unauthorized
    case insufficientCredits(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let s): return localizedString("error.badResponse", language: nil, s)
        case .decoding(let s): return localizedString("error.decoding", language: nil, s)
        case .noImage: return localizedString("error.noImage")
        case .http(let code, let body): return localizedString("error.http", language: nil, code, body)
        case .network(let s): return localizedString("error.network", language: nil, s)
        case .taskFailed(let s): return localizedString("error.taskFailed", language: nil, s)
        case .unauthorized: return localizedString("error.needLogin")
        case .insufficientCredits(let s): return s
        }
    }
}

struct ImageGenerationResult {
    let data: Data
    let mimeType: String
    /// New balance returned by the server immediately after the credit deduction.
    let balance: Int
    /// Backend work ID — the generation endpoint atomically creates a PENDING work
    /// and returns its ID. Desktop never has to do a separate "upload" step.
    let workId: String
    /// Server-side preview asset URL we already downloaded the bytes from. Kept
    /// in case callers want to display it as the canonical remote asset.
    let assetUrl: String
}

actor APIClient {
    /// All AI generation now goes through the qushenma backend.
    /// Endpoint: `POST {shenmaBaseUrl}/api/ai/generations`. The backend deducts
    /// the credit, calls the upstream model, stores the resulting image to
    /// object storage, and atomically creates a PENDING work in one transaction.
    /// We then download the image bytes from `previewAsset.url` to use locally.
    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool?
        let code: String?
        let message: String?
        let data: T?
    }

    private struct AssetDto: Decodable {
        let url: String?
        let mimeType: String?
    }

    private struct GenerationResultDto: Decodable {
        let generationId: String?
        let status: String?
        let chargedCredits: Int?
        let balance: Int?
        let workId: String?
        let previewAsset: AssetDto?
    }

    func generate(shenmaBaseUrl: String,
                  token: String,
                  prompt: String,
                  size: String,
                  debugLogging: Bool = false) async throws -> ImageGenerationResult {
        let trimmed = shenmaBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty, let submitURL = URL(string: "\(trimmed)/api/ai/generations") else {
            throw APIError.badResponse(localizedString("error.urlInvalid"))
        }

        var req = URLRequest(url: submitURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Backend blocks for the full upstream task lifecycle: submit + polling +
        // image download. Apimart's gpt-image-2 queue can take 11+ minutes during
        // load spikes (verified in production). Match the backend's 15-min poll
        // budget plus a small slack so the desktop doesn't drop the request while
        // the server's still doing useful work.
        req.timeoutInterval = 16 * 60

        let body: [String: Any] = [
            "model": "gpt-image-2",
            "prompt": prompt,
            "size": size,
            "publishMode": "pending_review",
            "clientRequestId": UUID().uuidString
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        APILog.req(enabled: debugLogging, url: submitURL, body: body)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            APILog.info(enabled: debugLogging, "submit network error: \(error.localizedDescription)")
            throw APIError.network(error.localizedDescription)
        }

        guard let http = resp as? HTTPURLResponse else {
            throw APIError.badResponse(localizedString("error.nonHttpResponse"))
        }
        APILog.resp(enabled: debugLogging, url: submitURL, status: http.statusCode, data: data)

        if http.statusCode == 401 {
            throw APIError.unauthorized
        }

        let envelope: Envelope<GenerationResultDto>
        do {
            envelope = try JSONDecoder().decode(Envelope<GenerationResultDto>.self, from: data)
        } catch {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) | \(String(snippet.prefix(300)))")
        }

        guard (200..<300).contains(http.statusCode), envelope.success != false else {
            let message = envelope.message ?? envelope.code ?? "HTTP \(http.statusCode)"
            // INSUFFICIENT_CREDITS is a known business code from the shenma backend.
            if let code = envelope.code, code.uppercased().contains("CREDIT") {
                throw APIError.insufficientCredits(message)
            }
            throw APIError.taskFailed(message)
        }

        guard let result = envelope.data,
              let assetUrl = result.previewAsset?.url,
              let workId = result.workId else {
            throw APIError.noImage
        }

        guard let imgUrl = URL(string: assetUrl) else {
            throw APIError.badResponse(localizedString("error.urlInvalid"))
        }

        let download = try await downloadImage(from: imgUrl, debugLogging: debugLogging)
        return ImageGenerationResult(
            data: download.data,
            mimeType: result.previewAsset?.mimeType ?? download.mimeType,
            balance: result.balance ?? 0,
            workId: workId,
            assetUrl: assetUrl
        )
    }

    private func downloadImage(from url: URL, debugLogging: Bool = false) async throws -> (data: Data, mimeType: String) {
        APILog.info(enabled: debugLogging, "download image: \(url.absoluteString)")
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let mime = (resp as? HTTPURLResponse)?.mimeType ?? "image/png"
            return (data, mime)
        } catch {
            APILog.info(enabled: debugLogging, "download error: \(error.localizedDescription)")
            throw APIError.network(error.localizedDescription)
        }
    }
}

struct PromptComposer {
    static func compose(mood: String,
                        moodEnergy: Double,
                        moodValence: Double,
                        style: String,
                        accent: String,
                        userPrompt: String,
                        useDate: Bool,
                        useLunar: Bool) -> String {
        var lines: [String] = []
        lines.append("A serene desktop wallpaper, photographic-quality digital art.")
        lines.append("Style: \(translateStyle(style)).")
        lines.append("Mood: \(mood) (energy=\(Int(moodEnergy*100)), valence=\(Int(moodValence*100))).")
        if accent != "auto" {
            lines.append("Dominant color tone: \(translateAccent(accent)).")
        }
        if useDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            lines.append("Date inspiration: \(f.string(from: Date())).")
        }
        if useLunar {
            lines.append("Cultural undertone: subtle Eastern lunar-calendar aesthetic, evoking 节气 / 物候 of the season.")
        }
        if !userPrompt.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("Additional cues: \(userPrompt).")
        }
        lines.append("Composition: cinematic, balanced negative space suitable as a desktop wallpaper, no text, no watermark, no people-faces.")
        return lines.joined(separator: " ")
    }

    private static func translateStyle(_ s: String) -> String {
        switch s {
        case "极简": return "minimalist, clean lines, soft gradients"
        case "水彩": return "watercolor painting, gentle washes"
        case "摄影": return "ultra realistic photography, shallow depth of field"
        case "赛博朋克": return "cyberpunk, neon-lit cityscape, vibrant"
        case "胶片": return "analog film photography, grain, warm tones"
        case "油画": return "oil painting, textured brush strokes"
        default: return s
        }
    }

    private static func translateAccent(_ a: String) -> String {
        switch a {
        case "ink":   return "deep ink black"
        case "sand":  return "warm sand beige"
        case "sea":   return "ocean blue"
        case "moss":  return "moss green"
        case "ember": return "ember orange-red"
        default: return "balanced palette"
        }
    }
}
