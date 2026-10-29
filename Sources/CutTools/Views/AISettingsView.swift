import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var ai: AIModelStore
    var body: some View {
        Form {
            Section {
                HStack(spacing:12) { Image(systemName:"sparkles").font(.title2).foregroundStyle(.indigo); VStack(alignment:.leading,spacing:4) { Text("模型与连接").font(.title2.bold()); Text("翻译与写稿使用同一套模型配置").foregroundStyle(.secondary).font(.callout) } }.padding(.vertical,6)
            }
            Section("服务连接") {
            Picker("模型服务",selection:Binding(get:{ ai.config.provider },set:{ ai.select($0) })) { ForEach(ModelProvider.allCases) { Text($0.title).tag($0) } }.disabled(ai.busy)
            TextField("Base URL",text:$ai.config.baseURL).disabled(ai.busy)
            TextField(ai.config.provider == .doubao ? "模型名或接入点 ID" : "模型名",text:$ai.config.model).disabled(ai.busy)
            }
            if ai.config.provider != .ollama {
                Section("API 密钥") {
                SecureField("API Key（输入后点击保存）",text:$ai.keyInput).disabled(ai.busy)
                HStack { Button("保存 API Key") { ai.saveKey() }; Button("删除已保存的 Key") { ai.deleteKey() } }.disabled(ai.busy)
                Toggle("请求 JSON 模式（模型需支持）",isOn:$ai.config.jsonMode).disabled(ai.busy)
                Text("在线调用会将文案需求、素材文字或待翻译字幕发送至上方服务地址，可能产生费用。API Key 仅存钥匙串；修改地址后需重新保存 Key。").font(.caption).foregroundStyle(.secondary)
                if ai.config.provider == .qwen { Text("千问预设为北京地域通用地址，也可填写控制台的业务空间专属地址；Key 需与地域匹配。").font(.caption).foregroundStyle(.secondary) }
                if ai.config.provider == .doubao { Text("填写火山方舟控制台已开通的模型 ID 或 ep- 开头的推理接入点 ID。").font(.caption).foregroundStyle(.secondary) }
                }
            } else { Text("使用本机 Ollama，无需 API Key。原有本地模型设置已迁移到这里。").font(.caption).foregroundStyle(.secondary) }
            HStack { Button(ai.config.provider == .ollama ? "测试模型" : "发送测试请求（可能计费）") { ai.test() }.disabled(ai.busy); if ai.busy { ProgressView().controlSize(.small); Button("取消") { ai.cancel() } } }
            Text(ai.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Section("AI 配音 · 千问语音合成") {
                TextField("语音 Base URL", text: $ai.voiceoverConfig.baseURL)
                TextField("语音模型", text: $ai.voiceoverConfig.model)
                SecureField("百炼 API Key（输入后点击保存）", text: $ai.voiceoverKeyInput)
                HStack { Button("保存配音 Key") { ai.saveVoiceoverKey() }; Button("删除配音 Key") { ai.deleteVoiceoverKey() } }
                Text(ai.voiceoverMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Text("默认使用北京地域 qwen3-tts-flash；Key 需与地域匹配。完整口播会发送至该语音服务，可能计费。生成声音为 AI 合成。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("百炼语音服务与 API Key 说明", destination: URL(string: "https://help.aliyun.com/zh/model-studio/qwen-tts-api")!)
            }
        }.formStyle(.grouped).frame(width:620,height:540).tint(.indigo)
    }
}
