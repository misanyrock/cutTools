import Foundation
import AVFoundation

struct MontageAsset: Codable, Identifiable, Equatable {
    var id = UUID()
    var url: URL
    var duration: Double
    var width: Int
    var height: Int
    var frameRate: Double
    static func inspect(_ url:URL) async throws -> Self {
        let asset = AVURLAsset(url:url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite,duration > 0,let track = try await asset.loadTracks(withMediaType:.video).first else { throw StudioError.message("\(url.lastPathComponent)：没有可用视频轨") }
        let size = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform), fps = try await track.load(.nominalFrameRate)
        let display = size.applying(transform)
        return Self(url:url,duration:duration,width:max(2,Int(abs(display.width))),height:max(2,Int(abs(display.height))),frameRate:fps > 0 ? Double(fps) : 25)
    }
}
struct MontageSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var start:Double
    var duration:Double
    var assetID:UUID?
    var sourceIn = 0.0
    var locked = false
}
struct MontageProject: Codable {
    var assets:[MontageAsset] = []
    var slots:[MontageSlot] = []
    var music:URL?
    var musicDuration = 0.0
    var sourceIn = 0.0
    var duration = 0.0
    var fps = 25
}
enum MontagePlanner {
    static func build(assets:[MontageAsset],markers:[BeatMarker],start:Double,end:Double,minimum:Double,fps:Int,previous:[MontageSlot] = []) throws -> [MontageSlot] {
        guard [24,25,30,50,60].contains(fps), start.isFinite,end.isFinite,minimum.isFinite,start >= 0,end > start,end <= 1800,minimum >= 0,minimum <= 60 else { throw StudioError.message("排镜范围或帧率无效") }
        let f = Double(fps), first = Int((start*f).rounded()), last = Int((end*f).rounded(.down)), minFrames = max(1,Int((minimum*f).rounded()))
        guard last-first >= minFrames else { throw StudioError.message("音乐片段短于最短镜头") }
        var boundaries = [first]
        for point in Set(markers.filter { $0.enabled && $0.time.isFinite && $0.time > start && $0.time < end }.map { Int(($0.time*f).rounded()) }).sorted() {
            if point-boundaries.last! >= minFrames && last-point >= minFrames { boundaries.append(point) }
        }
        boundaries.append(last)
        guard boundaries.count <= 2001 else { throw StudioError.message("镜头太多，请缩短音乐范围或增加最短镜头时长") }
        let available = assets.filter { $0.duration.isFinite && $0.duration > 0 }
        var result:[MontageSlot] = [], cursor = 0
        for i in 0..<boundaries.count-1 {
            let offset = Double(boundaries[i]-first)/f, duration = Double(boundaries[i+1]-boundaries[i])/f
            if let locked = previous.first(where:{ $0.locked && abs($0.start-offset) < 0.0001 && abs($0.duration-duration) < 0.0001 }) { result.append(locked); continue }
            var slot = MontageSlot(start:offset,duration:duration)
            if !available.isEmpty {
                for attempt in 0..<available.count {
                    let index = (cursor+attempt)%available.count
                    if available[index].duration+0.0001 >= duration { slot.assetID = available[index].id; cursor = (index+1)%available.count; break }
                }
            }
            result.append(slot)
        }
        guard previous.filter(\.locked).allSatisfy({ old in result.contains { $0.id == old.id } }) else { throw StudioError.message("卡点或范围已变化，无法保留锁定镜头。请先解锁后再重新排镜。") }
        return result
    }
    static func validate(_ project:MontageProject, requireAssigned:Bool = true) throws {
        guard let _ = project.music, project.duration.isFinite,project.duration > 0,project.duration <= 1800,project.sourceIn.isFinite,project.sourceIn >= 0,project.musicDuration.isFinite,project.musicDuration <= 1800,project.sourceIn+project.duration <= project.musicDuration+0.05,[24,25,30,50,60].contains(project.fps),!project.slots.isEmpty,Set(project.assets.map(\.id)).count == project.assets.count,Set(project.slots.map(\.id)).count == project.slots.count else { throw StudioError.message("排镜工程缺少音乐或有效的时间范围") }
        guard project.music!.isFileURL,project.assets.allSatisfy({ $0.url.isFileURL && $0.duration.isFinite && $0.duration > 0 && $0.duration < 604800 && $0.frameRate.isFinite && $0.frameRate > 0 && $0.frameRate <= 240 && $0.width > 0 && $0.height > 0 && $0.width <= 16384 && $0.height <= 16384 }) else { throw StudioError.message("素材必须是具有有效尺寸、时长和帧率的本地文件") }
        var cursor = 0.0
        for slot in project.slots {
            guard slot.start.isFinite,slot.duration.isFinite,slot.sourceIn.isFinite,abs(slot.start-cursor) < 0.0001,slot.duration > 0,slot.sourceIn >= 0,slot.sourceIn <= 604800 else { throw StudioError.message("镜头时间无效或不连续") }
            if requireAssigned {
                guard let asset = project.assets.first(where:{ $0.id == slot.assetID }),slot.sourceIn+slot.duration <= asset.duration+0.0001 else { throw StudioError.message("镜头 \(SRT.stamp(cursor)) 未分配素材或超出素材长度") }
            }
            cursor += slot.duration
        }
        guard abs(cursor-project.duration) < 0.001 else { throw StudioError.message("镜头总时长与音乐范围不一致") }
    }
    static func validateEditable(_ project:MontageProject) throws {
        if !project.slots.isEmpty { try validate(project,requireAssigned:false); return }
        guard [24,25,30,50,60].contains(project.fps),Set(project.assets.map(\.id)).count == project.assets.count,project.assets.allSatisfy({ $0.url.isFileURL && $0.duration.isFinite && $0.duration > 0 && $0.duration < 604800 && $0.frameRate.isFinite && $0.frameRate > 0 && $0.frameRate <= 240 && $0.width > 0 && $0.height > 0 && $0.width <= 16384 && $0.height <= 16384 }) else { throw StudioError.message("素材工程数据无效") }
    }
    static func xml(_ project:MontageProject) throws -> String {
        try validate(project)
        func t(_ n:Double) -> String { "\(Int((n*Double(project.fps)).rounded()))/\(project.fps)s" }
        func nativeTime(_ n:Double,_ rate:Double) -> String {
            let frame = Int((n*rate+0.000001).rounded(.down))
            if abs(rate-29.97) < 0.02 { return "\(frame*1001)/30000s" }
            if abs(rate-23.976) < 0.02 { return "\(frame*1001)/24000s" }
            if abs(rate-59.94) < 0.02 { return "\(frame*1001)/60000s" }
            return "\(frame)/\(max(1,Int(rate.rounded())))s"
        }
        let music = project.music!
        var resources = "<format id=\"r1\" frameDuration=\"1/\(project.fps)s\" width=\"1920\" height=\"1080\" colorSpace=\"1-1-1 (Rec. 709)\"/><asset id=\"music\" start=\"0s\" duration=\"\(t(project.musicDuration))\" hasAudio=\"1\"><media-rep kind=\"original-media\" src=\"\(StyledSubtitles.xmlEscape(music.absoluteString))\"/></asset>"
        var ids:[UUID:String] = [:]
        for (index,asset) in project.assets.enumerated() {
            let id = "a\(index)"; ids[asset.id] = id
            resources += "<format id=\"f\(index)\" frameDuration=\"\(nativeTime(1/asset.frameRate,asset.frameRate))\" width=\"\(asset.width)\" height=\"\(asset.height)\" colorSpace=\"1-1-1 (Rec. 709)\"/><asset id=\"\(id)\" name=\"\(StyledSubtitles.xmlEscape(asset.url.lastPathComponent))\" start=\"0s\" duration=\"\(nativeTime(asset.duration,asset.frameRate))\" hasVideo=\"1\" format=\"f\(index)\"><media-rep kind=\"original-media\" src=\"\(StyledSubtitles.xmlEscape(asset.url.absoluteString))\"/></asset>"
        }
        var clips = ""
        for (i,slot) in project.slots.enumerated() {
            let asset = project.assets.first { $0.id == slot.assetID }!
            let audio = i == 0 ? "<asset-clip ref=\"music\" lane=\"-1\" offset=\"\(nativeTime(slot.sourceIn,asset.frameRate))\" start=\"\(t(project.sourceIn))\" duration=\"\(t(project.duration))\" audioRole=\"music\"/>" : ""
            clips += "<asset-clip ref=\"\(ids[asset.id]!)\" name=\"\(StyledSubtitles.xmlEscape(asset.url.lastPathComponent))\" offset=\"\(t(slot.start))\" start=\"\(nativeTime(slot.sourceIn,asset.frameRate))\" duration=\"\(t(slot.duration))\" srcEnable=\"video\"><adjust-conform type=\"fit\"/>\(audio)</asset-clip>"
        }
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE fcpxml><fcpxml version=\"1.10\"><resources>\(resources)</resources><library><event name=\"CutTools 卡点排镜\"><project name=\"卡点排镜\"><sequence format=\"r1\" duration=\"\(t(project.duration))\" tcStart=\"0s\" tcFormat=\"NDF\"><spine>\(clips)</spine></sequence></project></event></library></fcpxml>"
    }
}
