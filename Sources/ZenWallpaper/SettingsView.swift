import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    let close: () -> Void

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

                Section {
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
