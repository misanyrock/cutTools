import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

@main struct CutToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var ai = AIModelStore()
    @StateObject private var workspace = Workspace()
    var body: some Scene { WindowGroup("CutTools · 视频整理与交付") { ContentView().environmentObject(workspace).environmentObject(ai).frame(minWidth: 1180, minHeight: 760).tint(.indigo) }.defaultSize(width:1320,height:860); SwiftUI.Settings { AISettingsView().environmentObject(ai) } }
}

struct ContentView: View {
    @EnvironmentObject var models: AIModelStore
    @EnvironmentObject var w: Workspace
    @State private var tab: String? = "卡点"
    @State private var queueExpanded = false
    @StateObject private var beats = BeatStore()
    @StateObject private var copy = CopyStore()
    var body: some View {
        NavigationSplitView {
            VStack(spacing:0) {
                HStack(spacing:10) {
                    if let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let icon = NSImage(contentsOf:url) { Image(nsImage:icon).resizable().frame(width:36,height:36) }
                    VStack(alignment:.leading,spacing:3) { Text("CutTools").font(.system(size:18,weight:.bold)); Text("创作与交付").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }.padding(.horizontal,18).padding(.top,20).padding(.bottom,24)
                List(selection:$tab) {
                    Section("创作") {
                        Label("音乐卡点",systemImage:"waveform").tag("卡点")
                        Label("从零写稿",systemImage:"square.and.pencil").tag("文案")
                    }
                    Section("整理与交付") {
                        Label("双语字幕",systemImage:"captions.bubble").tag("字幕")
                        Label("视频预览",systemImage:"play.rectangle").tag("视频")
                        Label("字幕编辑",systemImage:"text.alignleft").tag("编辑")
                        Label("工具箱",systemImage:"square.grid.2x2").tag("创作")
                    }
                }.listStyle(.sidebar)
                Divider().padding(.horizontal,14)
                VStack(alignment:.leading,spacing:10) {
                    SettingsLink { Label("模型与偏好设置",systemImage:"gearshape") }.buttonStyle(.plain)
                    Text(models.config.provider.title).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.leading).padding(18)
            }.navigationSplitViewColumnWidth(min:180,ideal:200,max:230)
        } detail: {
            VStack(spacing:0) {
                HStack(spacing:0) {
                    if tab != "卡点" && tab != "文案" { sidebar.frame(width:170); Divider() }
                    center.frame(minWidth:360,maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
                    if tab != "卡点" && tab != "文案" { Divider(); inspector.frame(width:260) }
                }.frame(maxHeight:.infinity)
                if queueExpanded || w.isRunning { Divider(); queue.frame(height:120).background(.regularMaterial) }
                Divider()
                HStack(spacing:10) {
                    Circle().fill(w.isRunning || beats.busy || copy.busy ? Color.orange : Color.indigo).frame(width:6,height:6)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(statusText)
                    Spacer(minLength:10)
                    Button { queueExpanded.toggle() } label: { Label("任务 \(w.jobs.count)",systemImage:"tray.full") }.buttonStyle(.plain).font(.caption)
                    Divider().frame(height:12)
                    Text(w.ffmpeg == nil ? "FFmpeg 未配置" : "FFmpeg 就绪").font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal,20).padding(.vertical,10)
            }.background(.primary.opacity(0.025))
        }
        .navigationTitle("CutTools")
        .onChange(of:w.jobs.count) { _, count in if count > 0 { queueExpanded = true } }
        .onDrop(of:[.fileURL],isTargeted:nil) { providers in
            if tab == "文案" { return false }
            for provider in providers { _ = provider.loadObject(ofClass:URL.self) { url,_ in if let url { Task { @MainActor in if tab == "卡点" { beats.load(url) } else { w.importURL(url) } } } } }
            return true
        }
    }
    var statusText: String {
        if tab == "卡点" { return beats.message }
        if tab == "文案" { return copy.message }
        return w.message
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("素材库").font(.headline); Text("拖放文件到窗口，或选择导入").font(.caption).foregroundStyle(.secondary)
            Button("添加视频") { w.choose("视频") }.keyboardShortcut("o")
            Button("导入中文字幕") { w.choose("中文") }
            Button("导入英文字幕") { w.choose("英文") }
            Divider()
            Text("视频 · \(w.videoURLs.count)").font(.headline)
            List(selection: $w.selectedVideo) { ForEach(w.videoURLs, id: \.self) { url in Text(url.lastPathComponent).lineLimit(1).tag(url as URL?) } }.listStyle(.sidebar)
            Text("中文字幕  \(w.chinese.count) 条").font(.caption)
            Text("英文字幕  \(w.english.count) 条").font(.caption)
        }.padding(14)
    }
    var center: some View {
        VStack(alignment:.leading,spacing:20) {
            if tab == "卡点" { BeatView(store:beats) }
            else if tab == "文案" { CopywritingView(store:copy) }
            else if tab == "字幕" { subtitleView }
            else if tab == "编辑" { editorView }
            else if tab == "创作" { StudioView() }
            else { videoView }
        }.padding(24).controlSize(.regular)
    }
    var subtitleView: some View {
        VStack(alignment: .leading) {
            HStack { WorkspaceHeader(title:"双语字幕",subtitle:"按时间匹配中英文，逐条确认后导出。",symbol:"captions.bubble"); Spacer(); MetricPill(title:"\(w.matched.filter { $0.1 }.count) 条待确认",symbol:"exclamationmark.circle") }
            List { ForEach(Array(w.matched.enumerated()), id: \.offset) { _, item in HStack(alignment: .top) { Text(SRT.stamp(item.0.start)).monospacedDigit().font(.caption).foregroundStyle(.secondary).frame(width: 95, alignment: .leading); Text(item.0.text).textSelection(.enabled); Spacer(); if item.1 { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }.padding(.vertical, 4) } }
            DisclosureGroup("检查结果 · \(w.issues.count) 项") { ScrollView { VStack(alignment: .leading) { ForEach(w.issues, id: \.self) { Text($0).font(.caption) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
            HStack { Text("整体偏移（秒）"); TextField("秒", value: $w.settings.offset, format: .number).frame(width: 80); Button("应用") { w.shift() }; Spacer(); Toggle("中文在上", isOn: $w.settings.chineseFirst).toggleStyle(.checkbox) }
        }
    }
    var editorView: some View {
        VStack(alignment: .leading) {
            WorkspaceHeader(title:"字幕编辑",subtitle:"修改文字与时间，让每一句都落在正确的位置。",symbol:"text.alignleft")
            TabView {
                cueEditor($w.chinese).tabItem { Text("中文") }
                cueEditor($w.english).tabItem { Text("英文") }
            }
        }
    }
    func cueEditor(_ cues: Binding<[Cue]>) -> some View {
        List {
            ForEach(cues) { $cue in
                VStack(alignment: .leading) {
                    HStack { Text("开始"); TextField("秒", value: $cue.start, format: .number).frame(width: 80); Text("结束"); TextField("秒", value: $cue.end, format: .number).frame(width: 80) }
                    TextField("字幕文字", text: $cue.text, axis: .vertical)
                }.padding(.vertical, 3).contextMenu {
                    Button("与下一条合并") { merge(cues, id: cue.id) }
                    Button("从中点拆分") { split(cues, id: cue.id) }
                    Button("删除字幕") { cues.wrappedValue.removeAll { $0.id == cue.id } }
                }
            }
        }
    }
    func merge(_ cues: Binding<[Cue]>, id: UUID) {
        guard let i = cues.wrappedValue.firstIndex(where: { $0.id == id }), i+1 < cues.wrappedValue.count else { return }
        var items = cues.wrappedValue
        items[i].end = max(items[i].end, items[i+1].end)
        items[i].text += "\n" + items[i+1].text
        items.remove(at: i+1); cues.wrappedValue = items
    }
    func split(_ cues: Binding<[Cue]>, id: UUID) {
        guard let i = cues.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
        var items = cues.wrappedValue; let c = items[i]
        guard c.end > c.start else { return }
        let chars = Array(c.text), midpoint = chars.count / 2, time = (c.start+c.end)/2
        items[i].end = time; items[i].text = String(chars.prefix(midpoint))
        items.insert(Cue(start: time,end: c.end,text: String(chars.dropFirst(midpoint)),sourceNumber: c.sourceNumber+1),at: i+1)
        cues.wrappedValue = items
    }
    var videoView: some View {
        VStack(alignment: .leading,spacing:18) {
            WorkspaceHeader(title:"视频预览",subtitle:"检查画面，准备目标比例与交付规格。",symbol:"play.rectangle")
            if let url = w.selectedVideo { StudioPlayer(url: url).frame(maxWidth: .infinity, maxHeight: .infinity); Text(url.lastPathComponent).font(.headline) } else { ContentUnavailableView("选择视频", systemImage: "film", description: Text("从左侧添加视频以预览")) }
            HStack { Button("检测内部黑边") { w.detectCrop() }; if !w.cropSuggestion.isEmpty { Text(w.cropSuggestion).font(.caption.monospaced()); Button("应用建议") { w.settings.crop = w.cropSuggestion } }; if !w.settings.crop.isEmpty { Button("清除裁切") { w.settings.crop = "" } } }
        }
    }
    var inspector: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Label("交付设置",systemImage:"square.and.arrow.up").font(.headline)
            Text("画面").font(.headline)
            Picker("适配", selection: $w.settings.mode) { ForEach(["保留画面", "裁切填满", "沿用素材比例"], id: \.self) { Text($0) } }
            if w.settings.mode != "沿用素材比例" { HStack { TextField("宽", value: $w.settings.width, format: .number); Text("×"); TextField("高", value: $w.settings.height, format: .number) } }
            if w.settings.mode == "保留画面" { Picker("背景", selection: $w.settings.background) { Text("黑色").tag("黑色"); Text("模糊").tag("模糊") } }
            if w.settings.mode == "裁切填满" { Text("水平位置"); Slider(value: $w.settings.position) }
            Picker("编码", selection: $w.settings.codec) { Text("H.264").tag("H.264"); Text("HEVC").tag("HEVC") }
            Divider(); Text("交付内容").font(.headline)
            Toggle("中、英及双语 SRT", isOn: $w.settings.subtitles)
            Toggle("无字幕视频", isOn: $w.settings.video)
            Toggle("烧录双语字幕", isOn: $w.settings.burned)
            Text("烧录需要支持 libass 的 FFmpeg。" ).font(.caption).foregroundStyle(.secondary)
            Divider(); TextField("预设名称", text: $w.settings.name)
            HStack { Button("保存预设") { w.savePreset() }; Menu("载入预设") { ForEach(w.presetNames, id: \.self) { name in Button(name) { w.loadPreset(name) } } } }
            Button(w.output?.path ?? "选择保存目录…") { w.choose("目录") }.lineLimit(1)
            HStack { Button("预览 10 秒") { w.run(preview: true) }.disabled(w.isRunning); Button("开始交付") { w.run() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(w.isRunning) }
            if w.isRunning { Button("取消任务") { w.cancel() } }
        }.padding(16) }
    }
    var queue: some View {
        VStack(alignment: .leading, spacing: 4) { HStack { Text("任务队列").font(.headline); Spacer(); Text("\(w.jobs.count) 项").foregroundStyle(.secondary) }; if w.jobs.isEmpty { Text("导出任务会显示在这里").foregroundStyle(.secondary).font(.caption) } else { ScrollView { ForEach(w.jobs) { job in HStack { Text(job.title).lineLimit(1); Spacer(); Text(job.status).lineLimit(2).foregroundStyle(job.status.hasPrefix("失败") ? .red : .secondary) }.font(.caption) } } } }.padding(12)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { if let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"), let icon = NSImage(contentsOf:url) { NSApp.applicationIconImage = icon }; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
}
