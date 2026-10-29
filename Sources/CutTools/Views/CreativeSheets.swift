import SwiftUI
import AppKit

struct RewriteComparisonView: View {
    @ObservedObject var store:CopyStore
    let proposal:RewriteProposal
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            WorkspaceHeader(title:"局部改写对比",subtitle:proposal.mode+" · 确认后只替换当前镜头",symbol:"text.badge.star")
            HStack(alignment:.top,spacing:16) { column("原文",proposal.original); column("改写建议",proposal.replacement) }
            Text("请核对事实与表达；段落时长保持原值，应用后可在版本历史恢复。").font(.caption).foregroundStyle(.secondary)
            HStack { Button("保留原文") { dismiss() }; Spacer(); Button("应用这段改写") { store.applyRewrite(proposal); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width:850,height:590)
    }
    func column(_ title:String,_ scene:ScriptScene) -> some View {
        Surface { ScrollView { VStack(alignment:.leading,spacing:14) { Text(title).font(.headline); FieldCaption(title:"口播"); Text(scene.spoken).textSelection(.enabled); Divider(); FieldCaption(title:"画面"); Text(scene.visual).textSelection(.enabled); FieldCaption(title:"屏幕文字"); Text(scene.caption).textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading) } }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}
struct CopyHistoryView:View {
    @ObservedObject var store:CopyStore
    @State private var selected:UUID?
    @Environment(\.dismiss) private var dismiss
    var version:CopyVersion? { store.versions.first { $0.id == selected } }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            WorkspaceHeader(title:"版本历史",subtitle:"保留最近 30 个版本；恢复前会先保存当前稿件",symbol:"clock.arrow.circlepath")
            HStack(alignment:.top,spacing:16) {
                List(selection:$selected) { ForEach(store.versions.reversed()) { version in VStack(alignment:.leading,spacing:4) { Text(version.label); Text(version.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary) }.tag(version.id) } }.frame(width:230)
                Surface { ScrollView { VStack(alignment:.leading,spacing:10) { Text("历史版本").font(.headline); Text(version?.draft.spokenText ?? "选择一个版本查看").textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading) } }
                Surface { ScrollView { VStack(alignment:.leading,spacing:10) { Text("当前稿件").font(.headline); Text(store.draft?.spokenText ?? "暂无文案").textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading) } }
            }
            HStack { Button("关闭") { dismiss() }; Spacer(); Button("恢复选中版本") { if let version { store.restore(version); dismiss() } }.buttonStyle(.borderedProminent).disabled(version == nil || store.busy) }
        }.padding(24).frame(width:980,height:650)
    }
}
struct TemplateNameView:View {
    @ObservedObject var store:CopyStore
    @State private var name = ""
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Text("保存个人创作模板").font(.title2.bold())
            Text("保存受众、目的、风格、时长与写作规则。当前主题和事实素材不会存进模板。").foregroundStyle(.secondary)
            TextField("模板名称",text:$name).textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("保存模板") { do { try store.saveTemplate(name:name); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width:460)
    }
}
struct MusicAlignmentView:View {
    @ObservedObject var copy:CopyStore
    @ObservedObject var beats:BeatStore
    @Environment(\.dismiss) private var dismiss
    @State private var start = 0.0
    @State private var end = 60.0
    @State private var anchor = 20.0
    @State private var keyScene = 1
    @State private var breath = 0.5
    @State private var plan:MusicAlignment?
    @State private var message = "重点段落对齐锚点，其他段落按原时长比例安排，并靠近已启用卡点"
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            WorkspaceHeader(title:"文案与音乐对齐",subtitle:beats.source?.lastPathComponent ?? "请先在音乐卡点中导入并分析音乐",symbol:"waveform.and.mic")
            if let draft = copy.draft,beats.duration > 0 {
                HStack { Text("音乐起点"); TextField("秒",value:$start,format:.number).frame(width:75); Text("结束"); TextField("秒",value:$end,format:.number).frame(width:75); Text("留白"); Slider(value:$breath,in:0...3,step:0.1).frame(width:100); Text(String(format:"%.1f 秒",breath)) }
                HStack {
                    Picker("重点段落",selection:$keyScene) { ForEach(draft.scenes.indices,id:\.self) { i in Text("镜头 \(i+1)：\(draft.scenes[i].spoken.prefix(14))").tag(i) } }.frame(maxWidth:380)
                    Text("音乐锚点"); TextField("秒",value:$anchor,format:.number).frame(width:75)
                    Menu("选择卡点") { ForEach(beats.markers.filter { $0.enabled && ($0.kind == "强拍候选" || $0.kind == "能量转折候选") }) { marker in Button("\(SRT.stamp(marker.time)) · \(marker.kind)") { anchor = marker.time } } }.fixedSize()
                    Button("试听锚点") { beats.seek(max(0,anchor-1)); beats.player.play() }
                }
                HStack { Button("生成对齐方案") { create() }.buttonStyle(.borderedProminent); Text("文字安排不会自动改变配音或音乐速度；超时段落会标出。").font(.caption).foregroundStyle(.secondary) }
                if let plan {
                    List(plan.rows) { row in HStack(alignment:.top) { Text("\(SRT.stamp(row.start)) → \(SRT.stamp(row.end))").font(.caption.monospacedDigit()).frame(width:215,alignment:.leading); Text(row.phase).frame(width:85,alignment:.leading); Text(row.spoken.isEmpty ? row.visual : row.spoken).lineLimit(3); Spacer(); if row.speechWarning { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(.orange).help("按每秒 3.5 字估算，口播可能超时") }; Button("试听") { beats.seek(plan.sourceIn+row.start); beats.player.play() } } }
                    HStack {
                        Button("更新文案预计时长") { copy.applyAlignment(plan); message = copy.message }
                        Button("添加段落切点") {
                            for row in plan.rows where row.sceneID != nil {
                                let time = plan.sourceIn+row.start
                                if !beats.markers.contains(where:{ abs($0.time-time) < 0.5/Double(plan.fps) && $0.enabled }) { beats.markers.append(BeatMarker(time:time,strength:1,kind:"手动标记")) }
                            }
                            beats.markers.sort { $0.time < $1.time }; message = "已添加段落起点，不删除原标记；排镜时可选择只启用手动标记"
                        }
                        Spacer(); Menu("导出对齐结果") { Button("SRT（选段从零计时）") { save(plan,kind:"srt") }; Button("CSV 分镜表") { save(plan,kind:"csv") }; Button("FCPXML 音乐与段落标记") { save(plan,kind:"fcpxml") } }.fixedSize()
                    }
                } else { ContentUnavailableView("先试听音乐，再安排文案",systemImage:"music.note.list",description:Text("锚点可选音乐转折或强拍；留白用于空镜与换气。")) }
            } else { ContentUnavailableView("需要音乐和文案",systemImage:"waveform",description:Text("先在音乐卡点分析音乐，并准备一份文案，再打开这里。")) }
            HStack { Text(message).font(.caption).foregroundStyle(.secondary); Spacer(); Button("关闭") { beats.player.pause(); dismiss() } }
        }.padding(24).frame(width:1000,height:680).onAppear {
            end = min(beats.duration,Double(copy.draft?.plannedSeconds ?? 60)); keyScene = min(1,max(0,(copy.draft?.scenes.count ?? 1)-1))
            let candidates = beats.markers.filter { $0.enabled && $0.time > end*0.25 && $0.time < end*0.75 && ($0.kind == "强拍候选" || $0.kind == "能量转折候选") }
            anchor = candidates.max { $0.strength < $1.strength }?.time ?? end*0.4
        }.onChange(of:start) { _,_ in plan = nil }.onChange(of:end) { _,_ in plan = nil }.onChange(of:anchor) { _,_ in plan = nil }.onChange(of:keyScene) { _,_ in plan = nil }.onChange(of:breath) { _,_ in plan = nil }.onDisappear { beats.player.pause() }
    }
    func create() {
        guard let draft = copy.draft,let source = beats.source else { return }
        do { plan = try MusicAlignment.create(draft:draft,music:source,musicDuration:beats.duration,start:start,end:end,markers:beats.markers,keyScene:keyScene,anchor:anchor,breath:breath,fps:beats.fps); message = "已生成方案，橙色提示表示口播可能超时；应用与导出前请试听确认" } catch { message = error.localizedDescription }
    }
    func save(_ plan:MusicAlignment,kind:String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "文案音乐对齐."+kind
        if panel.runModal() == .OK,let url = panel.url { do { let text = kind == "srt" ? SRT.render(plan.subtitles) : (kind == "csv" ? plan.csv : plan.fcpxml); try text.write(to:url,atomically:true,encoding:.utf8); message = "已保存 \(url.lastPathComponent)，精确时间以导出为准" } catch { message = error.localizedDescription } }
    }
}
