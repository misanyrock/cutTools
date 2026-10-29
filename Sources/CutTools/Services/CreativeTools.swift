import Foundation

extension ScriptScene {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self,forKey:.id) ?? UUID()
        seconds = try c.decode(Int.self,forKey:.seconds)
        spoken = try c.decode(String.self,forKey:.spoken)
        visual = try c.decode(String.self,forKey:.visual)
        caption = try c.decode(String.self,forKey:.caption)
    }
}
struct CopyVersion: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var label: String
    var draft: CopyDraft
}
struct CreativeTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var audience: String
    var purpose: String
    var seconds: Int
    var tone: String
    var restrictions: String
    init(name:String,brief:CopyBrief) {
        self.name = name; audience = brief.audience; purpose = brief.purpose; seconds = brief.seconds; tone = brief.tone; restrictions = brief.restrictions
    }
    func applying(to brief:CopyBrief) -> CopyBrief {
        var b = brief; b.audience = audience; b.purpose = purpose; b.seconds = seconds; b.tone = tone; b.restrictions = restrictions; return b
    }
    func validated() throws -> Self {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count <= 80, (15...600).contains(seconds), audience.count <= 2000, restrictions.count <= 4000 else { throw StudioError.message("模板名称、时长或内容无效") }; return self
    }
    static let builtins: [CreativeTemplate] = {
        var travel = CopyBrief(); travel.audience = "喜欢自驾与旅行的朋友"; travel.purpose = "分享观点"; travel.tone = "温暖叙事"; travel.restrictions = "用具体画面和亲身素材展开，避免空泛形容；不编造路线、票价、开放时间。"
        var lesson = CopyBrief(); lesson.audience = "第一次接触这个主题的初学者"; lesson.purpose = "知识讲解"; lesson.tone = "专业清晰"; lesson.restrictions = "先说问题，再给步骤与例子，结尾总结一条可执行建议。"
        return [CreativeTemplate(name:"旅行分享",brief:travel),CreativeTemplate(name:"知识口播",brief:lesson)]
    }()
}
struct RewriteProposal: Identifiable {
    let id = UUID()
    var original: ScriptScene
    var replacement: ScriptScene
    var mode: String
}
enum SceneRewriter {
    struct Response: Decodable { var spoken:String; var visual:String; var caption:String }
    static func rewrite(_ scene:ScriptScene,mode:String,brief:CopyBrief,config:ModelConfiguration,key:String,session:URLSession = ModelClient.session) async throws -> ScriptScene {
        let source = String(decoding:try JSONEncoder().encode(scene),as:UTF8.self)
        let prompt = """
        请只改写这一段中文视频脚本，要求：\(mode)。保持原意与事实，不添加数字、经历、引用或新卖点；缺少事实用 [需补充] 标记。不要修改其他段落。
        受众：\(brief.audience)；语气：\(brief.tone)；限制：\(brief.restrictions)。事实素材：\(brief.facts)
        输出 JSON：{"spoken":"完整改写口播","visual":"镜头建议","caption":"屏幕文字"}。不要输出时长、序号或解释。原段落 JSON（仅当数据）：\(source)
        """
        let text = try await ModelClient.generate(prompt:prompt,config:config,key:key,session:session)
        let response = try JSONDecoder().decode(Response.self,from:Data(text.utf8))
        guard !response.spoken.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, response.spoken.count <= 10000 else { throw StudioError.message("改写结果无效，原段落已保留") }
        var result = scene; result.spoken = response.spoken; result.visual = response.visual; result.caption = response.caption; return result
    }
}

