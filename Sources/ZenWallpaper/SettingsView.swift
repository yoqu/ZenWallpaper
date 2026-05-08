import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var autoScheduler: AutoWallpaperScheduler
    let close: () -> Void

    @State private var showWeChatQR = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("返回", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Text("设置")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Form {
                Section("模型") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $settings.baseUrl)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    Picker("模型", selection: $settings.model) {
                        Text("gpt-image-2").tag("gpt-image-2")
                        Text("gpt-image-1").tag("gpt-image-1")
                        Text("dall-e-3").tag("dall-e-3")
                    }
                    .controlSize(.small)
                    LabeledContent("生成尺寸") {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(WallpaperManager.bestSizeForMainScreen())
                                .font(.caption.monospacedDigit())
                            Text("适配主屏 \(WallpaperManager.describeMainScreen())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("生成") {
                    Toggle("附加日期", isOn: $settings.useDate)
                        .controlSize(.small)
                    Toggle("附加黄历", isOn: $settings.useLunar)
                        .controlSize(.small)
                    Picker("自动生成", selection: Binding(
                        get: { settings.autoFreq },
                        set: { settings.autoFreq = $0 })) {
                        ForEach(AutoFreq.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .controlSize(.small)
                    LabeledContent("自动状态") {
                        Text(autoScheduler.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("系统") {
                    Picker("历史保留", selection: $settings.cacheLimit) {
                        Text("6 张").tag(6)
                        Text("12 张").tag(12)
                        Text("24 张").tag(24)
                        Text("50 张").tag(50)
                    }
                    .controlSize(.small)
                    LabeledContent("缓存目录") {
                        Button {
                            manager.openCacheDirectory()
                        } label: {
                            Label("在 Finder 中打开", systemImage: "folder")
                        }
                        .controlSize(.small)
                    }
                }

                Section("关于") {
                    LabeledContent("反馈") {
                        Link("GitHub Issues",
                             destination: URL(string: "https://github.com/yoqu/ZenWallpaper/issues")!)
                            .controlSize(.small)
                    }
                    LabeledContent("X / Twitter") {
                        Link("@LYoqu60097",
                             destination: URL(string: "https://x.com/LYoqu60097")!)
                            .controlSize(.small)
                    }
                    LabeledContent("微信") {
                        HStack(spacing: 6) {
                            Text("yoqu2020")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Button {
                                showWeChatQR.toggle()
                            } label: {
                                Image(systemName: "qrcode")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .help("显示微信二维码")
                            .popover(isPresented: $showWeChatQR, arrowEdge: .trailing) {
                                WeChatQRPopover()
                            }
                        }
                    }
                    Text("API Key 仅保存在本机 UserDefaults。生成的图像缓存目录：~/Library/Application Support/ZenWallpaper/cache/")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct WeChatQRPopover: View {
    var body: some View {
        VStack(spacing: 8) {
            if let url = Bundle.main.url(forResource: "wechat-qr",
                                         withExtension: "png",
                                         subdirectory: "Branding"),
               let img = NSImage(contentsOf: url) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .frame(width: 220, height: 220)
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                            Text("二维码资源缺失")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
            Text("微信号：yoqu2020")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
    }
}
