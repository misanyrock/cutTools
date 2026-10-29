import Foundation

struct SubtitleStyle: Codable {
    var chineseSize = 48.0
    var englishSize = 34.0
    var chineseColor = "FFFFFF"
    var englishColor = "FFFF99"
    var bottom = 50
    var gap = 8
    var chineseBottom: Double?
    var englishBottom: Double?
    var chineseX: Double?
    var englishX: Double?

    func bottom(chinese: Bool, chineseFirst: Bool, bilingual: Bool) -> Double {
        let custom = chinese ? chineseBottom : englishBottom
        return custom ?? (Double(bottom) + (bilingual && chinese == chineseFirst ? (chinese ? englishSize : chineseSize) + Double(gap) : 0))
    }
    func x(chinese: Bool) -> Double { (chinese ? chineseX : englishX) ?? 0 }
}
struct TimeRange: Identifiable, Equatable {
    let id = UUID()
    var start: Double
    var end: Double
    var reason: String
    var selected = false
}
struct CheckFinding: Identifiable {
    let id = UUID()
    var start: Double
    var end: Double
    var message: String
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

enum Timeline {
    static func merged(_ ranges: [TimeRange], duration: Double) -> [(Double, Double)] {
        let sorted = ranges.filter(\.selected).map { (max(0, $0.start), min(duration, $0.end)) }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var result: [(Double, Double)] = []
        for r in sorted { if let last = result.last, r.0 <= last.1 { result[result.count-1].1 = max(last.1, r.1) } else { result.append(r) } }
        return result
    }
    static func kept(_ ranges: [TimeRange], duration: Double) -> [(Double, Double)] {
        var cursor = 0.0; var result: [(Double, Double)] = []
        for r in merged(ranges, duration: duration) { if r.0 > cursor { result.append((cursor, r.0)) }; cursor = r.1 }
        if cursor < duration { result.append((cursor, duration)) }; return result
    }
    static func remap(_ cues: [Cue], kept: [(Double, Double)]) -> [Cue] {
        var offset = 0.0; var result: [Cue] = []
        for range in kept {
            for cue in cues { let s = max(cue.start, range.0), e = min(cue.end, range.1); if e > s { var c = cue; c.id = UUID(); c.start = offset + s - range.0; c.end = offset + e - range.0; result.append(c) } }
            offset += range.1 - range.0
        }
        return result.enumerated().map { i, c in var c = c; c.sourceNumber = i+1; return c }
    }
    static func events(_ log: String, name: String, duration: Double) -> [(Double, Double)] {
        let regex = try! NSRegularExpression(pattern: "\(name)_(start|end)[:=]\\s*([0-9.]+)")
        var start: Double?; var result: [(Double, Double)] = []
        for match in regex.matches(in: log, range: NSRange(log.startIndex..., in: log)) {
            let kind = String(log[Range(match.range(at: 1), in: log)!]); let value = Double(log[Range(match.range(at: 2), in: log)!]) ?? 0
            if kind == "start" { start = value } else if let s = start { result.append((s, value)); start = nil }
        }
        if let start { result.append((start, duration)) }; return result
    }
}

enum StyledSubtitles {
    static func ass(zh: [Cue], en: [Cue], style: SubtitleStyle, width: Int, height: Int, chineseFirst: Bool) -> String {
        func color(_ hex: String) -> String { let clean = hex.uppercased().filter { $0.isHexDigit }; guard clean.count == 6 else { return "&H00FFFFFF" }; let chars = Array(clean); return "&H00" + String(chars[4...5]) + String(chars[2...3]) + String(chars[0...1]) }
        func time(_ t: Double) -> String { let n = max(0, Int(t*100)); return String(format: "%d:%02d:%02d.%02d", n/360000,n/6000%60,n/100%60,n%100) }
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "{", with: "\\{").replacingOccurrences(of: "}", with: "\\}").replacingOccurrences(of: "\n", with: "\\N") }
        let bilingual = !zh.isEmpty && !en.isEmpty
        let zhMargin = Int(style.bottom(chinese: true, chineseFirst: chineseFirst, bilingual: bilingual))
        let enMargin = Int(style.bottom(chinese: false, chineseFirst: chineseFirst, bilingual: bilingual))
        var text = """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: \(width)
        PlayResY: \(height)
        WrapStyle: 0
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Chinese,PingFang SC,\(style.chineseSize),\(color(style.chineseColor)),&H000000FF,&H00101010,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,40,40,\(zhMargin),1
        Style: English,Arial,\(style.englishSize),\(color(style.englishColor)),&H000000FF,&H00101010,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,40,40,\(enMargin),1
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """
        for (name,cues) in [("Chinese",zh),("English",en)] {
            let chinese = name == "Chinese"
            let x = Double(width) / 2 + style.x(chinese: chinese)
            let y = Double(height) - style.bottom(chinese: chinese, chineseFirst: chineseFirst, bilingual: bilingual)
            for c in cues {
                let wrapped = SubtitleLayout.wrapped(c.text, chinese: chinese, size: chinese ? style.chineseSize : style.englishSize, width: Double(width) - 80)
                text += "Dialogue: 0,\(time(c.start)),\(time(c.end)),\(name),,0,0,0,,{\\an2\\pos(\(x),\(y))}\(escape(wrapped))\n"
            }
        }
        return text
    }
    static func xmlEscape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static func fcpxml(zh: [Cue], en: [Cue], style: SubtitleStyle, width: Int, height: Int,
                       settings: SubtitleExportSettings = SubtitleExportSettings(), chineseFirst: Bool = true) throws -> String {
        let cues = zh + en
        guard !cues.isEmpty else { throw StudioError.message("请先导入或转写字幕") }
        guard width >= 2, height >= 2, width <= 7680, height <= 7680, width % 2 == 0, height % 2 == 0,
              cues.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end < 3_600_000 }),
              [style.chineseSize, style.englishSize].allSatisfy({ $0.isFinite && (16...100).contains($0) }),
              [style.chineseColor, style.englishColor].allSatisfy({ $0.count == 6 && $0.allSatisfy(\.isHexDigit) }),
              [style.chineseX, style.englishX, style.chineseBottom, style.englishBottom].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 7680 })
        else { throw StudioError.message("请检查字幕时间、分辨率、字号、位置和六位 HEX 颜色") }
        let rate = settings.frameRate
        let bilingual = !zh.isEmpty && !en.isEmpty
        var end = 1
        var titles: [String] = []
        for (chinese, track) in [(true, zh), (false, en)] {
            let size = chinese ? style.chineseSize : style.englishSize
            let color = SubtitleLayout.color(chinese ? style.chineseColor : style.englishColor).usingColorSpace(.sRGB)!
            let rgb = "\(color.redComponent) \(color.greenComponent) \(color.blueComponent) 1"
            let margin = style.bottom(chinese: chinese, chineseFirst: chineseFirst, bilingual: bilingual)
            let x = style.x(chinese: chinese)
            for cue in track {
                let start = rate.frame(cue.start), finish = max(start + 1, rate.frame(cue.end))
                end = max(end, finish)
                let id = "ts\(titles.count)"
                let text = SubtitleLayout.wrapped(cue.text, chinese: chinese, size: size, width: Double(width) - 80)
                // Basic Title uses a centered baseline; position is in percent of frame height.
                let baseline = SubtitleLayout.firstBaseline(text, chinese: chinese, size: size)
                let position = "\(x / Double(height) * 100) \((margin - Double(height) / 2 + baseline) / Double(height) * 100)"
                titles.append("""
                <title ref="r2" lane="\(chinese ? 1 : 2)" offset="\(rate.time(start))" start="0s" duration="\(rate.time(finish-start))" name="\(chinese ? "中文" : "英文") 字幕" role="\(chinese ? "titles.Chinese" : "titles.English")"><text><text-style ref="\(id)">\(xmlEscape(text))</text-style></text><text-style-def id="\(id)"><text-style font="\(chinese ? "PingFang SC" : "Arial")" fontSize="\(size)" fontColor="\(rgb)" alignment="center" strokeColor="0 0 0 1" strokeWidth="2"/></text-style-def><adjust-transform position="\(position)"/></title>
                """)
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10"><resources><format id="r1" frameDuration="\(rate.frameDuration)" width="\(width)" height="\(height)" colorSpace="\(settings.colorSpace.xmlValue)"/><effect id="r2" name="Basic Title" uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"/></resources><library colorProcessing="\(settings.colorSpace.processing)"><event name="CutTools"><project name="可编辑双语字幕"><sequence format="r1" duration="\(rate.time(end))" tcStart="0s" tcFormat="NDF"><spine><gap name="字幕底轨" offset="0s" start="0s" duration="\(rate.time(end))">\(titles.joined(separator: "\n"))</gap></spine></sequence></project></event></library></fcpxml>
        """
    }
}
