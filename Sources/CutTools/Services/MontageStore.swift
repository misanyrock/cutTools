import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor final class MontageStore: ObservableObject {
    let defaults:UserDefaults
    @Published var project:MontageProject { didSet { defaults.set(try? JSONEncoder().encode(project),forKey:"montageProject") } }
    @Published var rangeStart = 0.0
    @Published var rangeEnd = 60.0
    @Published var minimumShot = 0.5
    @Published var busy = false
    @Published var message = "先在音乐卡点中选择切点，再导入视频素材"
    @Published var selectedSlot:UUID?
    var task:Task<Void,Never>?
    private var process:Process?
    init(defaults:UserDefaults = .standard) {
        self.defaults = defaults
        project = defaults.data(forKey:"montageProject").flatMap { try? JSONDecoder().decode(MontageProject.self,from:$0) } ?? MontageProject()
        if project.duration > 0 { rangeStart = project.sourceIn; rangeEnd = project.sourceIn+project.duration }
    }
    func chooseAssets() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importAssets(panel.urls) }
    }
    func importAssets(_ urls:[URL]) {
        guard !busy else { return }; busy = true
        task = Task { @MainActor in
            defer { busy = false }
            var errors:[String] = []
            for url in urls where !project.assets.contains(where:{ $0.url == url }) {
                do { try Task.checkCancellation(); message = "读取素材：\(url.lastPathComponent)"; let asset = try await MontageAsset.inspect(url); try Task.checkCancellation(); project.assets.append(asset) }
                catch { if Task.isCancelled { message = "已取消导入"; return }; errors.append(error.localizedDescription) }
            }
            message = errors.isEmpty ? "已导入 \(project.assets.count) 个素材；按导入顺序轮换排镜" : errors.joined(separator:"\n")
        }
    }
    func build(beats:BeatStore) {
        guard !busy,let music = beats.source,beats.duration > 0,rangeEnd <= beats.duration else { message = "请先分析音乐，并设置不超出音乐长度的范围"; return }
        do {
            if project.slots.contains(where:\.locked),project.music != music { throw StudioError.message("音乐已改变，请先解锁原镜头再重新排镜") }
            let slots = try MontagePlanner.build(assets:project.assets,markers:beats.markers,start:rangeStart,end:rangeEnd,minimum:minimumShot,fps:beats.fps,previous:project.slots)
            project.music = music; project.musicDuration = beats.duration; project.sourceIn = (rangeStart*Double(beats.fps)).rounded()/Double(beats.fps); project.slots = slots; project.duration = slots.reduce(0) { $0+$1.duration }; project.fps = beats.fps
            selectedSlot = slots.first?.id
            let missing = slots.filter { $0.assetID == nil }.count
            message = missing == 0 ? "已生成 \(slots.count) 个镜头，锁定镜头保持原样；素材原声默认不使用" : "\(missing) 个镜头没有足够长的素材，请替换或增加素材后导出"
        } catch { message = error.localizedDescription }
    }
    func removeAsset(_ id:UUID) {
        project.assets.removeAll { $0.id == id }
        for i in project.slots.indices where project.slots[i].assetID == id { project.slots[i].assetID = nil; project.slots[i].locked = false }
    }
    func save(xml:Bool) {
        do {
            if xml { try MontagePlanner.validate(project) }
            let panel = NSSavePanel(); panel.nameFieldStringValue = "卡点排镜."+(xml ? "fcpxml" : "json")
            if panel.runModal() == .OK,let url = panel.url {
                if xml { try MontagePlanner.xml(project).write(to:url,atomically:true,encoding:.utf8) }
                else { try JSONEncoder().encode(project).write(to:url,options:.atomic) }
                message = "已保存 \(url.lastPathComponent)"
            }
        } catch { message = error.localizedDescription }
    }
    func open() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK,let url = panel.url {
            do { let incoming = try JSONDecoder().decode(MontageProject.self,from:Data(contentsOf:url)); try MontagePlanner.validateEditable(incoming); project = incoming; rangeStart = incoming.sourceIn; rangeEnd = incoming.sourceIn+incoming.duration; message = "排镜工程已载入，请确认原素材仍在原路径" }
            catch { message = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel(); if process?.isRunning == true { process?.terminate() } }
    func execute(_ executable:String,_ args:[String],directory:URL) async throws {
        try Task.checkCancellation()
        let log = directory.appendingPathComponent(UUID().uuidString+".log"); FileManager.default.createFile(atPath:log.path,contents:nil)
        let handle = try FileHandle(forWritingTo:log); defer { try? handle.close() }
        let p = Process(); p.executableURL = URL(fileURLWithPath:executable); p.arguments = args; p.standardError = handle; p.standardOutput = FileHandle.nullDevice; process = p; try p.run()
        await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in DispatchQueue.global().async { p.waitUntilExit(); c.resume() } }
        try Task.checkCancellation()
        guard p.terminationStatus == 0 else { throw StudioError.message(String(((try? String(contentsOf:log,encoding:.utf8)) ?? "FFmpeg 执行失败").suffix(1500))) }
    }
    func render(ffmpeg:String?,preview:Bool) {
        guard !busy else { return }
        do { try MontagePlanner.validate(project) } catch { message = error.localizedDescription; return }
        guard let ffmpeg else { message = "未找到 FFmpeg"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = preview ? "排镜预览.mp4" : "卡点成片.mp4"
        guard panel.runModal() == .OK,let destination = panel.url else { return }
        render(to:destination,ffmpeg:ffmpeg,preview:preview)
    }
    func render(to destination:URL,ffmpeg:String,preview:Bool) {
        guard !busy else { return }
        do { try MontagePlanner.validate(project) } catch { message = error.localizedDescription; return }
        let snapshot = project
        let originals = snapshot.assets.map(\.url)+[snapshot.music!]
        guard !originals.contains(where:{ $0.standardizedFileURL == destination.standardizedFileURL }) else { message = "输出不能覆盖原素材"; return }
        busy = true
        task = Task { @MainActor in
            defer { busy = false; process = nil }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:true); defer { try? FileManager.default.removeItem(at:temp) }
                let limit = preview ? min(10,snapshot.duration) : snapshot.duration
                var files:[String] = []
                for (i,slot) in snapshot.slots.enumerated() where slot.start < limit {
                    try Task.checkCancellation(); message = "渲染镜头 \(i+1)/\(snapshot.slots.count)"
                    let asset = snapshot.assets.first { $0.id == slot.assetID }!, filename = "\(i).mp4", part = temp.appendingPathComponent(filename)
                    _ = try await execute(ffmpeg,["-hide_banner","-loglevel","error","-nostdin","-y","-ss","\(slot.sourceIn)","-i",asset.url.path,"-t","\(min(slot.duration,limit-slot.start))","-an","-vf","scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=\(snapshot.fps)","-c:v","libx264","-preset","veryfast","-crf","20","-pix_fmt","yuv420p",part.path],directory:temp)
                    files.append("file '\(filename)'")
                }
                let list = temp.appendingPathComponent("list.txt"); try files.joined(separator:"\n").write(to:list,atomically:true,encoding:.utf8)
                let rendered = temp.appendingPathComponent("result.mp4")
                try await execute(ffmpeg,["-hide_banner","-loglevel","error","-nostdin","-y","-f","concat","-safe","1","-i",list.path,"-ss","\(snapshot.sourceIn)","-i",snapshot.music!.path,"-map","0:v:0","-map","1:a:0","-t","\(limit)","-c:v","copy","-c:a","aac","-movflags","+faststart",rendered.path],directory:temp)
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath:destination.path) { _ = try FileManager.default.replaceItemAt(destination,withItemAt:rendered) } else { try FileManager.default.moveItem(at:rendered,to:destination) }
                message = "已导出 \(destination.lastPathComponent)"
            } catch { message = error is CancellationError ? "已取消，原素材与原输出文件已保留" : error.localizedDescription }
        }
    }
}
