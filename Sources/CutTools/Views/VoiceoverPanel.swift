import SwiftUI

struct VoiceoverPanel: View {
    @EnvironmentObject var ai: AIModelStore
    @ObservedObject var store: VoiceoverStore
    let text: String
    var body: some View {
        Surface(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("AI 配音", systemImage: "waveform").font(.headline)
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }.help("设置语音服务和配音 API Key")
                }
                HStack {
                    Picker("声音", selection: $store.voice) {
                        ForEach(NarrationVoice.allCases, id: \.self) { voice in Text(voice.title).tag(voice) }
                    }.labelsHidden().accessibilityLabel("配音声音").disabled(store.busy)
                    Button("一键生成配音") { generate() }.buttonStyle(.borderedProminent)
                        .disabled(store.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("仅朗读全部镜头的口播文字。发送至 \(ai.voiceoverConfig.baseURL)，可能计费；声音为 AI 合成。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    if store.busy { ProgressView().controlSize(.small) }
                    Text(store.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    if store.busy { Button("取消配音") { store.cancel() } }
                }
                if let result = store.result {
                    HStack {
                        Text(result.voice.title).font(.caption)
                        Spacer()
                        Button("保存 WAV…") { store.save() }
                    }
                    StudioPlayer(url: result.url).frame(height: 54).accessibilityLabel("配音试听播放器")
                    if result.text != text || result.voice != store.voice {
                        Text("口播或所选音色已变化，当前试听仍是上次生成的配音。请重新生成以更新。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
    func generate() {
        do { let (config, key) = try ai.voiceoverSnapshot(); store.generate(text: text, config: config, key: key) }
        catch { store.message = error.localizedDescription }
    }
}
