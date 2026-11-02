import XCTest
@testable import CutTools

final class SentenceBeatTests: XCTestCase {
    func testWhisperWordsSplitByPunctuationAndPauseWithoutInventingStartTimes() throws {
        let parts: [(Int, Int, String)] = [(0, 60, ""), (60, 700, "今天"), (700, 1600, "天气很好"),
                                          (1600, 1920, ","), (1920, 3000, "我们一起出发"), (3000, 3000, "。"),
                                          (4000, 4300, "请带上"), (4300, 5000, "相机"),
                                          (5700, 6000, "最后一句")]
        let data = try JSONSerialization.data(withJSONObject: ["transcription": parts.map { ["offsets": ["from": $0.0, "to": $0.1], "text": $0.2] as [String: Any] }])
        let cues = try SentenceBeats.transcribed(data)
        XCTAssertEqual(cues.map(\.start), [0.06, 1.92, 4, 5.7])
        XCTAssertEqual(cues.map(\.text), ["今天天气很好,", "我们一起出发。", "请带上相机", "最后一句"])
        let invalid = Data(#"{"transcription":[{"offsets":{"from":20,"to":10},"text":"错误"}]}"#.utf8)
        XCTAssertThrowsError(try SentenceBeats.transcribed(invalid))
        let decimal = Data(#"{"transcription":[{"offsets":{"from":0,"to":100},"text":"3"},{"offsets":{"from":100,"to":200},"text":"."},{"offsets":{"from":200,"to":300},"text":"5"},{"offsets":{"from":300,"to":400},"text":" metres."}]}"#.utf8)
        XCTAssertEqual(try SentenceBeats.transcribed(decimal).map(\.text), ["3.5 metres."])
    }

    func testSentenceStartsSortQuantizeDeduplicateAndKeepText() throws {
        let cues = [
            Cue(start: 1.51, end: 2, text: "第二句\nHello & goodbye", sourceNumber: 2),
            Cue(start: 0.01, end: 1, text: "第一句", sourceNumber: 1),
            Cue(start: 0.015, end: 1, text: "同帧重复", sourceNumber: 3),
            Cue(start: 2.99, end: 3.1, text: "最后一句", sourceNumber: 4),
            Cue(start: 2, end: 2.5, text: " \n", sourceNumber: 5)
        ]
        let markers = try SentenceBeats.markers(cues, duration: 3, fps: 25)
        XCTAssertEqual(markers.map(\.time), [0, 1.52, 2.96])
        XCTAssertTrue(markers.allSatisfy { $0.enabled && BeatFilter.sentence.includes($0) })
        XCTAssertEqual(markers[1].kind, "句子：第二句 Hello & goodbye")
        let xml = BeatExport.xml(source: URL(fileURLWithPath: "/tmp/audio.wav"), duration: 3, markers: markers, fps: 25)
        XCTAssertTrue(xml.contains("第二句 Hello &amp; goodbye"))
        XCTAssertTrue(xml.contains("start=\"38/25s\""))
        XCTAssertTrue(BeatExport.csv(markers).contains("句子：第一句"))
        let session = BeatSession(source: URL(fileURLWithPath: "/tmp/audio.wav"), duration: 3, markers: markers, fps: 25)
        XCTAssertEqual(try JSONDecoder().decode(BeatSession.self, from: JSONEncoder().encode(session)).markers, markers)
    }

    func testInvalidOrUnmatchedSubtitlesDoNotGenerateGuessedTimes() {
        for cue in [Cue(start: .nan, end: 1, text: "错误", sourceNumber: 1),
                    Cue(start: -1, end: 1, text: "错误", sourceNumber: 1),
                    Cue(start: 3, end: 4, text: "超出音频", sourceNumber: 1),
                    Cue(start: 1, end: 0.5, text: "时间倒置", sourceNumber: 1)] {
            XCTAssertThrowsError(try SentenceBeats.markers([cue], duration: 3, fps: 25))
        }
        XCTAssertThrowsError(try SentenceBeats.markers([], duration: 3, fps: 25))
        XCTAssertThrowsError(try SentenceBeats.markers([], duration: .infinity, fps: 25))
        XCTAssertThrowsError(try SentenceBeats.markers([], duration: 3, fps: 0))
    }

    @MainActor func testSentenceFilterBulkUndoAndMontage() throws {
        let sentences = try SentenceBeats.markers([Cue(start: 1, end: 2, text: "一句", sourceNumber: 1), Cue(start: 2, end: 3, text: "两句", sourceNumber: 2)], duration: 4, fps: 25)
        let store = BeatStore()
        store.markers = sentences + [BeatMarker(time: 0.5, strength: 1, kind: "手动标记")]
        let original = store.markers
        store.filter = .sentence
        XCTAssertEqual(store.visibleMarkers, sentences)
        store.keepOnly(.sentence)
        XCTAssertEqual(store.markers.filter(\.enabled), sentences)
        let asset = MontageAsset(url: URL(fileURLWithPath: "/tmp/clip.mp4"), duration: 10, width: 1920, height: 1080, frameRate: 25)
        let slots = try MontagePlanner.build(assets: [asset], markers: store.markers, start: 0, end: 4, minimum: 0.1, fps: 25)
        XCTAssertEqual(slots.map(\.start), [0, 1, 2])
        store.undoSelection()
        XCTAssertEqual(store.markers, original)
    }

    @MainActor func waitForAnalysis(_ store: BeatStore) async throws {
        for _ in 0..<400 {
            if !store.busy { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        store.cancel()
        throw StudioError.message("句子分析测试超时：\(store.message)")
    }

    @MainActor func testAudioAnalysisWithSubtitlesAndWhisperOutputPreservesOldMarkersOnFailure() async throws {
        let workspace = Workspace()
        guard let ffmpeg = workspace.ffmpeg else { throw XCTSkip("未安装 FFmpeg") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("voice.wav")
        _ = try await workspace.checkedProcess(ffmpeg, ["-nostdin", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", audio.path])
        let store = BeatStore(); store.load(audio)
        let cues = [Cue(start: 0.5, end: 1, text: "第一句", sourceNumber: 1), Cue(start: 1.5, end: 2, text: "第二句", sourceNumber: 2)]
        store.analyze(ffmpeg: ffmpeg, sentenceCues: cues)
        try await waitForAnalysis(store)
        XCTAssertEqual(store.markers.map(\.time), [0.52, 1.52], store.message)
        XCTAssertFalse(store.waveform.isEmpty)
        XCTAssertEqual(store.filter, .sentence)
        let previous = store.markers
        store.analyze(ffmpeg: ffmpeg, sentenceCues: [Cue(start: 5, end: 6, text: "不匹配", sourceNumber: 1)])
        try await waitForAnalysis(store)
        XCTAssertEqual(store.markers, previous)

        let fakeWhisper = directory.appendingPathComponent("whisper-test")
        let script = """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -f) input="$2"; shift ;;
            -of) output="$2"; shift ;;
          esac
          shift
        done
        [ -s "$input" ] || exit 2
        /bin/cat > "$output.json" <<'JSON'
        {"transcription":[{"offsets":{"from":300,"to":1000},"text":"Whisper 测试句。"}]}
        JSON
        """
        try script.write(to: fakeWhisper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeWhisper.path)
        store.analyze(ffmpeg: ffmpeg, whisper: (fakeWhisper.path, audio.path, "zh"))
        try await waitForAnalysis(store)
        XCTAssertEqual(store.markers.map(\.time), [0.32], store.message)
        XCTAssertTrue(store.markers.first?.kind.contains("Whisper 测试句") ?? false)
        let transcribed = store.markers
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: fakeWhisper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeWhisper.path)
        store.analyze(ffmpeg: ffmpeg, whisper: (fakeWhisper.path, audio.path, "zh"))
        for _ in 0..<400 {
            if store.message.contains("Whisper 正在") { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        store.cancel()
        try await waitForAnalysis(store)
        XCTAssertEqual(store.markers, transcribed)
        XCTAssertTrue(store.message.contains("已取消"), store.message)
    }
}
