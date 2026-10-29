import SwiftUI
import AVKit

struct BeatView: View {
    @ObservedObject var store: BeatStore
    @EnvironmentObject var w: Workspace
    @State private var confirmAnalyze = false
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack {
                WorkspaceHeader(title:"音乐卡点",subtitle:store.source?.lastPathComponent ?? "找到节奏，安排每一次画面切换。",symbol:"waveform")
                Spacer()
                Button { store.openSession() } label: { Label("载入标记",systemImage:"folder") }.disabled(store.busy)
                Button { store.choose() } label: { Label("导入音乐",systemImage:"plus") }.buttonStyle(.borderedProminent).disabled(store.busy)
            }
            if store.source != nil { analysisControls }
            if store.duration > 0 {
                Surface(padding:16) {
                    VStack(spacing:14) {
                        HStack(spacing:12) {
                            Button { store.togglePlay() } label: { Image(systemName:"playpause.fill").frame(width:24,height:24) }.buttonStyle(.borderedProminent).help("播放 / 暂停")
                            Text(SRT.stamp(store.currentTime)).font(.system(size:20,weight:.medium,design:.monospaced))
                            Text("/ \(SRT.stamp(store.duration))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.add() } label: { Label("补一个点",systemImage:"plus.diamond") }.keyboardShortcut("m",modifiers:[]).disabled(store.busy).help("在播放位置添加标记 · M")
                            Image(systemName:"minus.magnifyingglass").foregroundStyle(.secondary)
                            Slider(value:$store.zoom,in:1...12).frame(width:100).accessibilityLabel("波形缩放")
                            Image(systemName:"plus.magnifyingglass").foregroundStyle(.secondary)
                        }
                        if store.waveform.isEmpty { Button("恢复波形（保留标记）") { store.analyze(ffmpeg:w.ffmpeg,preserveMarkers:true) }.disabled(store.busy) }
                        waveform.frame(height:170).clipShape(RoundedRectangle(cornerRadius:9))
                        HStack {
                            Label("强拍 / 节拍",systemImage:"diamond.fill").foregroundStyle(.orange)
                            Label("手动标记",systemImage:"diamond.fill").foregroundStyle(.green)
                            Spacer(); Text("点击波形定位 · 点击时间试听 · M 补点").foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
                HStack(spacing:8) {
                    Text("标记列表").font(.headline)
                    MetricPill(title:"已启用 \(store.markers.filter(\.enabled).count)",symbol:"checkmark.circle")
                    Spacer()
                    Picker("显示",selection:$store.filter) { ForEach(BeatFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth:430)
                    Toggle("仅启用",isOn:$store.enabledOnly).toggleStyle(.checkbox)
                    Menu("批量保留") {
                        Button("仅启用强拍") { store.keepOnly(.strong) }
                        Button("仅启用能量转折") { store.keepOnly(.transition) }
                        Button("仅启用强拍与转折") { store.keepOnly(.highlights) }
                        Button("仅启用手动标记") { store.keepOnly(.manual) }
                        Button("启用全部") { store.keepOnly(.all) }
                    }.fixedSize()
                    Button { store.undoSelection() } label: { Image(systemName:"arrow.uturn.backward") }.disabled(store.selectionUndo == nil).help("撤销上次批量保留")
                }.disabled(store.busy)
                markerList
                HStack(spacing:12) {
                    Text("显示 \(store.visibleMarkers.count) 项；导出全部已启用标记。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("帧率",selection:$store.fps) { ForEach([24,25,30,50,60],id:\.self) { Text("\($0) fps").tag($0) } }.frame(width:120)
                    Menu { Button("导出 CSV 时间表") { store.save(kind:"csv") }; Button("保存标记工程") { store.save(kind:"json") } } label: { Label("更多导出",systemImage:"ellipsis") }.fixedSize()
                    Button { store.save(kind:"fcpxml") } label: { Label("导出 FCPXML",systemImage:"square.and.arrow.up") }.buttonStyle(.borderedProminent)
                }.disabled(store.busy)
                Text("强拍与转折为算法候选；FCPXML 将新建带音乐与标记的时间线，导入后请检查对齐。").font(.caption).foregroundStyle(.secondary)
            } else if !store.busy { emptyState }
            if store.busy { HStack { ProgressView().controlSize(.small); Text(store.message).foregroundStyle(.secondary); Spacer(); Button("取消分析") { store.cancel() } }.font(.callout) }
        }.onDisappear { store.player.pause() }
        .confirmationDialog("重新分析会替换全部自动与手动标记",isPresented:$confirmAnalyze) { Button("替换并重新分析",role:.destructive) { store.analyze(ffmpeg:w.ffmpeg) } }
    }
    var analysisControls: some View {
        HStack(spacing:14) {
            Text("检测强度").font(.callout.weight(.medium))
            Slider(value:$store.sensitivity,in:0.3...2).frame(width:140).disabled(store.busy)
            Text("越高，候选越少").font(.caption).foregroundStyle(.secondary)
            Button(store.markers.isEmpty ? "分析节拍" : "重新分析") { if store.markers.isEmpty { store.analyze(ffmpeg:w.ffmpeg) } else { confirmAnalyze = true } }.disabled(store.busy)
            Spacer()
            if let bpm = store.bpm { MetricPill(title:"约 \(Int(bpm.rounded())) BPM",symbol:"metronome") }
        }
    }
    var markerList: some View {
        List {
            ForEach(store.visibleMarkers) { marker in
                HStack(spacing:16) {
                    Toggle(isOn:Binding(get:{ store.markers.first(where:{ $0.id == marker.id })?.enabled ?? false },set:{ value in if let i = store.markers.firstIndex(where:{ $0.id == marker.id }) { store.markers[i].enabled = value } })) { EmptyView() }.labelsHidden().toggleStyle(.checkbox)
                    Button { store.seek(max(0,marker.time-0.3)); store.player.play() } label: { Label(SRT.stamp(marker.time),systemImage:"play.circle").font(.system(size:13,weight:.medium,design:.monospaced)) }.buttonStyle(.plain)
                    Text(marker.kind).font(.caption.weight(.medium)).foregroundStyle(marker.kind == "强拍候选" ? Color.orange : Color.secondary).padding(.horizontal,9).padding(.vertical,4).background(.primary.opacity(0.04),in:Capsule())
                    Spacer()
                    HStack(spacing:8) {
                        Button { store.shift(marker.id,by:-1/Double(store.fps)) } label: { Image(systemName:"chevron.left") }.help("提前 1 帧")
                        Text("1 帧").font(.caption).foregroundStyle(.secondary)
                        Button { store.shift(marker.id,by:1/Double(store.fps)) } label: { Image(systemName:"chevron.right") }.help("延后 1 帧")
                    }
                    Button { store.markers.removeAll { $0.id == marker.id } } label: { Image(systemName:"trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("删除标记")
                }.padding(.vertical,6).listRowSeparator(.visible)
            }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(.background,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(.primary.opacity(0.07))).disabled(store.busy)
        .overlay { if store.visibleMarkers.isEmpty { ContentUnavailableView("没有符合筛选的标记",systemImage:"line.3.horizontal.decrease.circle",description:Text("切换显示类型，或取消仅启用筛选。")) } }
    }
    var emptyState: some View {
        Surface(padding:30) {
            VStack(spacing:20) {
                Spacer()
                Image(systemName:"waveform").font(.system(size:52,weight:.light)).foregroundStyle(.indigo).frame(width:104,height:104).background(.indigo.opacity(0.07),in:RoundedRectangle(cornerRadius:27))
                Text("导入音乐，开始标记节拍").font(.system(size:24,weight:.semibold))
                Text("自动发现节拍与转折，试听后再筛选。\n也可以直接导入带音轨的视频。").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
                Button("选择音乐文件") { store.choose() }.buttonStyle(.borderedProminent).controlSize(.large)
                Text("MP3 · WAV · M4A · 视频音轨").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing:30) { Label("波形试听",systemImage:"waveform.path"); Label("逐帧微调",systemImage:"slider.horizontal.3"); Label("FCP 标记导出",systemImage:"square.and.arrow.up") }.font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
    var waveform: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                let width = max(1,geometry.size.width*store.zoom)
                Canvas { context,size in
                    for i in 0...8 {
                        let x = Double(i)/8*size.width
                        var grid = Path(); grid.move(to:CGPoint(x:x,y:0)); grid.addLine(to:CGPoint(x:x,y:size.height-22))
                        context.stroke(grid,with:.color(.primary.opacity(0.055)),lineWidth:1)
                        let time = String(SRT.stamp(store.duration*Double(i)/8).prefix(8))
                        context.draw(Text(time).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary),at:CGPoint(x:max(30,min(size.width-30,x)),y:size.height-10))
                    }
                    var wave = Path(); let count = max(1,store.waveform.count), mid = (size.height-22)/2
                    for (i,peak) in store.waveform.enumerated() {
                        let x = Double(i)/Double(count)*size.width, h = max(1,Double(peak)*(mid-10))
                        wave.move(to:CGPoint(x:x,y:mid-h)); wave.addLine(to:CGPoint(x:x,y:mid+h))
                    }
                    context.stroke(wave,with:.color(.indigo.opacity(0.72)),lineWidth:max(1,size.width/Double(count)))
                    for marker in store.visibleMarkers {
                        let x = marker.time/store.duration*size.width
                        var line = Path(); line.move(to:CGPoint(x:x,y:4)); line.addLine(to:CGPoint(x:x,y:size.height-22))
                        context.stroke(line,with:.color((marker.kind == "手动标记" ? Color.green : Color.orange).opacity(marker.enabled ? 0.9 : 0.25)),style:StrokeStyle(lineWidth:1,dash:marker.enabled ? [] : [4,3]))
                    }
                    let x = store.currentTime/store.duration*size.width
                    var playhead = Path(); playhead.move(to:CGPoint(x:x,y:0)); playhead.addLine(to:CGPoint(x:x,y:size.height-22))
                    context.stroke(playhead,with:.color(.primary),lineWidth:2)
                }.frame(width:width,height:164).background(.indigo.opacity(0.035)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { value in store.seek(value.location.x/width*store.duration) })
            }
        }
    }
}