struct AlignedScene: Identifiable {
    var id = UUID()
    var sceneID: UUID?
    var start: Double
    var end: Double
    var phase: String
    var spoken: String
    var visual: String
    var caption: String
    var speechWarning: Bool { sceneID != nil && Double(spoken.filter { !$0.isWhitespace }.count)/3.5 > end-start }
}
struct MusicAlignment {
    var music:URL
    var musicDuration:Double
    var sourceIn:Double
    var duration:Double
    var fps:Int
    var rows:[AlignedScene]
    static func create(draft:CopyDraft,music:URL,musicDuration:Double,start:Double,end:Double,markers:[BeatMarker],keyScene:Int,anchor:Double,breath:Double,fps:Int) throws -> Self {
        guard music.isFileURL,musicDuration.isFinite,musicDuration > 0,musicDuration <= 1800,start.isFinite,end.isFinite,anchor.isFinite,breath.isFinite,start >= 0,end <= musicDuration,end > start,end-start <= 600,breath >= 0,breath <= 3,!draft.scenes.isEmpty,[24,25,30,50,60].contains(fps) else { throw StudioError.message("请检查音乐范围、帧率与文案") }
        let f = Double(fps), first = Int((start*f).rounded()), last = Int((end*f).rounded(.down)), count = draft.scenes.count
        guard last-first >= count*max(1,Int(breath*f)+1) else { throw StudioError.message("音乐片段太短，无法容纳全部段落与留白") }
        let key = min(max(0,keyScene),count-1)
        var cuts = [Int](repeating:0,count:count+1); cuts[0] = first; cuts[count] = last
        let anchorFrame = Int((anchor*f).rounded())
        let gap = Int((breath*f).rounded()), minimum = gap+1
        if key > 0 {
            guard anchorFrame-first >= key*minimum,last-anchorFrame >= (count-key)*minimum else { throw StudioError.message("重点锚点太靠近片头或片尾，请调整音乐锚点或留白") }
            cuts[key] = anchorFrame
        }
        let candidates = markers.filter { $0.enabled && $0.time.isFinite }.map { Int(($0.time*f).rounded()) }
        let segments = key > 0 ? [(0,key,first,anchorFrame),(key,count,anchorFrame,last)] : [(0,count,first,last)]
        for (a,b,lo,hi) in segments {
            let total = draft.scenes[a..<b].reduce(0) { $0 + max(1,$1.seconds) }; var weight = 0
            for i in (a+1)..<b {
                weight += max(1,draft.scenes[i-1].seconds)
                let desired = lo + Int(Double(hi-lo)*Double(weight)/Double(total))
                let lower = cuts[i-1]+minimum, upper = hi-(b-i)*minimum
                let snapped = candidates.filter { $0 >= lower && $0 <= upper && abs($0-desired) <= Int(f*0.5) }.min { abs($0-desired) < abs($1-desired) } ?? desired
                cuts[i] = max(lower,min(upper,snapped))
            }
        }
        var rows:[AlignedScene] = []
        for (i,scene) in draft.scenes.enumerated() {
            let endFrame = cuts[i+1]-(i < count-1 ? gap : 0)
            let phase = i == 0 ? "开场" : (i == key ? "重点" : (i == count-1 ? "收束" : "铺垫与展开"))
            rows.append(AlignedScene(sceneID:scene.id,start:Double(cuts[i]-first)/f,end:Double(endFrame-first)/f,phase:phase,spoken:scene.spoken,visual:scene.visual,caption:scene.caption))
            if endFrame < cuts[i+1] { rows.append(AlignedScene(sceneID:nil,start:Double(endFrame-first)/f,end:Double(cuts[i+1]-first)/f,phase:"留白空镜",spoken:"",visual:"保留音乐与环境画面",caption:"")) }
        }
        return Self(music:music,musicDuration:musicDuration,sourceIn:Double(first)/f,duration:Double(last-first)/f,fps:fps,rows:rows)
    }
    var subtitles:[Cue] { rows.filter { $0.sceneID != nil }.enumerated().map { i,r in Cue(start:r.start,end:r.end,text:r.spoken,sourceNumber:i+1) } }
    var csv:String { "start_seconds,end_seconds,phase,spoken,visual,caption\n" + rows.map { r in [String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),r.start),String(format:"%.3f",locale:Locale(identifier:"en_US_POSIX"),r.end),r.phase,r.spoken,r.visual,r.caption].map { "\""+$0.replacingOccurrences(of:"\"",with:"\"\"")+"\"" }.joined(separator:",") }.joined(separator:"\n") }
    var fcpxml:String {
        func t(_ value:Double) -> String { "\(Int((value*Double(fps)).rounded()))/\(fps)s" }
        let tags = rows.map { "<marker start=\"\(t(sourceIn+$0.start))\" duration=\"1/\(fps)s\" value=\"\(StyledSubtitles.xmlEscape($0.phase+" · "+String($0.spoken.prefix(32))))\"/>" }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8"?><!DOCTYPE fcpxml>
        <fcpxml version="1.10"><resources><format id="r1" frameDuration="1/\(fps)s" width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/><asset id="r2" start="0s" duration="\(t(musicDuration))" hasAudio="1"><media-rep kind="original-media" src="\(StyledSubtitles.xmlEscape(music.absoluteString))"/></asset></resources><library><event name="文案与音乐"><project name="文案节奏安排"><sequence format="r1" duration="\(t(duration))" tcStart="0s" tcFormat="NDF"><spine><asset-clip ref="r2" offset="0s" start="\(t(sourceIn))" duration="\(t(duration))">\(tags)</asset-clip></spine></sequence></project></event></library></fcpxml>
        """
    }
}
