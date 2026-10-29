import SwiftUI

struct AISettingsView: View {
    @EnvironmentObject var ai: AIModelStore
    var body: some View {
        Form {
            Picker("模型服务",selection:Binding(get:{ ai.config.provider },set:{ ai.select($0) })) { ForEach(ModelProvider.allCases) { Text($0.title).tag($0) } }.disabled(ai.busy)
            TextField("Base URL",text:$ai.config.baseURL).disabled(ai.busy)
            TextField(ai.config.provider == .doubao ? "模型名或接入点 ID" : "模型名",text:$ai.config.model).disabled(ai.busy)
            if ai.config.provider != .ollama {
                SecureField("API Key（输入后点击保存）",text:$ai.keyInput).disabled(ai.busy)
                HStack { Button("保存 API Key") { ai.saveKey() }; Button("删除已保存的 Key") { ai.deleteKey() } }.disabled(ai.busy)
                Toggle("请求 JSON 模式（模型需支持）",isOn:$ai.config.jsonMode).disabled(ai.busy)
                Text("在线调用会将文案需求、素材文字或待翻译字幕发送至上方服务地址，可能产生费用。API Key 仅存钥匙串；修改地址后需重新保存 Key。").font(.caption).foregroundStyle(.secondary)
                if ai.config.provider == .qwen { Text("千问预设为北京地域通用地址，也可填写控制台的业务空间专属地址；Key 需与地域匹配。").font(.caption).foregroundStyle(.secondary) }
                if ai.config.provider == .doubao { Text("填写火山方舟控制台已开通的模型 ID 或 ep- 开头的推理接入点 ID。").font(.caption).foregroundStyle(.secondary) }
            } else { Text("使用本机 Ollama，无需 API Key。原有本地模型设置已迁移到这里。").font(.caption).foregroundStyle(.secondary) }
            HStack { Button(ai.config.provider == .ollama ? "测试模型" : "发送测试请求（可能计费）") { ai.test() }.disabled(ai.busy); if ai.busy { ProgressView().controlSize(.small); Button("取消") { ai.cancel() } } }
            Text(ai.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }.padding(24).frame(width:580).fixedSize(horizontal:false,vertical:true)
    }
}
