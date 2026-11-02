import Foundation

enum SentenceBeats {
    static func transcribed(_ data: Data) throws -> [Cue] {
        struct Transcript: Decodable {
            struct Part: Decodable {
                struct Offsets: Decodable { var from: Int; var to: Int }
                var offsets: Offsets; var text: String
            }
            var transcription: [Part]
        }
        let parts = try JSONDecoder().decode(Transcript.self, from: data).transcription
        guard parts.allSatisfy({ $0.offsets.from >= 0 && $0.offsets.to >= $0.offsets.from && $0.offsets.to <= 1_801_000 }),
              zip(parts, parts.dropFirst()).allSatisfy({ $0.offsets.from <= $1.offsets.from }) else {
            throw StudioError.message("Whisper 返回了无效的句子时间")
        }
        var sentences: [Cue] = [], current: Cue?
        for (index, part) in parts.enumerated() {
            let text = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let start = Double(part.offsets.from) / 1000, end = Double(part.offsets.to) / 1000
            let punctuation = text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
            if let sentence = current, start - sentence.end >= 0.6 && !punctuation {
                sentences.append(sentence); current = nil
            }
            if current == nil {
                guard !punctuation, end > start else { continue }
                current = Cue(start: start, end: end, text: part.text, sourceNumber: sentences.count + 1)
            } else {
                current!.text += part.text
                current!.end = max(current!.end, end)
            }
            let next = index + 1 < parts.count ? parts[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines).first : nil
            let numericSeparator = [".", ","].contains(text) && index > 0 && parts[index - 1].text.last?.isNumber == true && next?.isNumber == true
            if text.contains(where: { "。！？!?；;，,.".contains($0) }) && !numericSeparator, let sentence = current {
                sentences.append(sentence); current = nil
            }
        }
        if let current { sentences.append(current) }
        return sentences
    }

    static func markers(_ cues: [Cue], duration: Double, fps: Int) throws -> [BeatMarker] {
        guard duration.isFinite, duration > 0, duration <= 1800, [24,25,30,50,60].contains(fps) else {
            throw StudioError.message("音频时长或帧率无效，单次支持 30 分钟以内")
        }
        let sentences = cues.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !sentences.isEmpty else { throw StudioError.message("字幕中没有可用的句子") }
        guard sentences.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.start < duration && $0.end > $0.start }) else {
            throw StudioError.message("字幕时间无效或句首超出音频范围，请确认字幕与当前音频匹配且从同一起点计时")
        }
        let frames = max(1, Int((duration * Double(fps)).rounded(.down)))
        var seen = Set<Int>()
        return sentences.sorted { $0.start < $1.start }.compactMap { cue in
            let frame = min(frames - 1, Int((cue.start * Double(fps)).rounded()))
            guard seen.insert(frame).inserted else { return nil }
            let text = cue.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return BeatMarker(time: Double(frame) / Double(fps), strength: 1, kind: "句子：\(text.prefix(60))")
        }
    }
}
