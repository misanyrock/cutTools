import Foundation

struct SubtitleStyle: Codable {
    var chineseSize = 48.0
    var englishSize = 34.0
    var chineseColor = "FFFFFF"
    var englishColor = "FFFF99"
    var bottom = 50
    var gap = 8
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
        let zhMargin = style.bottom + (chineseFirst && !en.isEmpty ? Int(style.englishSize) + style.gap : 0)
        let enMargin = style.bottom + (!chineseFirst && !zh.isEmpty ? Int(style.chineseSize) + style.gap : 0)
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
        for (name,cues) in [("Chinese",zh),("English",en)] { for c in cues { text += "Dialogue: 0,\(time(c.start)),\(time(c.end)),\(name),,0,0,0,,\(escape(c.text))\n" } }
        return text
    }
    static func xmlEscape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
    static func fcpxml(_ cues: [Cue], style: SubtitleStyle, width: Int, height: Int) -> String {
        func t(_ frame: Int) -> String { "\(frame)/25s" }
        let timedCues = cues.map { cue in
            let start = max(0, Int((cue.start * 25).rounded()))
            let end = max(start + 1, Int((cue.end * 25).rounded()))
            return (cue: cue, start: start, end: end)
        }
        let end = timedCues.map(\.end).max() ?? 25
        let titles = timedCues.enumerated().map { i,c in """
        <title ref="r2" lane="1" offset="\(t(c.start))" duration="\(t(c.end-c.start))" name="字幕 \(i+1)"><text><text-style ref="ts\(i)">\(xmlEscape(c.cue.text))</text-style></text><text-style-def id="ts\(i)"><text-style font="PingFang SC" fontSize="\(Int(style.chineseSize))" fontColor="1 1 1 1" alignment="center"/></text-style-def></title>
        """ }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10"><resources><format id="r1" frameDuration="1/25s" width="\(width)" height="\(height)" colorSpace="1-1-1 (Rec. 709)"/><effect id="r2" name="Basic Title" uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"/></resources><library><event name="CutTools"><project name="可编辑字幕"><sequence format="r1" duration="\(t(end))" tcStart="0s" tcFormat="NDF"><spine><gap name="字幕底轨" offset="0s" duration="\(t(end))">\(titles)</gap></spine></sequence></project></event></library></fcpxml>
        """
    }
}
