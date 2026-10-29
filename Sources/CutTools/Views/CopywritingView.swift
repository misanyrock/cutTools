import SwiftUI

struct CopywritingView: View {
    @EnvironmentObject var ai: AIModelStore
    @ObservedObject var store: CopyStore
    @ObservedObject var beats: BeatStore
    @State private var showHistory = false
    @State private var showTemplateName = false
    @State private var showAlignment = false
    @State private var confirmReplace = false
    @State private var offline = false
    @State private var confirmOpen = false
    @State private var showOpenings = false
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack {
                WorkspaceHeader(title:"从零写稿",subtitle:"把一个想法，写成可以开拍的脚本。",symbol:"square.and.pencil")
                Spacer(); Button { if store.draft == nil { store.open() } else { confirmOpen = true } } label: { Label("载入文案",systemImage:"folder") }.disabled(store.busy)
            }
            HStack(alignment:.top,spacing:20) {
                Surface(padding:18) {
                    VStack(alignment:.leading,spacing:16) {
                        HStack { Label("创作需求",systemImage:"slider.horizontal.3").font(.headline); Spacer(); Menu("模板") {
                            ForEach(CreativeTemplate.builtins) { template in Button(template.name) { store.applyTemplate(template) } }
                            Divider(); ForEach(store.templates) { template in Button(template.name) { store.applyTemplate(template) } }
                            Divider(); Button("保存当前设置为模板") { showTemplateName = true }; Button("导入个人模板") { store.importTemplates() }; Button("导出个人模板") { store.exportTemplates() }
                        }.fixedSize() }
                        ScrollView {
                            VStack(alignment:.leading,spacing:16) {
                                VStack(alignment:.leading,spacing:6) { FieldCaption(title:"主题 · 必填"); TextField("这条视频想讲什么？",text:$store.brief.topic,axis:.vertical).textFieldStyle(.roundedBorder) }
                                VStack(alignment:.leading,spacing:6) { FieldCaption(title:"目标观众"); TextField("例如：喜欢自驾旅行的朋友",text:$store.brief.audience,axis:.vertical).textFieldStyle(.roundedBorder) }
                                Picker("创作目标",selection:$store.brief.purpose) { ForEach(["分享观点","讲故事","知识讲解","介绍产品","引导行动"],id:\.self) { Text($0).tag($0) } }
                                Picker("表达风格",selection:$store.brief.tone) { ForEach(["自然口语","温暖叙事","简洁有力","轻松幽默","专业清晰"],id:\.self) { Text($0).tag($0) } }
                                Stepper("目标时长  \(store.brief.seconds) 秒",value:$store.brief.seconds,in:15...600,step:15).font(.callout)
                                VStack(alignment:.leading,spacing:6) {
                                    FieldCaption(title:"事实与素材")
                                    InsetTextEditor(text:$store.brief.facts,accessibilityLabel:"事实与素材").frame(height:132).clipShape(RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(.primary.opacity(0.12)))
                                    Text("人物、地点、观点，或希望讲到的细节。只用你提供的事实。").font(.caption).foregroundStyle(.secondary)
                                }
                                VStack(alignment:.leading,spacing:6) { FieldCaption(title:"其他要求"); TextField("必须包含 / 不要出现的内容",text:$store.brief.restrictions,axis:.vertical).textFieldStyle(.roundedBorder) }
                            }.padding(.trailing,3)
                        }
                        Divider()
                        HStack { Image(systemName:ai.config.provider == .ollama ? "desktopcomputer" : "sparkles").foregroundStyle(.indigo); VStack(alignment:.leading,spacing:2) { Text(ai.config.provider.title).font(.callout.weight(.medium)); Text(ai.config.model.isEmpty ? "尚未设置模型" : ai.config.model).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); SettingsLink { Image(systemName:"gearshape") }.help("模型与 API Key 设置") }
                        Text(ai.config.provider == .ollama ? "使用本机模型生成。" : "需求和素材将发送至 \(ai.config.baseURL)，调用可能计费。").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        Button { generate(offline:false) } label: { Label("生成完整初稿",systemImage:"sparkles").frame(maxWidth:.infinity) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.brief.topic.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        Button("先生成写作提纲") { generate(offline:true) }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity).help("无需模型；生成需要自行填写的提纲")
                    }.disabled(store.busy)
                }.frame(width:296)
                if let draft = store.draft { editor(Binding(get:{ store.draft ?? draft },set:{ store.draft = $0 })) }
                else { emptyDraft }
            }.frame(maxHeight:.infinity)
            if store.busy { HStack { ProgressView().controlSize(.small); Text(store.message).font(.callout).foregroundStyle(.secondary); Spacer(); Button("取消生成") { store.cancel() } } }
        }
        .sheet(item:$store.pendingRewrite) { proposal in RewriteComparisonView(store:store,proposal:proposal) }
        .sheet(isPresented:$showHistory) { CopyHistoryView(store:store) }
        .sheet(isPresented:$showTemplateName) { TemplateNameView(store:store) }
        .sheet(isPresented:$showAlignment) { MusicAlignmentView(copy:store,beats:beats) }
        .confirmationDialog("生成新稿会替换当前稿件，可先导出工程保留当前版本",isPresented:$confirmReplace) { Button("替换生成",role:.destructive) { runGeneration() } }
        .confirmationDialog("载入其他工程会替换当前文案",isPresented:$confirmOpen) { Button("选择其他工程") { store.open() } }
    }
    var emptyDraft: some View {
        Surface(padding:32) {
            VStack(spacing:20) {
                Spacer()
                Image(systemName:"doc.text").font(.system(size:44,weight:.light)).foregroundStyle(.indigo).frame(width:96,height:96).background(.indigo.opacity(0.07),in:RoundedRectangle(cornerRadius:24))
                Text("从一个想法开始").font(.system(size:24,weight:.semibold))
                Text("填写左侧需求，生成开头、完整口播和分镜建议。\n每一段都可以继续修改，草稿会自动保存。").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                HStack(spacing:24) { Label("明确主题",systemImage:"1.circle"); Label("生成初稿",systemImage:"2.circle"); Label("修改定稿",systemImage:"3.circle") }.font(.caption).foregroundStyle(.secondary).padding(.top,10)
                Spacer()
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    func generate(offline:Bool) { self.offline = offline; if store.draft == nil { runGeneration() } else { confirmReplace = true } }
    func runGeneration() {
        if offline { store.generate(offline:true); return }
        do { let (config,key) = try ai.snapshot(); store.generate(offline:false,config:config,key:key) } catch { store.message = error.localizedDescription }
    }
    func editor(_ draft:Binding<CopyDraft>) -> some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                Text("脚本工作台").font(.headline)
                Menu("版本") { Button("保存当前版本") { store.checkpoint("手动保存") }; Button("历史与对比") { showHistory = true } }.fixedSize()
                Button("音乐对齐") { showAlignment = true }
                Spacer()
                Label("自动保存",systemImage:"checkmark.circle").font(.caption).foregroundStyle(.secondary)
                Button { store.copyText() } label: { Label("复制口播",systemImage:"doc.on.doc") }
                Menu { Button("导出 Markdown") { store.save(project:false) }; Button("保存文案工程") { store.save(project:true) } } label: { Label("导出",systemImage:"square.and.arrow.up") }.fixedSize()
            }
            TextField("为这条视频起个标题",text:draft.title).textFieldStyle(.plain).font(.system(size:24,weight:.semibold)).padding(.vertical,4)
            HStack(spacing:8) {
                MetricPill(title:"\(draft.wrappedValue.scenes.count) 个镜头",symbol:"film")
                MetricPill(title:"计划 \(draft.wrappedValue.plannedSeconds) 秒",symbol:"clock")
                MetricPill(title:"口播约 \(draft.wrappedValue.estimatedSeconds) 秒",symbol:"waveform")
            }
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Surface(padding:16) {
                        DisclosureGroup(isExpanded:$showOpenings) {
                            VStack(spacing:12) {
                                ForEach(draft.wrappedValue.openings.indices,id:\.self) { i in
                                    HStack(alignment:.top,spacing:10) {
                                        Text("\(i+1)").font(.caption.monospacedDigit()).foregroundStyle(.indigo).frame(width:22,height:22).background(.indigo.opacity(0.08),in:Circle())
                                        TextField("开头",text:draft.openings[i],axis:.vertical).textFieldStyle(.roundedBorder)
                                        Button("采用") { guard !draft.wrappedValue.scenes.isEmpty else { return }; draft.wrappedValue.scenes[0].spoken = draft.wrappedValue.openings[i] }
                                    }
                                }
                            }.padding(.top,12)
                        } label: { Label("开头方案 · \(draft.wrappedValue.openings.count)",systemImage:"lightbulb").font(.callout.weight(.medium)) }
                    }
                    ForEach(Array(draft.wrappedValue.scenes.enumerated()),id:\.element.id) { index, sceneValue in
                        if let i = draft.wrappedValue.scenes.firstIndex(where:{ $0.id == sceneValue.id }) {
                            sceneEditor(draft.scenes[i],number:index+1)
                        }
                    }
                }.padding(.trailing,4).padding(.bottom,4)
            }
        }.frame(minWidth:390,maxWidth:.infinity,maxHeight:.infinity,alignment:.top).disabled(store.busy)
    }
    func sceneEditor(_ scene:Binding<ScriptScene>,number:Int) -> some View {
        Surface {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text(String(format:"%02d",number)).font(.system(size:14,weight:.semibold,design:.monospaced)).foregroundStyle(.indigo).frame(width:34,height:30).background(.indigo.opacity(0.08),in:RoundedRectangle(cornerRadius:8))
                    Text(number == 1 ? "开场" : "镜头 \(number)").font(.headline)
                    Spacer()
                    Menu("AI 改写") { ForEach(["更精简","更自然口语","强化吸引力","更有故事感"],id:\.self) { mode in Button(mode) { do { let (config,key) = try ai.snapshot(); store.rewrite(sceneID:scene.wrappedValue.id,mode:mode,config:config,key:key) } catch { store.message = error.localizedDescription } } } }.fixedSize()
                    Stepper("\(scene.wrappedValue.seconds) 秒",value:scene.seconds,in:1...600).fixedSize().font(.callout).foregroundStyle(.secondary)
                }
                VStack(alignment:.leading,spacing:6) {
                    FieldCaption(title:"口播")
                    InsetTextEditor(text:scene.spoken,accessibilityLabel:"口播文字").frame(height:90).clipShape(RoundedRectangle(cornerRadius:7)).overlay(RoundedRectangle(cornerRadius:7).strokeBorder(.primary.opacity(0.10)))
                }
                VStack(alignment:.leading,spacing:6) { FieldCaption(title:"画面与镜头"); TextField("画面与镜头建议",text:scene.visual,axis:.vertical).textFieldStyle(.roundedBorder) }
                VStack(alignment:.leading,spacing:6) { FieldCaption(title:"屏幕文字"); TextField("屏幕文字",text:scene.caption,axis:.vertical).textFieldStyle(.roundedBorder) }
            }
        }
    }
}
