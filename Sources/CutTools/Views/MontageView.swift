import SwiftUI
import AVKit

struct MontageView:View {
    @ObservedObject var store:MontageStore
    @ObservedObject var beats:BeatStore
    @EnvironmentObject var w:Workspace
    let openMusic:() -> Void
    var selected:MontageSlot? { store.project.slots.first { $0.id == store.selectedSlot } }
    var selectedAsset:MontageAsset? { store.project.assets.first { $0.id == selected?.assetID } }
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { WorkspaceHeader(title:"卡点排镜",subtitle:"按已启用卡点安排素材，锁定满意的镜头后再导出。",symbol:"film.stack"); Spacer(); Button("载入排镜") { store.open() }.disabled(store.busy); Button("导入视频") { store.chooseAssets() }.buttonStyle(.borderedProminent).disabled(store.busy) }
            HStack { Text(beats.source?.lastPathComponent ?? "尚未选择音乐").lineLimit(1).foregroundStyle(.secondary); Button("选择音乐与卡点") { openMusic() }; Spacer(); Text("起点"); TextField("秒",value:$store.rangeStart,format:.number).frame(width:65); Text("结束"); TextField("秒",value:$store.rangeEnd,format:.number).frame(width:65); Stepper("最短镜头 \(store.minimumShot, specifier:"%.1f") 秒",value:$store.minimumShot,in:0.1...10,step:0.1); Button("按卡点排镜") { store.build(beats:beats) }.disabled(beats.duration <= 0 || store.project.assets.isEmpty) }.disabled(store.busy)
            HStack(alignment:.top,spacing:16) {
                Surface(padding:12) {
                    VStack(alignment:.leading,spacing:12) {
                        Text("素材顺序 · \(store.project.assets.count)").font(.headline)
                        Text("按导入顺序轮换；可重复使用同一素材，只选择足够长的素材。").font(.caption).foregroundStyle(.secondary)
                        List { ForEach(Array(store.project.assets.enumerated()),id:\.element.id) { i,asset in VStack(alignment:.leading,spacing:6) { Text(asset.url.lastPathComponent).lineLimit(2); HStack { Text("\(asset.duration,specifier:"%.1f") 秒").font(.caption).foregroundStyle(.secondary); Spacer(); Button { if i > 0 { store.project.assets.swapAt(i,i-1) } } label: { Image(systemName:"arrow.up") }.disabled(i == 0); Button { store.removeAsset(asset.id) } label: { Image(systemName:"trash") } } }.padding(.vertical,4) } }.listStyle(.plain)
                    }.disabled(store.busy)
                }.frame(width:235)
                VStack(alignment:.leading,spacing:12) {
                    if let selectedAsset,let selected { StudioPlayer(url:selectedAsset.url,seekTime:selected.sourceIn).frame(height:180).clipShape(RoundedRectangle(cornerRadius:10)) }
                    if store.project.slots.isEmpty { ContentUnavailableView("把素材排到音乐里",systemImage:"film.stack",description:Text("选择音乐范围并导入素材，再按卡点生成镜头。")) }
                    else {
                        Text("\(store.project.slots.count) 个镜头 · \(store.project.duration,specifier:"%.2f") 秒 · \(store.project.fps) fps").font(.headline)
                        List(selection:$store.selectedSlot) {
                            ForEach($store.project.slots) { $slot in
                                VStack(alignment:.leading,spacing:8) {
                                    HStack { Text("\(SRT.stamp(slot.start)) · \(slot.duration,specifier:"%.2f") 秒").font(.caption.monospacedDigit()); Spacer(); Toggle("锁定",isOn:$slot.locked).toggleStyle(.checkbox) }
                                    HStack { Picker("素材",selection:$slot.assetID) { Text("未分配").tag(nil as UUID?); ForEach(store.project.assets) { asset in Text(asset.url.lastPathComponent).tag(Optional(asset.id)) } }; Text("入点"); TextField("秒",value:$slot.sourceIn,format:.number).frame(width:65); Button("预览") { store.selectedSlot = slot.id } }
                                    if let asset = store.project.assets.first(where:{ $0.id == slot.assetID }),slot.sourceIn+slot.duration > asset.duration || slot.sourceIn < 0 { Text("超出素材长度，请调整入点或替换素材").font(.caption).foregroundStyle(.orange) }
                                }.tag(slot.id).padding(.vertical,5)
                            }
                        }.listStyle(.plain).disabled(store.busy)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            HStack { Text(store.message).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled); Spacer(); if store.busy { ProgressView().controlSize(.small); Button("取消") { store.cancel() } } else { Menu("导出") { Button("FCPXML 可编辑时间线") { store.save(xml:true) }; Button("保存排镜工程") { store.save(xml:false) }; Button("渲染前 10 秒预览") { store.render(ffmpeg:w.ffmpeg,preview:true) }; Button("渲染完整 MP4") { store.render(ffmpeg:w.ffmpeg,preview:false) } }.fixedSize() } }
            Text("默认保留音乐、关闭素材原声；成片统一 1920×1080 保留画面。锁定镜头不会被自动排镜替换。FCPXML 需在目标 FCP 中验证，并保持原素材可访问。").font(.caption).foregroundStyle(.secondary)
        }.onAppear { if store.project.slots.isEmpty, beats.duration > 0 { store.rangeEnd = min(store.rangeEnd,beats.duration) } }.onDrop(of:[.fileURL],isTargeted:nil) { providers in
            guard !store.busy else { return false }
            Task { @MainActor in var urls:[URL] = []; for p in providers { let url:URL? = await withCheckedContinuation { c in _ = p.loadObject(ofClass:URL.self) { url,_ in c.resume(returning:url) } }; if let url { urls.append(url) } }; store.importAssets(urls) }; return true
        }
    }
}
