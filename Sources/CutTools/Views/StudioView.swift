import SwiftUI
import AVKit

struct StudioView: View {
    @EnvironmentObject var w: Workspace
    @EnvironmentObject var ai: AIModelStore
    @State private var section = "AI 字幕"
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeader(title:"工具箱",subtitle:"整理字幕、准备画面，检查交付前的细节。",symbol:"square.grid.2x2")
            Picker("工作区", selection: $section) { ForEach(["AI 字幕","字幕样式","口播粗剪","成片检查"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            if w.studioBusy { HStack { ProgressView().controlSize(.small); Text(w.studioProgress); Spacer(); Button("取消") { w.cancel() } } }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if section == "AI 字幕" { aiPanel }
                    else if section == "字幕样式" { styles }
                    else if section == "口播粗剪" { roughCut }
                    else { checks }
                }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    var aiPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地语音转字幕").font(.title2.bold())
            Text("使用本机 whisper-cli 和 ggml 模型，生成字幕后替换对应语言轨。原视频不会修改。").font(.callout).foregroundStyle(.secondary)
            HStack { TextField("whisper-cli 路径", text: $w.whisperPath); Button("选择程序") { w.pickModel(executable: true) } }
            HStack { TextField("ggml 模型文件", text: $w.whisperModel); Button("选择模型") { w.pickModel(executable: false) } }
            Picker("原语言", selection: $w.language) { Text("中文").tag("zh"); Text("英文").tag("en") }.frame(width: 200)
            Button("转写选中的视频") { w.transcribe() }.buttonStyle(.borderedProminent).disabled(w.studioBusy || w.isRunning)
            Text(w.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Link("Whisper.cpp 安装与模型说明", destination: URL(string: "https://github.com/ggml-org/whisper.cpp")!)
            Divider()
            Text("翻译与术语表").font(.title2.bold())
            Text("当前模型：\(ai.config.provider.title) · \(ai.config.model)。译文全部成功后才替换目标语言轨。在线模式会将字幕与术语表发送至 \(ai.config.baseURL)，可能计费。").font(.callout).foregroundStyle(.secondary)
            SettingsLink { Text("模型与 API Key 设置…") }
            Text("术语表：每行一项，例如 Final Cut Pro = Final Cut Pro").font(.caption)
            InsetTextEditor(text: $w.glossary, monospaced: true, accessibilityLabel: "翻译术语表").frame(height: 100).border(.secondary.opacity(0.3))
            HStack { Button("中文 → 英文") { translate(true) }; Button("英文 → 中文") { translate(false) }; Button("保存配置") { w.saveAISettings() } }.disabled(w.studioBusy || w.isRunning)
        }
    }
    func translate(_ toEnglish: Bool) {
        do { let (config,key) = try ai.snapshot(); w.translate(toEnglish:toEnglish,config:config,key:key) } catch { w.message = error.localizedDescription }
    }
    var styles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("双语字幕样式").font(.title2.bold())
            HStack { Text("中文字号"); Slider(value: $w.style.chineseSize, in: 16...100, step: 1); Text("\(Int(w.style.chineseSize))") }
            HStack { Text("英文字号"); Slider(value: $w.style.englishSize, in: 16...100, step: 1); Text("\(Int(w.style.englishSize))") }
            TextField("中文颜色（六位 HEX）", text: $w.style.chineseColor)
            TextField("英文颜色（六位 HEX）", text: $w.style.englishColor)
            Stepper("底边距离：\(w.style.bottom)", value: $w.style.bottom, in: 10...300)
            Stepper("两行间距：\(w.style.gap)", value: $w.style.gap, in: 0...80)
            VStack(spacing: CGFloat(w.style.gap)) { Text(w.chinese.first?.text ?? "每一段故事，都值得认真交付").font(.system(size: w.style.chineseSize / 2)).foregroundStyle(hexColor(w.style.chineseColor)); Text(w.english.first?.text ?? "Every story deserves a thoughtful finish.").font(.system(size: w.style.englishSize / 2)).foregroundStyle(hexColor(w.style.englishColor)) }.frame(maxWidth: .infinity).padding(24).background(.black).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack { Button("导出 ASS 样式字幕") { w.exportStyled(xml: false) }; Button("导出 FCPXML 标题") { w.exportStyled(xml: true) } }
            Text("烧录使用上述样式。FCPXML 为独立可编辑标题时间线，当前使用基础标题模板；导入兼容性仍需在 Final Cut Pro 中验证。").font(.caption).foregroundStyle(.secondary)
        }
    }
    var roughCut: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("口播粗剪").font(.title2.bold())
            Text("检测至少 1 秒的静音，保留两端呼吸余量。口头禅与相邻重复句基于现有字幕识别；候选默认不删除。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("分析选中视频") { w.analyzeVideo(quality: false) }; Button("导出已勾选的粗剪") { w.exportRoughCut() } }.disabled(w.studioBusy || w.isRunning)
            ForEach($w.cuts) { $cut in HStack { Toggle(isOn: $cut.selected) { Text(cut.reason).lineLimit(2) }; Spacer(); Button("\(SRT.stamp(cut.start)) – \(SRT.stamp(cut.end))") { w.seekTime = cut.start } }.padding(.vertical, 4) }
            if w.cuts.isEmpty { Text("分析结果会显示在这里，勾选要删除的段落后导出。对应字幕将重新计算时间。").foregroundStyle(.secondary) }
            Divider()
            Text("字幕定位").font(.headline)
            ForEach(w.chinese.isEmpty ? w.english : w.chinese) { cue in Button { w.seekTime = cue.start } label: { HStack(alignment: .top) { Text(SRT.stamp(cue.start)).monospacedDigit(); Text(cue.text).lineLimit(2); Spacer() } }.buttonStyle(.plain).padding(.vertical, 3) }
            StudioPlayer(url: w.selectedVideo, seekTime: w.seekTime).frame(height: 220)
        }
    }
    var checks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成片检查").font(.title2.bold())
            Text("检查黑场、静音、音频满幅峰值与字幕超时。结果是需要试听或观看的候选，无法自动判定剪辑意图。").font(.callout).foregroundStyle(.secondary)
            HStack { Button("检查选中视频") { w.analyzeVideo(quality: true) }.disabled(w.studioBusy || w.isRunning); Button("导出检查报告") { w.exportCheckReport() }.disabled(w.findings.isEmpty) }
            ForEach(w.findings) { finding in HStack { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange); VStack(alignment: .leading) { Text(finding.message); Text("\(SRT.stamp(finding.start)) – \(SRT.stamp(finding.end))").font(.caption.monospaced()) }; Spacer(); Button("定位") { w.seekTime = finding.start } } }
            StudioPlayer(url: w.selectedVideo, seekTime: w.seekTime).frame(height: 240)
        }
    }
    func hexColor(_ value: String) -> Color { let n = UInt64(value, radix: 16) ?? 0xFFFFFF; return Color(red: Double(n >> 16 & 255)/255, green: Double(n >> 8 & 255)/255, blue: Double(n & 255)/255) }
}
