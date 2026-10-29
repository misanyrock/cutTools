import Foundation
import AVKit
import AppKit
import UniformTypeIdentifiers

struct BeatSession: Codable {
    var source: URL
    var duration: Double
    var markers: [BeatMarker]
    var fps: Int
}

@MainActor final class BeatStore: ObservableObject {
    @Published var filter: BeatFilter = .all
    @Published var enabledOnly = false
    @Published private(set) var selectionUndo: [UUID: Bool]?
    var visibleMarkers: [BeatMarker] { markers.filter { filter.includes($0) && (!enabledOnly || $0.enabled) } }
    func keepOnly(_ filter: BeatFilter) {
        guard !busy else { return }
        selectionUndo = Dictionary(uniqueKeysWithValues: markers.map { ($0.id,$0.enabled) })
        markers = filter.enabledOnly(markers)
        message = "仅启用\(filter.rawValue)：\(markers.filter(\.enabled).count) 个；其余标记保留但不导出（包含手动标记）"
    }
    func undoSelection() {
        guard let previous = selectionUndo else { return }
        markers = markers.map { var marker = $0; if let enabled = previous[marker.id] { marker.enabled = enabled }; return marker }
        selectionUndo = nil
    }
    @Published var source: URL?
    @Published var duration = 0.0
    @Published var waveform: [Float] = []
    @Published var markers: [BeatMarker] = []
    @Published var bpm: Double?
    @Published var sensitivity = 1.0
    @Published var fps = 25
    @Published var currentTime = 0.0
    @Published var busy = false
    @Published var message = "导入音乐，试听并标记你想切换画面的瞬间"
    @Published var zoom = 1.0
    let player = AVPlayer()
    private var observer: Any?
    private var process: Process?
    private var task: Task<Void,Never>?
    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1,preferredTimescale: 600),queue: .main) { [weak self] time in
            Task { @MainActor in if time.seconds.isFinite { self?.currentTime = time.seconds } }
        }
    }
    deinit { if let observer { player.removeTimeObserver(observer) }; task?.cancel() }
    func choose() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio,.movie]
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
    func load(_ url: URL) {
        guard !busy else { return }
        selectionUndo = nil; filter = .all; enabledOnly = false
        source = url; duration = 0; waveform = []; markers = []; bpm = nil; currentTime = 0
        player.pause(); player.replaceCurrentItem(with: AVPlayerItem(url: url)); message = "已载入 \(url.lastPathComponent)，点击分析节拍"
    }
    func cancel() { task?.cancel(); if process?.isRunning == true { process?.terminate() } }
    func analyze(ffmpeg: String?, preserveMarkers: Bool = false) {
        guard !busy, let source else { return }
        guard let ffmpeg else { message = "未找到 FFmpeg，请先安装后再分析"; return }
        let sensitivity = sensitivity
        busy = true; message = "正在提取音频与分析节拍…"
        task = Task { @MainActor in
            defer { busy = false; process = nil }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: temp,withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: temp) }
                let pcm = temp.appendingPathComponent("audio.f32"), log = temp.appendingPathComponent("decode.log")
                FileManager.default.createFile(atPath: log.path,contents: nil)
                let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
                let p = Process(); p.executableURL = URL(fileURLWithPath: ffmpeg)
                p.arguments = ["-hide_banner","-loglevel","error","-nostdin","-y","-i",source.path,"-t","1801","-vn","-ac","1","-ar","22050","-f","f32le",pcm.path]
                p.standardError = handle; p.standardOutput = FileHandle.nullDevice; process = p; try p.run()
                await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in DispatchQueue.global().async { p.waitUntilExit(); continuation.resume() } }
                try Task.checkCancellation()
                guard p.terminationStatus == 0 else { throw StudioError.message((try? String(contentsOf: log,encoding: .utf8)) ?? "无法解码音频") }
                let data = try Data(contentsOf: pcm)
                guard data.count <= 22050*4*1800 else { throw StudioError.message("单次分析支持 30 分钟以内，请先截取音乐片段") }
                let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let detection = Task.detached(priority: .userInitiated) { try BeatDetector.analyze(samples,sensitivity: sensitivity) }
                let result = try await withTaskCancellationHandler { try await detection.value } onCancel: { detection.cancel() }
                try Task.checkCancellation()
                if preserveMarkers {
                    guard abs(duration-result.duration) < 0.1 else { throw StudioError.message("音频时长已变化，无法安全恢复波形；原标记已保留") }
                    waveform = result.waveform; bpm = result.bpm; message = "波形已恢复，原标记与工程帧率保持不变"; return
                }
                selectionUndo = nil; waveform = result.waveform; duration = result.duration; markers = result.markers; bpm = result.bpm
                message = "找到 \(markers.filter(\.enabled).count) 个节拍候选，请试听确认；重新分析将替换现有标记"
            } catch { message = error is CancellationError ? "已取消分析，原标记保留" : error.localizedDescription }
        }
    }
    func seek(_ time: Double) {
        guard time.isFinite else { return }; let t = max(0,min(time,duration))
        currentTime = t; player.seek(to: CMTime(seconds: t,preferredTimescale: 600),toleranceBefore: .zero,toleranceAfter: .zero)
    }
    func togglePlay() { if player.rate == 0 { player.play() } else { player.pause() } }
    func add() {
        guard duration > 0 else { message = "请先分析音乐"; return }
        markers.append(BeatMarker(time: max(0,min(currentTime,duration-0.001)),strength: 1,kind: "手动标记")); markers.sort { $0.time < $1.time }
    }
    func shift(_ id: UUID, by delta: Double) {
        guard let i = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[i].time = max(0,min(duration-0.001,markers[i].time+delta)); markers.sort { $0.time < $1.time }
    }
    func save(kind: String) {
        guard let source, duration > 0 else { message = "先分析音乐或载入标记工程"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "-卡点." + kind
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if kind == "json" { try JSONEncoder().encode(BeatSession(source: source,duration: duration,markers: markers,fps: fps)).write(to: url,options: .atomic) }
                else { let text = kind == "fcpxml" ? BeatExport.xml(source: source,duration: duration,markers: markers,fps: fps) : BeatExport.csv(markers); try text.write(to: url,atomically: true,encoding: .utf8) }
                message = "已保存 \(url.lastPathComponent)" + (kind == "fcpxml" ? "；在 FCP 导入后检查与音乐是否对齐" : "")
            } catch { message = error.localizedDescription }
        }
    }
    func openSession() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let session = try JSONDecoder().decode(BeatSession.self,from: Data(contentsOf: url))
                guard session.duration.isFinite, session.duration > 0, session.duration <= 1800,
                      session.markers.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time < session.duration && $0.strength.isFinite }),
                      Set(session.markers.map(\.id)).count == session.markers.count else { throw StudioError.message("标记工程数据无效") }
                load(session.source); duration = session.duration; markers = session.markers.sorted { $0.time < $1.time }; fps = [24,25,30,50,60].contains(session.fps) ? session.fps : 25
                message = FileManager.default.fileExists(atPath: session.source.path) ? "已恢复标记，波形需重新分析；重新分析会替换标记" : "原音乐路径不存在，标记可查看但无法试听；请恢复音乐文件到原路径"
            } catch { message = error.localizedDescription }
        }
    }
}
