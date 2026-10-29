import Foundation

enum SubtitleFrameRate: String, CaseIterable, Codable {
    case fps23976 = "23.976", fps24 = "24", fps25 = "25", fps2997 = "29.97"
    case fps30 = "30", fps50 = "50", fps5994 = "59.94", fps60 = "60"
    var denominator: Int { switch self { case .fps23976: return 24000; case .fps2997: return 30000; case .fps5994: return 60000; default: return Int(rawValue)! } }
    var numerator: Int { [.fps23976, .fps2997, .fps5994].contains(self) ? 1001 : 1 }
    var secondsPerFrame: Double { Double(numerator) / Double(denominator) }
    var frameDuration: String { time(1) }
    func frame(_ seconds: Double) -> Int { Int((seconds / secondsPerFrame).rounded()) }
    func time(_ frames: Int) -> String { "\(frames * numerator)/\(denominator)s" }
}

enum SubtitleColorSpace: String, CaseIterable, Codable {
    case rec709 = "标准 · Rec.709"
    case wide709 = "广色域 HDR 资源库 · Rec.709 项目"
    case hlg = "HDR · Rec.2020 HLG"
    case pq = "HDR · Rec.2020 PQ"
    var processing: String { self == .rec709 ? "standard" : "wide-hdr" }
    var xmlValue: String { switch self { case .rec709, .wide709: return "1-1-1 (Rec. 709)"; case .hlg: return "9-18-9 (Rec. 2020 HLG)"; case .pq: return "9-16-9 (Rec. 2020 PQ)" } }
}

struct SubtitleExportSettings: Codable {
    var frameRate: SubtitleFrameRate = .fps25
    var colorSpace: SubtitleColorSpace = .rec709
}
