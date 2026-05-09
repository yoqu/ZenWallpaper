import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var manager: WallpaperManager
    @EnvironmentObject var autoScheduler: AutoWallpaperScheduler
    @EnvironmentObject var shenma: ShenmaConnectionManager
    @EnvironmentObject var l10n: LocalizationManager
    let close: () -> Void

    @State private var showWeChatQR = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label(l10n.t("common.back"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                Text(l10n.t("settings.title"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            Form {
                Section(l10n.t("settings.section.generation")) {
                    Toggle(l10n.t("settings.useDate"), isOn: $settings.useDate)
                        .controlSize(.small)
                    Toggle(l10n.t("settings.useLunar"), isOn: $settings.useLunar)
                        .controlSize(.small)
                    Picker(l10n.t("settings.autoGenerate"), selection: Binding(
                        get: { settings.autoFreq },
                        set: { settings.autoFreq = $0 })) {
                        ForEach(AutoFreq.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .controlSize(.small)
                    LabeledContent(l10n.t("settings.autoStatus")) {
                        Text(autoScheduler.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(l10n.t("settings.imageSize")) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(WallpaperManager.bestSizeForMainScreen())
                                .font(.caption.monospacedDigit())
                            Text(l10n.t("settings.fitsScreen", WallpaperManager.describeMainScreen()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section(l10n.t("settings.section.system")) {
                    Picker(l10n.t("settings.language"), selection: $settings.appLanguageRaw) {
                        Text(l10n.t("settings.language.system")).tag(AppLanguage.system.rawValue)
                        Text("中文").tag(AppLanguage.zh.rawValue)
                        Text("English").tag(AppLanguage.en.rawValue)
                    }
                    .controlSize(.small)
                    Picker(l10n.t("settings.historyLimit"), selection: $settings.cacheLimit) {
                        Text(l10n.t("common.images_count", 6)).tag(6)
                        Text(l10n.t("common.images_count", 12)).tag(12)
                        Text(l10n.t("common.images_count", 24)).tag(24)
                        Text(l10n.t("common.images_count", 50)).tag(50)
                    }
                    .controlSize(.small)
                    LabeledContent(l10n.t("settings.cacheDir")) {
                        Button {
                            manager.openCacheDirectory()
                        } label: {
                            Label(l10n.t("common.openInFinderShort"), systemImage: "folder")
                        }
                        .controlSize(.small)
                    }
                }

                Section(l10n.t("settings.section.shenma")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.t("settings.shenmaEndpoint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // One-tap preset switcher. Picking Production / Local dev fills
                        // the URL field with the canonical value; Custom hands control
                        // back to whatever's typed below.
                        Picker("", selection: Binding(
                            get: { ShenmaEndpoint.match(settings.shenmaBaseUrl) },
                            set: { preset in
                                if preset != .custom {
                                    settings.shenmaBaseUrl = preset.url
                                }
                            }
                        )) {
                            Text(l10n.t("settings.shenmaEndpoint.production"))
                                .tag(ShenmaEndpoint.production)
                            Text(l10n.t("settings.shenmaEndpoint.localhost"))
                                .tag(ShenmaEndpoint.localhost)
                            Text(l10n.t("settings.shenmaEndpoint.custom"))
                                .tag(ShenmaEndpoint.custom)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.t("settings.shenmaBaseUrl"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("", text: $settings.shenmaBaseUrl)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .labelsHidden()
                            .help(l10n.t("settings.shenmaBaseUrlHelp"))
                    }
                    if let account = shenma.account {
                        LabeledContent(l10n.t("settings.shenmaStatus")) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(account.user.nickname)
                                    .font(.caption)
                                Text("@\(account.user.username)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else if shenma.isConnecting {
                        LabeledContent(l10n.t("settings.shenmaStatus")) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(l10n.t("settings.shenmaConnecting"))
                                    .font(.caption)
                                if let code = shenma.userCode {
                                    Text(code)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    } else {
                        LabeledContent(l10n.t("settings.shenmaStatus")) {
                            Text(l10n.t("settings.shenmaDisconnected"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = shenma.lastError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    // One action button at a time, three mutually exclusive states:
                    //   • disconnected → prominent "Connect"
                    //   • connecting  → red "Cancel" (aborts the poll loop locally)
                    //   • connected   → red "Disconnect" (revokes the token server-side too)
                    // Showing both buttons grayed-out at the same time was confusing.
                    HStack {
                        if shenma.isConnected {
                            Button(role: .destructive) {
                                shenma.disconnect(baseUrl: settings.shenmaBaseUrl)
                            } label: {
                                Label(l10n.t("settings.shenmaDisconnect"), systemImage: "xmark.circle")
                            }
                            .controlSize(.small)
                        } else if shenma.isConnecting {
                            Button(role: .destructive) {
                                shenma.disconnect(baseUrl: settings.shenmaBaseUrl)
                            } label: {
                                Label(l10n.t("settings.shenmaCancel"), systemImage: "xmark.circle")
                            }
                            .controlSize(.small)
                        } else {
                            Button {
                                Task { await shenma.connect(baseUrl: settings.shenmaBaseUrl) }
                            } label: {
                                Label(l10n.t("settings.shenmaConnect"), systemImage: "link")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                Section(l10n.t("settings.section.debug")) {
                    Toggle(l10n.t("settings.debugLogging"), isOn: $settings.debugLogging)
                        .controlSize(.small)
                    LabeledContent(l10n.t("settings.logsDir")) {
                        Button {
                            manager.openLogsDirectory()
                        } label: {
                            Label(l10n.t("common.open"), systemImage: "folder")
                        }
                        .controlSize(.small)
                        .help(l10n.t("settings.logsTip"))
                    }
                    Text(l10n.t("settings.debugDescription"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Section(l10n.t("settings.section.about")) {
                    LabeledContent(l10n.t("settings.feedback")) {
                        Link("GitHub Issues",
                             destination: URL(string: "https://github.com/yoqu/ZenWallpaper/issues")!)
                            .controlSize(.small)
                    }
                    LabeledContent("X / Twitter") {
                        Link("@LYoqu60097",
                             destination: URL(string: "https://x.com/LYoqu60097")!)
                            .controlSize(.small)
                    }
                    LabeledContent(l10n.t("settings.wechat")) {
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
                            .help(l10n.t("settings.wechatTip"))
                            .popover(isPresented: $showWeChatQR, arrowEdge: .trailing) {
                                WeChatQRPopover()
                            }
                        }
                    }
                    Text(l10n.t("settings.privacyNote"))
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
    @EnvironmentObject var l10n: LocalizationManager

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
                            Text(l10n.t("settings.qrMissing"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
            }
            Text(l10n.t("settings.wechatLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
    }
}
