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

    static func poll(enabled: Bool, url: URL, status: Int, data: Data, attempt: Int) {
        guard enabled else { return }
        let body = String(data: data, encoding: .utf8) ?? "<binary \(data.count)B>"
        emit("← poll#\(attempt) \(status) \(url.absoluteString)\nbody:\n\(body)")
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
    case taskTimeout

    var errorDescription: String? {
        switch self {
        case .badResponse(let s): return localizedString("error.badResponse", language: nil, s)
        case .decoding(let s): return localizedString("error.decoding", language: nil, s)
        case .noImage: return localizedString("error.noImage")
        case .http(let code, let body): return localizedString("error.http", language: nil, code, body)
        case .network(let s): return localizedString("error.network", language: nil, s)
        case .taskFailed(let s): return localizedString("error.taskFailed", language: nil, s)
        case .taskTimeout: return localizedString("error.taskTimeout")
        }
    }
}

struct ImageGenerationResult {
    let data: Data
    let mimeType: String
}

actor APIClient {
    // Supports OpenAI-compatible image endpoints and async providers that return task IDs.
    private struct SubmitItem: Decodable {
        let status: String?
        let task_id: String?
        // Synchronous-style fields (in case some models return inline):
        let url: String?
        let b64_json: String?
    }
    private struct SubmitEnvelope: Decodable {
        let code: Int?
        let data: [SubmitItem]?
        let error: ErrorBody?
    }
    private struct ErrorBody: Decodable {
        let message: String?
        let type: String?
    }

    // Task polling: GET /tasks/{id} → { code, data: { status, progress, result: { images: [{ url: [..] }] } } }
    private struct TaskImage: Decodable {
        let url: [String]?
    }
    private struct TaskResult: Decodable {
        let images: [TaskImage]?
    }
    private struct TaskData: Decodable {
        let status: String?
        let progress: Int?
        let result: TaskResult?
        let error: String?
        let message: String?
    }
    private struct TaskEnvelope: Decodable {
        let code: Int?
        let data: TaskData?
        let error: ErrorBody?
    }

    /// Generate an image. Calls progress(label, fraction 0…1) for UI updates.
    func generate(baseUrl: String,
                  apiKey: String,
                  model: String,
                  prompt: String,
                  size: String,
                  debugLogging: Bool = false,
                  progress: (@Sendable (String, Double) -> Void)? = nil) async throws -> ImageGenerationResult {
        var trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.isEmpty { trimmed = "https://api.openai.com/v1" }
        guard let submitURL = URL(string: "\(trimmed)/images/generations") else {
            throw APIError.badResponse(localizedString("error.urlInvalid"))
        }

        // Submit
        var req = URLRequest(url: submitURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": size,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        APILog.req(enabled: debugLogging, url: submitURL, body: body)

        let (subData, subResp): (Data, URLResponse)
        do {
            (subData, subResp) = try await URLSession.shared.data(for: req)
        } catch {
            APILog.info(enabled: debugLogging, "submit network error: \(error.localizedDescription)")
            throw APIError.network(error.localizedDescription)
        }

        guard let subHttp = subResp as? HTTPURLResponse else {
            APILog.info(enabled: debugLogging, "submit non-HTTP response")
            throw APIError.badResponse(localizedString("error.nonHttpResponse"))
        }
        APILog.resp(enabled: debugLogging, url: submitURL, status: subHttp.statusCode, data: subData)
        if !(200..<300).contains(subHttp.statusCode) {
            let body = String(data: subData, encoding: .utf8) ?? ""
            throw APIError.http(subHttp.statusCode, String(body.prefix(500)))
        }

        let envelope: SubmitEnvelope
        do {
            envelope = try JSONDecoder().decode(SubmitEnvelope.self, from: subData)
        } catch {
            let body = String(data: subData, encoding: .utf8) ?? ""
            throw APIError.decoding("\(error.localizedDescription) | \(String(body.prefix(300)))")
        }

        if let err = envelope.error?.message {
            throw APIError.taskFailed(err)
        }
        guard let item = envelope.data?.first else {
            throw APIError.noImage
        }

        // Sync response path
        if let urlStr = item.url, let imgUrl = URL(string: urlStr) {
            return try await downloadImage(from: imgUrl, debugLogging: debugLogging)
        }
        if let b64 = item.b64_json, let imgData = Data(base64Encoded: b64) {
            return ImageGenerationResult(data: imgData, mimeType: "image/png")
        }

        // Async task polling
        guard let taskId = item.task_id else {
            throw APIError.noImage
        }
        guard let taskURL = URL(string: "\(trimmed)/tasks/\(taskId)") else {
            throw APIError.badResponse(localizedString("error.taskUrlInvalid"))
        }

        let imageUrl = try await pollTask(url: taskURL, apiKey: apiKey, debugLogging: debugLogging, progress: progress)
        return try await downloadImage(from: imageUrl, debugLogging: debugLogging)
    }

    private func pollTask(url: URL,
                          apiKey: String,
                          debugLogging: Bool,
                          progress: (@Sendable (String, Double) -> Void)?) async throws -> URL {
        // Poll up to ~3 minutes. Start fast then back off slightly.
        let intervalsMs: [UInt64] = Array(repeating: 2_000, count: 90)
        let maxAttempts = intervalsMs.count

        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: intervalsMs[attempt] * 1_000_000)

            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.timeoutInterval = 20

            let (data, resp): (Data, URLResponse)
            do {
                (data, resp) = try await URLSession.shared.data(for: req)
            } catch {
                APILog.info(enabled: debugLogging, "poll#\(attempt) network error: \(error.localizedDescription)")
                // transient network error — keep trying
                continue
            }
            APILog.poll(enabled: debugLogging,
                        url: url,
                        status: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                        data: data,
                        attempt: attempt)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                continue
            }

            let env: TaskEnvelope
            do {
                env = try JSONDecoder().decode(TaskEnvelope.self, from: data)
            } catch {
                continue
            }

            let status = env.data?.status?.lowercased() ?? ""
            let pct = Double(env.data?.progress ?? 0) / 100.0

            switch status {
            case "completed", "succeeded", "success":
                guard let urlStr = env.data?.result?.images?.first?.url?.first,
                      let imgUrl = URL(string: urlStr) else {
                    throw APIError.noImage
                }
                progress?(localizedString("gen.downloading"), 0.85)
                return imgUrl
            case "failed", "error":
                throw APIError.taskFailed(env.data?.error ?? env.data?.message ?? localizedString("error.unknown"))
            default:
                // pending / running / processing / submitted
                let frac = max(0.55, min(0.80, 0.55 + pct * 0.25))
                progress?(String(format: localizedString("gen.progress"), Int(pct*100)), frac)
            }
        }
        throw APIError.taskTimeout
    }

    private func downloadImage(from url: URL, debugLogging: Bool = false) async throws -> ImageGenerationResult {
        APILog.info(enabled: debugLogging, "download image: \(url.absoluteString)")
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let mime = (resp as? HTTPURLResponse)?.mimeType ?? "image/png"
            return ImageGenerationResult(data: data, mimeType: mime)
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
