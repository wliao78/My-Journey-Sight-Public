import SwiftUI

struct GuideSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("guideVoiceIdentifier") private var voiceIdentifier = ""
    @AppStorage("publicAIProvider") private var providerID = PublicAIProvider.openAI.rawValue
    @StateObject private var voicePreview = GuideSpeechPlaybackService()
    @State private var key = ""
    @State private var status = ""
    @State private var testing = false
    @State private var aiConsent = PublicAIConsent.granted

    var body: some View {
        NavigationStack {
            Form {
                Section("讲解声音") {
                    Picker("中文声音", selection: $voiceIdentifier) {
                        Text("温和女声（自动选择）").tag("")
                        ForEach(GuideSpeechPlaybackService.chineseVoices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    Button(voicePreview.speakingMessageID == nil ? "试听声音" : "停止试听") {
                        if voicePreview.speakingMessageID == nil {
                            voicePreview.toggle(message: GuideMessage(isUser: false, text: String(localized: "欢迎来到这里。接下来，我们一起听听这座城市的故事。")))
                        } else {
                            voicePreview.stop()
                        }
                    }
                    Text("可选声音取决于设备已安装的系统中文语音。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(SightTheme.panel)
                Section("AI 服务") {
                    Picker("服务商", selection: $providerID) {
                        ForEach(PublicAIProvider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .onChange(of: providerID) { _, _ in aiConsent = PublicAIConsent.granted }
                    SecureField("在此粘贴 API Key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存") {
                        let didSave = APIKeyStore(provider: selectedProvider).save(key)
                        status = didSave ? String(localized: "已安全保存在此设备钥匙串。") : String(localized: "保存失败。")
                        if didSave { key = "" }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    Button(testing ? "正在测试…" : "测试连接") {
                        testing = true
                        Task {
                            do {
                                try await GuideAIClient().testConnection()
                                status = String(localized: "连接成功。返回首页即可获取 AI 推荐。")
                            } catch { status = error.localizedDescription }
                            testing = false
                        }
                    }
                    .disabled(testing)
                    .buttonStyle(.bordered)
                    Button("删除已保存的密钥", role: .destructive) {
                        APIKeyStore(provider: selectedProvider).clear()
                        status = String(localized: "密钥已删除。")
                    }
                    Toggle("同意向所选 AI 服务商发送资料", isOn: $aiConsent)
                        .onChange(of: aiConsent) { _, value in PublicAIConsent.set(value) }
                    Text("使用 AI 时，输入文字、照片、位置及相关地点信息会发送给所选服务商。可随时关闭；关闭后仍可浏览演示内容。")
                        .font(.footnote)
                }
                .listRowBackground(SightTheme.panel)
                Section {
                    Text(status.isEmpty ? "密钥仅存在本设备钥匙串，不写入项目文件。" : status)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(SightTheme.panel)
            }
            .scrollContentBackground(.hidden)
            .background { SightTheme.background }
            .foregroundStyle(.white)
            .tint(SightTheme.accent)
            .preferredColorScheme(.dark)
            .navigationTitle("设置")
            .onDisappear { voicePreview.stop() }
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private var selectedProvider: PublicAIProvider {
        PublicAIProvider(rawValue: providerID) ?? .openAI
    }
}
