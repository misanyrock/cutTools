import SwiftUI

struct CopywritingView: View {
    @EnvironmentObject var ai: AIModelStore
    @ObservedObject var store: CopyStore
    @State private var confirmReplace = false
    @State private var offline = false
    @State private var confirmOpen = false
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            HStack {
                VStack(alignment: .leading) { Text("从零写稿").font(.title.bold()); Text("从主题到口播与分镜；修改会自动保存在本机").foregroundStyle(.secondary) }
                Spacer(); Button("载入文案") { if store.draft == nil { store.open() } else { confirmOpen = true } }.disabled(store.busy)
            }
            HStack(alignment: .top,spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading,spacing: 12) {
                        Text("创作需求").font(.headline)
                        TextField("主题（必填）",text: $store.brief.topic,axis: .vertical)
                        TextField("给谁看？例如初学剪辑的学生",text: $store.brief.audience,axis: .vertical)
                        Picker("目标",selection: $store.brief.purpose) { ForEach(["分享观点","讲故事","知识讲解","介绍产品","引导行动"],id: \.self) { Text($0).tag($0) } }
                        Stepper("目标时长：\(store.brief.seconds) 秒",value: $store.brief.seconds,in: 15...600,step: 15)
                        Picker("风格",selection: $store.brief.tone) { ForEach(["自然口语","温暖叙事","简洁有力","轻松幽默","专业清晰"],id: \.self) { Text($0).tag($0) } }
                        Text("事实与素材（人、事、观点、产品信息）").font(.caption)
                        InsetTextEditor(text: $store.brief.facts, accessibilityLabel: "事实与素材").frame(height: 120).border(.secondary.opacity(0.3))
                        TextField("必须包含 / 不要出现的内容",text: $store.brief.restrictions,axis: .vertical)
                        Divider(); Text("当前模型：\(ai.config.provider.title)").font(.headline)
                        Text(ai.config.model.isEmpty ? "请配置模型" : ai.config.model).foregroundStyle(.secondary)
                        SettingsLink { Text("模型与 API Key 设置…") }
                        Text(ai.config.provider == .ollama ? "使用本机 Ollama。未安装时可生成写作提纲。" : "生成时会将创作需求与素材文字发送至 \(ai.config.baseURL)，可能计费。").font(.caption).foregroundStyle(.secondary)
                        Button("生成完整初稿") { generate(offline: false) }.buttonStyle(.borderedProminent).disabled(store.brief.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("生成写作提纲（无需模型）") { generate(offline: true) }
                    }.disabled(store.busy).padding(.trailing,12)
                }.frame(width: 310).frame(maxHeight: .infinity,alignment: .top)
                Divider()
                VStack(alignment: .leading,spacing: 10) {
                    if let draft = store.draft {
                        editor(Binding(get: { store.draft ?? draft },set: { store.draft = $0 }))
                    } else { ContentUnavailableView("你的第一稿从这里开始",systemImage: "square.and.pencil",description: Text("填好主题与素材，生成三个开头方案和一份可编辑的完整稿件。")) }
                }.padding(.leading,12).frame(minWidth: 400,maxWidth: .infinity,maxHeight: .infinity,alignment: .top)
            }
            HStack { if store.busy { ProgressView().controlSize(.small); Button("取消") { store.cancel() } }; Text(store.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .confirmationDialog("生成新稿会替换当前稿件（当前编辑已自动保存，可先导出工程）",isPresented: $confirmReplace) { Button("替换生成",role: .destructive) { runGeneration() } }
        .confirmationDialog("载入其他工程会替换当前文案",isPresented: $confirmOpen) { Button("选择其他工程") { store.open() } }
    }
    func generate(offline: Bool) { self.offline = offline; if store.draft == nil { runGeneration() } else { confirmReplace = true } }
    func runGeneration() {
        if offline { store.generate(offline:true); return }
        do { let (config,key) = try ai.snapshot(); store.generate(offline:false,config:config,key:key) } catch { store.message = error.localizedDescription }
    }
    func editor(_ draft: Binding<CopyDraft>) -> some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack { Text("分镜计划 \(draft.wrappedValue.plannedSeconds) 秒 · 口播估算 \(draft.wrappedValue.estimatedSeconds) 秒").font(.caption).foregroundStyle(.secondary); Spacer() }
            TextField("标题",text: draft.title).font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading,spacing: 14) {
                    Text("开头备选").font(.headline)
                    ForEach(draft.wrappedValue.openings.indices,id: \.self) { i in HStack(alignment: .top) { TextField("开头",text: draft.openings[i],axis: .vertical); Button("用作首段") { guard !draft.wrappedValue.scenes.isEmpty else { return }; draft.wrappedValue.scenes[0].spoken = draft.wrappedValue.openings[i] } } }
                    Divider()
                    ForEach(draft.scenes) { scene in
                        VStack(alignment: .leading,spacing: 6) {
                            Stepper("片段时长：\(scene.wrappedValue.seconds) 秒",value: scene.seconds,in: 1...600)
                            Text("口播").font(.caption).foregroundStyle(.secondary)
                            InsetTextEditor(text: scene.spoken, accessibilityLabel: "口播文字").frame(height: 100).border(.secondary.opacity(0.25))
                            TextField("画面与镜头建议",text: scene.visual,axis: .vertical)
                            TextField("屏幕文字",text: scene.caption,axis: .vertical)
                        }.padding(12).background(.quaternary.opacity(0.4),in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            HStack { Button("复制口播稿") { store.copyText() }; Button("导出 Markdown") { store.save(project: false) }; Button("保存文案工程") { store.save(project: true) } }
        }.disabled(store.busy)
    }
}
