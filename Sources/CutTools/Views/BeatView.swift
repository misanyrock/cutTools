import SwiftUI
import AVKit

struct BeatView: View {
    @ObservedObject var store: BeatStore
    @EnvironmentObject var w: Workspace
    @State private var confirmAnalyze = false
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            HStack {
                VStack(alignment: .leading,spacing: 4) { Text("音乐卡点").font(.title.bold()); Text(store.source?.lastPathComponent ?? "拖入音乐或视频，找到值得切镜头的瞬间").foregroundStyle(.secondary) }
                Spacer()
                Button("导入音乐") { store.choose() }.disabled(store.busy)
                Button("载入标记") { store.openSession() }.disabled(store.busy)
            }
            HStack {
                Text("筛选强度"); Slider(value: $store.sensitivity,in: 0.3...2).frame(width: 120).disabled(store.busy)
                Text("越高，候选越少").font(.caption).foregroundStyle(.secondary)
                Button(store.markers.isEmpty ? "分析节拍" : "重新分析") { if store.markers.isEmpty { store.analyze(ffmpeg: w.ffmpeg) } else { confirmAnalyze = true } }.disabled(store.source == nil || store.busy)
                if store.busy { ProgressView().controlSize(.small); Button("取消") { store.cancel() } }
                Spacer()
                if let bpm = store.bpm { Text("约 \(Int(bpm.rounded())) BPM · 估计值").monospacedDigit().foregroundStyle(.secondary) }
            }
            if store.duration > 0 {
                HStack { Button("播放 / 暂停") { store.togglePlay() }; Button("在播放位置补点 · M") { store.add() }.keyboardShortcut("m",modifiers: []).disabled(store.busy); Text(SRT.stamp(store.currentTime)).monospacedDigit(); Spacer(); Text("波形缩放"); Slider(value: $store.zoom,in: 1...12).frame(width: 100) }
                if store.waveform.isEmpty { Button("恢复波形（保留标记）") { store.analyze(ffmpeg: w.ffmpeg,preserveMarkers: true) }.disabled(store.busy) }
                waveform.frame(height: 150)
                HStack { Text("\(store.markers.filter(\.enabled).count) 个启用标记 / 共 \(store.markers.count) 个候选"); Spacer(); Picker("工程帧率",selection: $store.fps) { ForEach([24,25,30,50,60],id: \.self) { Text("\($0) fps").tag($0) } }.frame(width: 160) }
                HStack {
                    Picker("显示",selection: $store.filter) { ForEach(BeatFilter.allCases) { filter in Text(filter.rawValue).tag(filter) } }.pickerStyle(.segmented)
                    Toggle("仅看启用",isOn: $store.enabledOnly).toggleStyle(.checkbox)
                    Menu("批量保留") {
                        Button("仅启用强拍") { store.keepOnly(.strong) }
                        Button("仅启用能量转折") { store.keepOnly(.transition) }
                        Button("仅启用强拍与转折") { store.keepOnly(.highlights) }
                        Button("启用全部") { store.keepOnly(.all) }
                    }
                    Button("撤销批量操作") { store.undoSelection() }.disabled(store.selectionUndo == nil)
                }.disabled(store.busy)
                Text("显示 \(store.visibleMarkers.count) 项。筛选只改变列表与波形；导出使用全部已启用标记。批量保留会禁用其他类型，原标记仍保留。").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(store.visibleMarkers) { marker in
                        HStack(spacing: 10) {
                            Toggle(isOn: Binding(get: { store.markers.first(where: { $0.id == marker.id })?.enabled ?? false },set: { value in if let i = store.markers.firstIndex(where: { $0.id == marker.id }) { store.markers[i].enabled = value } })) { EmptyView() }.labelsHidden()
                            Button(SRT.stamp(marker.time)) { store.seek(max(0,marker.time-0.3)); store.player.play() }.monospacedDigit()
                            Text(marker.kind).foregroundStyle(marker.kind == "强拍候选" ? .orange : .secondary)
                            Spacer()
                            Button("−1 帧") { store.shift(marker.id,by: -1/Double(store.fps)) }
                            Button("+1 帧") { store.shift(marker.id,by: 1/Double(store.fps)) }
                            Button { store.markers.removeAll { $0.id == marker.id } } label: { Image(systemName: "trash") }.help("删除标记")
                        }.font(.callout)
                    }
                }.disabled(store.busy)
                HStack { Button("导出 FCPXML 标记") { store.save(kind: "fcpxml") }; Button("导出 CSV 时间表") { store.save(kind: "csv") }; Button("保存标记工程") { store.save(kind: "json") } }.disabled(store.busy)
                Text("FCPXML 会创建带音乐和标记的新时间线；请保持原音乐文件可访问。强拍与转折均为算法候选，不能保证是小节首拍；FCP 导入兼容性需实测。").font(.caption).foregroundStyle(.secondary)
            } else if !store.busy { ContentUnavailableView("先选一首音乐",systemImage: "waveform",description: Text("支持 MP3、WAV、M4A，也可以从视频提取音轨。")) }
            Text(store.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }.onDisappear { store.player.pause() }
        .confirmationDialog("重新分析会替换全部自动与手动标记",isPresented: $confirmAnalyze) { Button("替换并重新分析",role: .destructive) { store.analyze(ffmpeg: w.ffmpeg) } }
    }
    var waveform: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                let width = max(1,geometry.size.width*store.zoom)
                Canvas { context,size in
                    var wave = Path()
                    let count = max(1,store.waveform.count)
                    for (i,peak) in store.waveform.enumerated() { let x = Double(i)/Double(count)*size.width, h = max(1,Double(peak)*size.height*0.45); wave.move(to: CGPoint(x:x,y:size.height/2-h)); wave.addLine(to: CGPoint(x:x,y:size.height/2+h)) }
                    context.stroke(wave,with: .color(.accentColor.opacity(0.6)),lineWidth: max(1,size.width/Double(count)))
                    for m in store.visibleMarkers { let x = m.time/store.duration*size.width; var line = Path(); line.move(to: CGPoint(x:x,y:0)); line.addLine(to: CGPoint(x:x,y:size.height)); context.stroke(line,with: .color((m.kind == "手动标记" ? Color.green : Color.orange).opacity(m.enabled ? 1 : 0.3)),style: StrokeStyle(lineWidth: 1,dash: m.enabled ? [] : [4,3])) }
                    let x = store.currentTime/store.duration*size.width
                    var playhead = Path(); playhead.move(to: CGPoint(x:x,y:0)); playhead.addLine(to: CGPoint(x:x,y:size.height)); context.stroke(playhead,with: .color(.primary),lineWidth: 2)
                }.frame(width: width,height: 130).background(.quaternary.opacity(0.4)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in store.seek(value.location.x/width*store.duration) })
            }
        }
    }
}
