import SwiftUI

struct SubtitleStylePanel: View {
    @EnvironmentObject var w: Workspace
    var preview: SubtitlePreview {
        SubtitlePreview(chinese: w.chinese, english: w.english, style: w.style,
                        width: w.settings.width, height: w.settings.height, chineseFirst: w.settings.chineseFirst)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("双语字幕预览").font(.title2.bold())
            if let url = w.selectedVideo {
                StudioPlayer(url: url, seekTime: w.seekTime, subtitles: preview)
                    .aspectRatio(CGFloat(max(2, w.settings.width)) / CGFloat(max(2, w.settings.height)), contentMode: .fit)
                    .frame(maxHeight: 420).background(.black)
                Text(url.lastPathComponent).font(.caption).lineLimit(1)
                Picker("定位字幕", selection: $w.seekTime) {
                    Text("视频开头").tag(0.0)
                    ForEach((w.chinese.isEmpty ? w.english : w.chinese).filter { $0.start > 0 }) { cue in
                        Text("\(SRT.stamp(cue.start))  \(cue.text.prefix(28))").tag(cue.start)
                    }
                }
            } else {
                ContentUnavailableView("添加视频以预览", systemImage: "film", description: Text("导入字幕后，播放视频即可查看排版。"))
                    .frame(height: 180)
            }
            Text("播放、拖动进度条或定位到一句字幕；修改样式后即时更新。预览使用保留画面模式，HDR 亮度以 FCP 为准。")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("中文在上", isOn: $w.settings.chineseFirst)
                .onChange(of: w.settings.chineseFirst) { _, _ in w.style.chineseBottom = nil; w.style.englishBottom = nil }
            languageStyle(chinese: true)
            languageStyle(chinese: false)
            Button("恢复自动上下位置") { w.style.chineseBottom = nil; w.style.englishBottom = nil; w.style.chineseX = nil; w.style.englishX = nil }
            Divider()
            Text("Final Cut Pro 导出设置").font(.headline)
            Picker("帧率", selection: $w.subtitleExport.frameRate) {
                ForEach(SubtitleFrameRate.allCases, id: \.self) { rate in Text("\(rate.rawValue) fps").tag(rate) }
            }
            HStack {
                Text("分辨率")
                TextField("宽", value: $w.settings.width, format: .number).accessibilityLabel("导出宽度")
                Text("×")
                TextField("高", value: $w.settings.height, format: .number).accessibilityLabel("导出高度")
                Menu("常用") {
                    Button("1920 × 1080") { w.settings.width = 1920; w.settings.height = 1080 }
                    Button("3840 × 2160") { w.settings.width = 3840; w.settings.height = 2160 }
                    Button("1080 × 1920（竖屏）") { w.settings.width = 1080; w.settings.height = 1920 }
                    Button("2160 × 3840（竖屏）") { w.settings.width = 2160; w.settings.height = 3840 }
                }.fixedSize()
            }
            Picker("颜色处理", selection: $w.subtitleExport.colorSpace) {
                ForEach(SubtitleColorSpace.allCases, id: \.self) { space in Text(space.rawValue).tag(space) }
            }
            Text("请与 FCP 项目的帧率、分辨率和资源库颜色处理一致。分辨率也用于预览和字幕烧录。")
                .font(.caption).foregroundStyle(.secondary)
            ViewThatFits {
                HStack { exportButtons }
                VStack(alignment: .leading) { exportButtons }
            }
            Text(w.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("FCPXML 包含中文、英文两条可编辑标题轨，各自保留时间与样式；导入后无需再转换字幕。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder var exportButtons: some View {
        Button("导出双轨 FCPXML") { w.exportStyled(xml: true) }.buttonStyle(.borderedProminent)
        Button("导出 ASS 样式字幕") { w.exportStyled(xml: false) }
    }
    func languageStyle(chinese: Bool) -> some View {
        let name = chinese ? "中文" : "英文"
        let size = chinese ? $w.style.chineseSize : $w.style.englishSize
        let color = chinese ? $w.style.chineseColor : $w.style.englishColor
        let bottom = Binding<Double>(get: {
            w.style.bottom(chinese: chinese, chineseFirst: w.settings.chineseFirst, bilingual: !w.chinese.isEmpty && !w.english.isEmpty)
        }, set: { if chinese { w.style.chineseBottom = $0 } else { w.style.englishBottom = $0 } })
        let x = Binding<Double>(get: { w.style.x(chinese: chinese) }, set: { if chinese { w.style.chineseX = $0 } else { w.style.englishX = $0 } })
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(name)样式").font(.headline)
            HStack { Text("字号"); Slider(value: size, in: 16...100, step: 1).accessibilityLabel("\(name)字号"); Text("\(Int(size.wrappedValue))").monospacedDigit() }
            HStack {
                ColorPicker("颜色", selection: Binding(get: { Color(nsColor: SubtitleLayout.color(color.wrappedValue)) }, set: {
                    if let rgb = NSColor($0).usingColorSpace(.sRGB) {
                        color.wrappedValue = String(format: "%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                    }
                }), supportsOpacity: false)
                TextField("HEX", text: color).frame(width: 85).accessibilityLabel("\(name)六位颜色")
            }
            HStack { Text("水平偏移"); TextField("像素", value: x, format: .number).accessibilityLabel("\(name)水平偏移"); Text("px") }
            HStack { Text("距底边"); TextField("像素", value: bottom, format: .number).accessibilityLabel("\(name)距底边"); Text("px") }
        }
    }
}
