import Foundation
import AppKit

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
        case .badResponse(let s): return "服务返回异常: \(s)"
        case .decoding(let s): return "解析失败: \(s)"
        case .noImage: return "未返回图像"
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .network(let s): return "网络错误: \(s)"
        case .taskFailed(let s): return "生成失败: \(s)"
        case .taskTimeout: return "生成超时"
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
                  progress: (@Sendable (String, Double) -> Void)? = nil) async throws -> ImageGenerationResult {
        var trimmed = baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if trimmed.isEmpty { trimmed = "https://api.openai.com/v1" }
        guard let submitURL = URL(string: "\(trimmed)/images/generations") else {
            throw APIError.badResponse("URL 无效")
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

        let (subData, subResp): (Data, URLResponse)
        do {
            (subData, subResp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let subHttp = subResp as? HTTPURLResponse else {
            throw APIError.badResponse("非 HTTP 响应")
        }
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
            return try await downloadImage(from: imgUrl)
        }
        if let b64 = item.b64_json, let imgData = Data(base64Encoded: b64) {
            return ImageGenerationResult(data: imgData, mimeType: "image/png")
        }

        // Async task polling
        guard let taskId = item.task_id else {
            throw APIError.noImage
        }
        guard let taskURL = URL(string: "\(trimmed)/tasks/\(taskId)") else {
            throw APIError.badResponse("任务 URL 无效")
        }

        let imageUrl = try await pollTask(url: taskURL, apiKey: apiKey, progress: progress)
        return try await downloadImage(from: imageUrl)
    }

    private func pollTask(url: URL,
                          apiKey: String,
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
                // transient network error — keep trying
                continue
            }
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
                progress?("下载图像…", 0.85)
                return imgUrl
            case "failed", "error":
                throw APIError.taskFailed(env.data?.error ?? env.data?.message ?? "未知原因")
            default:
                // pending / running / processing / submitted
                let frac = max(0.55, min(0.80, 0.55 + pct * 0.25))
                progress?("生成中…(\(Int(pct*100))%)", frac)
            }
        }
        throw APIError.taskTimeout
    }

    private func downloadImage(from url: URL) async throws -> ImageGenerationResult {
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            let mime = (resp as? HTTPURLResponse)?.mimeType ?? "image/png"
            return ImageGenerationResult(data: data, mimeType: mime)
        } catch {
            throw APIError.network("下载图像失败: \(error.localizedDescription)")
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
