import Foundation

struct BeatMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var time: Double
    var strength: Double
    var kind: String
    var enabled = true
}
struct BeatAnalysis {
    var duration: Double
    var waveform: [Float]
    var markers: [BeatMarker]
    var bpm: Double?
}

/// Spectral-flux onset candidates, not a claim of musical downbeat recognition.
enum BeatDetector {
    static func analyze(_ samples: [Float], rate: Double = 22050, sensitivity: Double = 1) throws -> BeatAnalysis {
        guard rate > 0, samples.count >= 1024, samples.allSatisfy(\.isFinite) else { throw StudioError.message("音频太短或包含无效采样") }
        let n = 1024, hop = 256
        let window = (0..<n).map { Float(0.5 - 0.5*cos(2 * .pi * Double($0)/Double(n-1))) }
        let cosines = (0..<n/2).map { Float(cos(-2 * .pi * Double($0)/Double(n))) }
        let sines = (0..<n/2).map { Float(sin(-2 * .pi * Double($0)/Double(n))) }
        let reversed = (0..<n).map { value -> Int in var value = value, r = 0; for _ in 0..<10 { r = r*2 + (value & 1); value >>= 1 }; return r }
        var real = [Float](repeating: 0,count: n), imag = real
        var previous = [Float](repeating: 0,count: n/2)
        var flux: [Double] = [], energy: [Double] = []
        for offset in stride(from: 0, through: samples.count-n, by: hop) {
            if flux.count % 100 == 0 { try Task.checkCancellation() }
            var sum = 0.0
            for j in 0..<n { let x = samples[offset+j]; real[reversed[j]] = x*window[j]; imag[reversed[j]] = 0; sum += Double(x*x) }
            var length = 2
            while length <= n {
                let half = length/2, step = n/length
                for base in stride(from: 0, to: n, by: length) {
                    for j in 0..<half {
                        let a = base+j, b = a+half, k = j*step
                        let r = real[b]*cosines[k] - imag[b]*sines[k], i = real[b]*sines[k] + imag[b]*cosines[k]
                        real[b] = real[a]-r; imag[b] = imag[a]-i; real[a] += r; imag[a] += i
                    }
                }
                length *= 2
            }
            var onset = 0.0
            for k in 1..<n/2 {
                let magnitude = sqrt(real[k]*real[k]+imag[k]*imag[k])
                // Low-frequency onsets have extra weight, useful for kick drums.
                onset += Double(max(0,magnitude-previous[k])) * (k < 12 ? 2 : 1)
                previous[k] = magnitude
            }
            flux.append(onset); energy.append(sum/Double(n))
        }
        let peak = flux.max() ?? 0
        var candidates: [BeatMarker] = []
        if peak > 0.001 && flux.count > 2 {
            for i in 1..<flux.count-1 {
                let local = Array(flux[max(0,i-20)...min(flux.count-1,i+20)]).sorted()
                let baseline = local[local.count/2]
                guard flux[i] >= flux[i-1], flux[i] > flux[i+1], flux[i] > max(peak*0.06,baseline*(1.4 + sensitivity)), flux[i] > 0.001 else { continue }
                let center = i*hop+n/2
                let lower = max(1,center-n/2), upper = min(samples.count-1,center+n/2)
                var best = lower, derivative: Float = 0
                for k in lower...upper { let d = abs(samples[k]-samples[k-1]); if d > derivative { derivative = d; best = k } }
                let time = Double(best)/rate
                let marker = BeatMarker(time: time,strength: flux[i]/peak,kind: flux[i] > peak*0.65 ? "强拍候选" : "节拍候选")
                if let last = candidates.last, time-last.time < 0.18 {
                    if marker.strength > last.strength { candidates[candidates.count-1] = marker }
                } else { candidates.append(marker) }
            }
        }
        // Large sustained energy changes are offered as transitions, separately labeled.
        let second = max(1,Int(rate/Double(hop)))
        if energy.count > second*2 {
            var last = -10.0
            for i in stride(from: second, to: energy.count-second, by: second/4) {
                let before = energy[(i-second)..<i].reduce(0,+)/Double(second), after = energy[i..<(i+second)].reduce(0,+)/Double(second)
                let t = Double(i*hop)/rate
                if max(before,after) > 0.0001, abs(log((after+1e-7)/(before+1e-7))) > 1.8, t-last > 3 {
                    candidates.append(BeatMarker(time: t,strength: 0.5,kind: "能量转折候选",enabled: false)); last = t
                }
            }
        }
        let beats = candidates.filter { $0.kind != "能量转折候选" }.sorted { $0.time < $1.time }
        var periods: [Double] = []
        for i in beats.indices.dropFirst() { let d = beats[i].time-beats[i-1].time; if d > 0.25 && d < 1.5 { periods.append(d) } }
        periods.sort()
        let bpm = periods.count >= 3 ? 60/periods[periods.count/2] : nil
        let bins = min(2400,samples.count), size = max(1,samples.count/bins)
        var waveform: [Float] = []
        for start in stride(from: 0,to: samples.count,by: size) { waveform.append(samples[start..<min(samples.count,start+size)].map(abs).max() ?? 0) }
        return BeatAnalysis(duration: Double(samples.count)/rate,waveform: waveform,markers: candidates.sorted { $0.time < $1.time },bpm: bpm)
    }
}

enum BeatExport {
    static func xml(source: URL, duration: Double, markers: [BeatMarker], fps: Int) -> String {
        let fps = [24,25,30,50,60].contains(fps) ? fps : 25
        let frames = max(1,Int((duration*Double(fps)).rounded(.down)))
        func t(_ frame: Int) -> String { "\(frame)/\(fps)s" }
        let enabled = markers.filter { $0.enabled && $0.time.isFinite && $0.time >= 0 && $0.time < duration }.sorted { $0.time < $1.time }
        var seen = Set<Int>()
        let tags = enabled.compactMap { m -> String? in
            let frame = min(frames-1,Int((m.time*Double(fps)).rounded()))
            guard seen.insert(frame).inserted else { return nil }
            return "<marker start=\"\(t(frame))\" duration=\"1/\(fps)s\" value=\"\(StyledSubtitles.xmlEscape(m.kind))\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10"><resources>
        <format id="r1" frameDuration="1/\(fps)s" width="1920" height="1080" colorSpace="1-1-1 (Rec. 709)"/>
        <asset id="r2" name="\(StyledSubtitles.xmlEscape(source.lastPathComponent))" start="0s" duration="\(t(frames))" hasAudio="1"><media-rep kind="original-media" src="\(StyledSubtitles.xmlEscape(source.absoluteString))"/></asset>
        </resources><library><event name="CutTools 音乐卡点"><project name="音乐卡点"><sequence format="r1" duration="\(t(frames))" tcStart="0s" tcFormat="NDF"><spine><asset-clip ref="r2" name="音乐卡点" offset="0s" start="0s" duration="\(t(frames))">\(tags)</asset-clip></spine></sequence></project></event></library></fcpxml>
        """
    }
    static func csv(_ markers: [BeatMarker]) -> String {
        "seconds,type,strength\n" + markers.filter(\.enabled).sorted { $0.time < $1.time }.map { String(format: "%.6f",locale: Locale(identifier: "en_US_POSIX"),$0.time) + ",\"" + $0.kind.replacingOccurrences(of: "\"",with: "\"\"") + "\",\($0.strength)" }.joined(separator: "\n")
    }
}
