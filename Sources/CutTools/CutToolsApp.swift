import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

@main struct CutToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var ai = AIModelStore()
    @StateObject private var workspace = Workspace()
    var body: some Scene { WindowGroup("CutTools · 视频整理与交付") { ContentView().environmentObject(workspace).environmentObject(ai).frame(minWidth: 1050, minHeight: 700) }; SwiftUI.Settings { AISettingsView().environmentObject(ai) } }
}

struct ContentView: View {
    @EnvironmentObject var models: AIModelStore
    @EnvironmentObject var w: Workspace
    @State private var tab = "卡点"
    @StateObject private var beats = BeatStore()
    @StateObject private var copy = CopyStore()
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { if tab != "卡点" && tab != "文案" { sidebar.frame(width: 220); Divider() }; center.frame(minWidth: 450, maxWidth: .infinity, maxHeight: .infinity, alignment: .top); if tab != "卡点" && tab != "文案" { Divider(); inspector.frame(width: 290) } }.frame(maxHeight: .infinity)
            Divider(); queue.frame(height: 120)
            HStack { Text(w.message).lineLimit(1); Spacer(); Text(w.ffmpeg == nil ? "FFmpeg 未找到" : "FFmpeg 已连接 · AI：\(models.config.provider.title)").foregroundStyle(.secondary) }.font(.caption).padding(8)
        }.onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers { _ = p.loadObject(ofClass: URL.self) { url, _ in if let url { Task { @MainActor in if tab == "卡点" { beats.load(url) } else { w.importURL(url) } } } } }; return true
        }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("素材").font(.title2.bold()); Text("拖放文件到窗口，或选择导入").font(.caption).foregroundStyle(.secondary)
            Button("添加视频") { w.choose("视频") }.keyboardShortcut("o")
            Button("导入中文字幕") { w.choose("中文") }
            Button("导入英文字幕") { w.choose("英文") }
            Divider()
            Text("视频 · \(w.videoURLs.count)").font(.headline)
            List(selection: $w.selectedVideo) { ForEach(w.videoURLs, id: \.self) { url in Text(url.lastPathComponent).lineLimit(1).tag(url as URL?) } }.listStyle(.sidebar)
            Text("中文字幕  \(w.chinese.count) 条").font(.caption)
            Text("英文字幕  \(w.english.count) 条").font(.caption)
        }.padding(16)
    }
    var center: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) { Text("音乐卡点").tag("卡点"); Text("从零写稿").tag("文案"); Text("字幕整理").tag("字幕"); Text("视频预览").tag("视频"); Text("编辑字幕").tag("编辑"); Text("创作与检查").tag("创作") }.pickerStyle(.segmented).frame(maxWidth: .infinity)
            if tab == "卡点" { BeatView(store: beats) } else if tab == "文案" { CopywritingView(store: copy) } else if tab == "字幕" { subtitleView } else if tab == "编辑" { editorView } else if tab == "创作" { StudioView() } else { videoView }
        }.padding(18)
    }
    var subtitleView: some View {
        VStack(alignment: .leading) {
            HStack { Text("双语匹配").font(.title2.bold()); Spacer(); Text("\(w.matched.filter { $0.1 }.count) 条待确认").foregroundStyle(.orange) }
            Text("根据时间匹配字幕；橙色标记需要检查。").font(.caption).foregroundStyle(.secondary)
            List { ForEach(Array(w.matched.enumerated()), id: \.offset) { _, item in HStack(alignment: .top) { Text(SRT.stamp(item.0.start)).monospacedDigit().font(.caption).foregroundStyle(.secondary).frame(width: 95, alignment: .leading); Text(item.0.text).textSelection(.enabled); Spacer(); if item.1 { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }.padding(.vertical, 4) } }
            DisclosureGroup("检查结果 · \(w.issues.count) 项") { ScrollView { VStack(alignment: .leading) { ForEach(w.issues, id: \.self) { Text($0).font(.caption) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100) }
            HStack { Text("整体偏移（秒）"); TextField("秒", value: $w.settings.offset, format: .number).frame(width: 80); Button("应用") { w.shift() }; Spacer(); Toggle("中文在上", isOn: $w.settings.chineseFirst).toggleStyle(.checkbox) }
        }
    }
    var editorView: some View {
        VStack(alignment: .leading) {
            Text("编辑原始字幕").font(.title2.bold())
            Text("修改文字或秒数后，双语匹配会自动更新。").font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading) {
            if let url = w.selectedVideo { StudioPlayer(url: url).frame(maxWidth: .infinity, maxHeight: .infinity); Text(url.lastPathComponent).font(.headline) } else { ContentUnavailableView("选择视频", systemImage: "film", description: Text("从左侧添加视频以预览")) }
            HStack { Button("检测内部黑边") { w.detectCrop() }; if !w.cropSuggestion.isEmpty { Text(w.cropSuggestion).font(.caption.monospaced()); Button("应用建议") { w.settings.crop = w.cropSuggestion } }; if !w.settings.crop.isEmpty { Button("清除裁切") { w.settings.crop = "" } } }
        }
    }
    var inspector: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) {
            Text("交付设置").font(.title2.bold())
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
            HStack { Button("预览 10 秒") { w.run(preview: true) }.disabled(w.isRunning); Button("开始交付") { w.run() }.keyboardShortcut(.return, modifiers: .command).disabled(w.isRunning) }
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
