import Foundation
import CoreFoundation

struct Cue: Identifiable, Equatable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var sourceNumber: Int
}

enum SRT {
    static func time(_ s: String) -> Double? {
        let p = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let sec = Double(p[2]), h.isFinite, m.isFinite, sec.isFinite, h >= 0, h < 1000, m >= 0, m < 60, sec >= 0, sec < 60 else { return nil }
        return h * 3600 + m * 60 + sec
    }
    static func stamp(_ seconds: Double) -> String {
        let bounded = seconds.isFinite ? min(max(0, seconds), 3_599_999) : 0
        let ms = Int((bounded * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3600000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }
    static func read(_ url: URL) throws -> [Cue] {
        let data = try Data(contentsOf: url)
        guard let string = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))) else { throw NSError(domain: "SRT", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法识别字幕编码（支持 UTF-8、UTF-16、GB18030）"]) }
        return try parse(string)
    }
    static func parse(_ input: String) throws -> [Cue] {
        let normalized = input.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return try blocks.enumerated().map { index, block in
            let lines = block.components(separatedBy: "\n")
            guard let t = lines.firstIndex(where: { $0.contains("-->") }) else { throw NSError(domain: "SRT", code: 2, userInfo: [NSLocalizedDescriptionKey: "第 \(index + 1) 段缺少时间轴"]) }
            let parts = lines[t].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]), let end = time(parts[1].components(separatedBy: " ").filter { !$0.isEmpty }.first ?? ""), end > start else { throw NSError(domain: "SRT", code: 3, userInfo: [NSLocalizedDescriptionKey: "第 \(index + 1) 段时间无效"]) }
            return Cue(start: start, end: end, text: lines.dropFirst(t + 1).joined(separator: "\n").trimmingCharacters(in: .newlines), sourceNumber: Int(lines.first ?? "") ?? 0)
        }
    }
    static func render(_ cues: [Cue]) -> String {
        cues.enumerated().map { i, c in "\(i + 1)\n\(stamp(c.start)) --> \(stamp(c.end))\n\(c.text)\n" }.joined(separator: "\n")
    }
    static func issues(_ cues: [Cue]) -> [String] {
        var result: [String] = []
        for (i, c) in cues.enumerated() {
            if c.sourceNumber != i + 1 { result.append("第 \(i+1) 条：序号不连续") }
            if c.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("第 \(i+1) 条：空字幕") }
            if c.end - c.start < 0.8 { result.append("第 \(i+1) 条：显示不足 0.8 秒") }
            if c.text.components(separatedBy: "\n").contains(where: { $0.count > 42 }) { result.append("第 \(i+1) 条：单行超过 42 字") }
            if i > 0 && c.start < cues[i-1].end { result.append("第 \(i+1) 条：与上一条时间重叠") }
        }
        return result
    }
    // Connected overlap components preserve one-to-many pairings without relying on numbering.
    static func match(_ left: [Cue], _ right: [Cue], chineseFirst: Bool) -> [(Cue, Bool)] {
        struct Item { var cue: Cue; var chinese: Bool }
        let items = (left.map { Item(cue: $0, chinese: true) } + right.map { Item(cue: $0, chinese: false) }).sorted { $0.cue.start < $1.cue.start }
        var groups: [[Item]] = []
        for item in items {
            if let last = groups.last, last.contains(where: { $0.chinese != item.chinese && min($0.cue.end, item.cue.end) > max($0.cue.start, item.cue.start) }) { groups[groups.count - 1].append(item) }
            else { groups.append([item]) }
        }
        return groups.map { group in
            let zh = group.filter(\.chinese).map { $0.cue.text }.joined(separator: "\n")
            let en = group.filter { !$0.chinese }.map { $0.cue.text }.joined(separator: "\n")
            let text = (chineseFirst ? [zh,en] : [en,zh]).filter { !$0.isEmpty }.joined(separator: "\n")
            let start = group.map { $0.cue.start }.min()!, end = group.map { $0.cue.end }.max()!
            let confidence = !zh.isEmpty && !en.isEmpty && group.count == 2 && min(group[0].cue.end, group[1].cue.end) - max(group[0].cue.start, group[1].cue.start) >= 0.5 * min(group[0].cue.end - group[0].cue.start, group[1].cue.end - group[1].cue.start)
            return (Cue(start: start, end: end, text: text, sourceNumber: 0), !confidence)
        }
    }
}
