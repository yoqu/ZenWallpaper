// End-to-end test of APIClient. Compile with:
//   swiftc test_e2e.swift Sources/ZenWallpaper/APIClient.swift -o /tmp/zen_test -framework AppKit
// Then run /tmp/zen_test
import Foundation

@main
struct E2ETest {
    static func main() async {
        let api = APIClient()
        let prompt = "minimalist mountain at dawn, soft warm light, balanced negative space, no text"
        let env = ProcessInfo.processInfo.environment
        let baseUrl = env["ZENWALLPAPER_BASE_URL"] ?? "https://api.openai.com/v1"
        let apiKey = env["ZENWALLPAPER_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            print("[test] Set ZENWALLPAPER_API_KEY before running this test.")
            exit(1)
        }
        print("[test] submitting prompt to gpt-image-2…")
        do {
            let result = try await api.generate(
                baseUrl: baseUrl,
                apiKey: apiKey,
                model: "gpt-image-2",
                prompt: prompt,
                size: "1024x1024",
                progress: { label, frac in
                    print("[progress \(Int(frac*100))%] \(label)")
                }
            )
            print("[test] received \(result.data.count) bytes (\(result.mimeType))")
            let outURL = URL(fileURLWithPath: "/tmp/zen_test_output.png")
            try result.data.write(to: outURL)
            print("[test] wrote \(outURL.path)")
            // sanity: PNG magic
            let head = result.data.prefix(8)
            let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            let jpgMagic: [UInt8] = [0xFF, 0xD8, 0xFF]
            if head.starts(with: pngMagic) {
                print("[test] OK: valid PNG header")
            } else if head.starts(with: jpgMagic) {
                print("[test] OK: valid JPEG header")
            } else {
                print("[test] WARN: unknown image header")
            }
            exit(0)
        } catch {
            print("[test] FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }
}

// Bridge top-level await
@_silgen_name("swift_task_asyncMainDrainQueue")
func _drain() -> Never
