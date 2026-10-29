import Foundation
import AppKit

struct Settings: Codable {
    var width = 1920
    var height = 1080
    var mode = "保留画面"
    var background = "黑色"
    var codec = "H.264"
    var name = "课程视频"
    var offset = 0.0
    var chineseFirst = true
    var video = true
    var burned = false
    var subtitles = true
    var crop = ""
    var position = 0.5
}

struct Job: Identifiable {
    let id = UUID()
    var title: String
    var status = "等待中"
    var progress = 0.0
}

@MainActor final class Workspace: ObservableObject {
    @Published var chinese: [Cue] = []
    @Published var english: [Cue] = []
    @Published var videoURLs: [URL] = []
    @Published var selectedVideo: URL?
    @Published var settings = Settings()
    @Published var output: URL?
    @Published var jobs: [Job] = []
    @Published var message = "拖入视频和字幕，开始整理"
    @Published var cropSuggestion = ""
    @Published var isRunning = false
    @Published var presetNames: [String] = []
    @Published var style: SubtitleStyle = (UserDefaults.standard.data(forKey: "subtitleStyle").flatMap { try? JSONDecoder().decode(SubtitleStyle.self, from: $0) }) ?? SubtitleStyle()
    var cutsVideo: URL?
    @Published var cuts: [TimeRange] = []
    @Published var findings: [CheckFinding] = []
    @Published var studioBusy = false
    @Published var studioProgress = ""
    @Published var seekTime = 0.0
    @Published var duration = 0.0
    @Published var whisperPath = UserDefaults.standard.string(forKey: "whisperPath") ?? "/opt/homebrew/bin/whisper-cli"
    @Published var whisperModel = UserDefaults.standard.string(forKey: "whisperModel") ?? ""
    @Published var translationModel = UserDefaults.standard.string(forKey: "translationModel") ?? "qwen3:8b"
    @Published var glossary = UserDefaults.standard.string(forKey: "glossary") ?? ""
    @Published var language = "zh"
    var studioTask: Task<Void, Never>?
    private var process: Process?
    private var cancelled = false
    var ffmpeg: String? { executable("ffmpeg") }
    var ffprobe: String? { executable("ffprobe") }
    var matched: [(Cue, Bool)] { SRT.match(chinese, english, chineseFirst: settings.chineseFirst) }
    var issues: [String] { SRT.issues(chinese).map { "中文：" + $0 } + SRT.issues(english).map { "英文：" + $0 } }
    init() { presetNames = Array(presets.keys).sorted() }
    var presets: [String: Settings] {
        get { guard let data = UserDefaults.standard.data(forKey: "presets") else { return [:] }; return (try? JSONDecoder().decode([String: Settings].self, from: data)) ?? [:] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "presets"); presetNames = Array(newValue.keys).sorted() }
    }
    func savePreset() { UserDefaults.standard.set(try? JSONEncoder().encode(style), forKey: "subtitleStyle"); var p = presets; p[settings.name] = settings; presets = p; message = "预设已保存" }
    func loadPreset(_ name: String) { if let p = presets[name] { settings = p } }
    func executable(_ name: String) -> String? { ["/opt/homebrew/bin/", "/usr/local/bin/", "/usr/bin/"].map { $0 + name }.first { FileManager.default.isExecutableFile(atPath: $0) } }
    func importURL(_ url: URL, language: String? = nil) {
        if url.pathExtension.lowercased() == "srt" {
            do { let cues = try SRT.read(url); if language == "英文" || (language == nil && !chinese.isEmpty && english.isEmpty) { english = cues } else { chinese = cues }; message = "已导入 \(url.lastPathComponent)：\(cues.count) 条" } catch { message = error.localizedDescription }
        } else { if !videoURLs.contains(url) { videoURLs.append(url) }; selectedVideo = url; message = "已添加 \(url.lastPathComponent)" }
    }
    func choose(_ kind: String) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = kind == "视频"; panel.canChooseDirectories = kind == "目录"; panel.canChooseFiles = kind != "目录"
        if panel.runModal() == .OK { if kind == "目录" { output = panel.url } else { for url in panel.urls { importURL(url, language: kind) } } }
    }
    func shift() {
        let delta = settings.offset
        func apply(_ cues: [Cue]) -> [Cue] { cues.map { c in var c = c; let duration = c.end - c.start; c.start = max(0, c.start + delta); c.end = c.start + duration; return c } }
        chinese = apply(chinese); english = apply(english); settings.offset = 0; message = "已应用整体偏移"
    }
    func detectCrop() {
        guard let video = selectedVideo, let ffmpeg else { message = "请先选择视频并配置 FFmpeg"; return }
        studio {
            self.studioProgress = "多处采样检测黑边"
            let duration = try await self.mediaDuration(video)
            var samples: [String] = []
            for fraction in [0.1, 0.5, 0.85] {
                let log = try await self.checkedProcess(ffmpeg, ["-hide_banner","-nostdin","-ss","\(duration*fraction)","-i",video.path,"-t","2","-vf","cropdetect=24:16:0","-an","-f","null","-"])
                let regex = try NSRegularExpression(pattern: "crop=([0-9]+:[0-9]+:[0-9]+:[0-9]+)")
                if let last = regex.matches(in: log, range: NSRange(log.startIndex..., in: log)).last, let range = Range(last.range(at: 1), in: log) { samples.append(String(log[range])) }
            }
            guard let candidate = samples.first, samples.count == 3, samples.allSatisfy({ $0 == candidate }) else { throw StudioError.message("不同位置的黑边检测结果不一致，请手动检查；未应用裁切") }
            self.cropSuggestion = candidate; self.studioProgress = "建议裁切 \(candidate)，请确认后应用"
        }
    }
    func cancel() { studioTask?.cancel(); cancelled = true; process?.terminate(); message = "正在取消任务" }
    func run(preview: Bool = false) {
        guard !isRunning && !studioBusy else { message = "请等待当前任务完成"; return }; guard let dir = output else { message = "请选择保存目录"; return }
        guard !videoURLs.isEmpty || !chinese.isEmpty || !english.isEmpty else { message = "请先导入素材"; return }
        if settings.video || settings.burned { guard ffmpeg != nil else { message = "未找到 FFmpeg，请安装或配置 /opt/homebrew/bin/ffmpeg"; return } }
        guard (chinese + english).allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start }) else { message = "字幕时间无效，请先修正"; return }
        guard settings.width > 0, settings.height > 0, settings.width <= 7680, settings.height <= 7680, settings.width % 2 == 0, settings.height % 2 == 0 else { message = "分辨率必须是 2 到 7680 的偶数"; return }
        cancelled = false; isRunning = true; jobs = []; let config = settings; let zh = chinese; let en = english; let bilingual = matched.map(\.0); let videos = videoURLs
        Task { @MainActor in
            defer { self.isRunning = false; self.process = nil }
            do {
                if config.burned {
                    let capabilities = await runProcess(ffmpeg!, ["-hide_banner", "-filters"])
                    guard capabilities.1.contains("subtitles") else { throw StudioError.message("当前 FFmpeg 没有 subtitles/libass 滤镜，无法烧录。请配置带 libass 的 FFmpeg，或导出 ASS 字幕。") }
                }
                if config.subtitles && !preview {
                    for (suffix, cues) in [("中文", zh), ("英文", en), ("双语", bilingual)] where !cues.isEmpty {
                        let destination = unique(dir, "\(config.name)-\(suffix)", "srt"); try SRT.render(cues).write(to: destination, atomically: true, encoding: .utf8)
                        jobs.append(Job(title: destination.lastPathComponent, status: "完成", progress: 1))
                    }
                }
                for video in videos {
                    for burn in [false, true] where (burn ? config.burned : config.video) {
                        if cancelled { throw CancellationError() }
                        if burn && bilingual.isEmpty { throw NSError(domain: "Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可烧录的字幕"]) }
                        let destination = unique(dir, "\(video.deletingPathExtension().lastPathComponent)-\(burn ? "双语" : "无字幕")\(preview ? "-预览" : "")", "mp4")
                        jobs.append(Job(title: destination.lastPathComponent, status: "处理中")); let index = jobs.count - 1
                        let tempSRT = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ass")
                        defer { try? FileManager.default.removeItem(at: tempSRT) }
                        var filters: [String] = []
                        if !config.crop.isEmpty { filters.append("crop=\(config.crop)") }
                        if config.mode == "保留画面" {
                            if config.background == "模糊" { filters.append("split[fg][bg];[bg]scale=\(config.width):\(config.height):force_original_aspect_ratio=increase,crop=\(config.width):\(config.height),boxblur=20:2[blur];[fg]scale=\(config.width):\(config.height):force_original_aspect_ratio=decrease[front];[blur][front]overlay=(W-w)/2:(H-h)/2") }
                            else { filters.append("scale=\(config.width):\(config.height):force_original_aspect_ratio=decrease,pad=\(config.width):\(config.height):(ow-iw)/2:(oh-ih)/2:black") }
                        } else if config.mode == "裁切填满" { filters.append("scale=\(config.width):\(config.height):force_original_aspect_ratio=increase,crop=\(config.width):\(config.height):(iw-ow)*\(config.position):(ih-oh)/2") }
                        if burn { try StyledSubtitles.ass(zh: zh, en: en, style: style, width: config.width, height: config.height, chineseFirst: config.chineseFirst).write(to: tempSRT, atomically: true, encoding: .utf8); filters.append("subtitles='\(tempSRT.path.replacingOccurrences(of: "'", with: "\\'"))'") }
                        var args = ["-hide_banner", "-nostdin", "-n", "-i", video.path]; if preview { args += ["-t", "10"] }; if !filters.isEmpty { args += ["-vf", filters.joined(separator: ",")] }; args += ["-c:v", config.codec == "HEVC" ? "libx265" : "libx264", "-crf", "23", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart", destination.path]
                        let result = await runProcess(ffmpeg!, args)
                        if result.0 != 0 { try? FileManager.default.removeItem(at: destination); jobs[index].status = "失败：\(result.1.suffix(600))"; if cancelled { throw CancellationError() }; continue }
                        jobs[index].status = "完成"; jobs[index].progress = 1
                    }
                }
                message = cancelled ? "已取消" : "任务结束，请查看队列"
            } catch { message = error is CancellationError ? "已取消" : error.localizedDescription }
        }
    }
    func unique(_ dir: URL, _ stem: String, _ ext: String) -> URL { let stem = stem.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_"); var n = 0; var url: URL; repeat { url = dir.appendingPathComponent(stem + (n == 0 ? "" : "-\(n)")).appendingPathExtension(ext); n += 1 } while FileManager.default.fileExists(atPath: url.path); return url }
    func runProcess(_ executable: String, _ args: [String]) async -> (Int32, String) {
        let task = Process(); task.executableURL = URL(fileURLWithPath: executable); task.arguments = args; let pipe = Pipe(); task.standardError = pipe; task.standardOutput = pipe; process = task
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        return await withCheckedContinuation { continuation in DispatchQueue.global().async { let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit(); continuation.resume(returning: (task.terminationStatus, String(decoding: data, as: UTF8.self))) } }
    }
}
