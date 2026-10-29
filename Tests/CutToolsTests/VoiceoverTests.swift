import XCTest
import AVFoundation
@testable import CutTools

final class VoiceoverTests: XCTestCase {
    func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VoiceoverMock.self]
        return URLSession(configuration: config)
    }
    func config(_ scenario: String = "success") -> VoiceoverConfiguration {
        VoiceoverConfiguration(baseURL: "https://voice.test/\(scenario)", model: "qwen3-tts-flash")
    }

    func testChunkingPreservesWholeScriptAndHonorsLimit() throws {
        let text = String(repeating: "这是一段自然的口播，含有 English 和😀。", count: 70)
        let chunks = try VoiceoverService.chunks(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.utf16.count <= 500 })
        XCTAssertEqual(try VoiceoverService.chunks("短稿"), ["短稿"])
        XCTAssertThrowsError(try VoiceoverService.chunks(" \n "))
        XCTAssertThrowsError(try VoiceoverService.chunks(String(repeating: "字", count: 20001)))
        XCTAssertThrowsError(try VoiceoverService.chunks("a" + String(repeating: "\u{0301}", count: 501)))
    }

    func testVoiceRequestsAndCredentialIsolation() throws {
        for voice in NarrationVoice.allCases {
            let request = try VoiceoverService.request(text: "你好", voice: voice, config: config(), key: "test-secret")
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "qwen3-tts-flash")
            XCTAssertEqual((body["input"] as? [String: String])?["voice"], voice.rawValue)
            XCTAssertEqual((body["input"] as? [String: String])?["text"], "你好")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")
        }
        XCTAssertNotEqual(VoiceoverConfiguration().credentials.credentialAccount, ModelProvider.qwen.defaults.credentialAccount)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(config()), as: UTF8.self).contains("test-secret"))
        for address in ["http://voice.test", "https://key@voice.test", "https://voice.test?key=secret", "https://voice.test#fragment"] {
            let unsafe = VoiceoverConfiguration(baseURL: address)
            XCTAssertThrowsError(try VoiceoverService.request(text: "你好", voice: .ethan, config: unsafe, key: "key"))
        }
        XCTAssertThrowsError(try VoiceoverService.request(text: "你好", voice: .ethan, config: config(), key: ""))
        XCTAssertThrowsError(try VoiceoverService.request(text: "你好", voice: .ethan, config: config(), key: "key\r\ninjected"))
    }

    func testAudioDownloadUpgradesHTTPSAndRejectsUntrustedURLs() throws {
        let url = try VoiceoverService.audioURL("http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/test.wav?Signature=example")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.query, "Signature=example")
        for value in ["file:///etc/passwd", "http://127.0.0.1/a.wav", "https://evil.test/a.wav", "https://aliyuncs.com.evil.test/a.wav", "https://key@bucket.aliyuncs.com/a.wav"] {
            XCTAssertThrowsError(try VoiceoverService.audioURL(value))
        }
    }

    func testServiceValidatesErrorsAndDoesNotForwardKeyToDownload() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let audio = try await VoiceoverService.synthesize(text: "Hello", voice: .serena, config: config(), key: "test-secret", session: session)
        XCTAssertEqual(audio, VoiceoverMock.wav())
        for scenario in ["unauthorized", "logical-error", "invalid-audio", "unsafe-url"] {
            do {
                _ = try await VoiceoverService.synthesize(text: "Hello", voice: .ethan, config: config(scenario), key: "test-secret", session: session)
                XCTFail("Expected failure: \(scenario)")
            } catch { XCTAssertFalse(error.localizedDescription.contains("test-secret")) }
        }
    }

    @MainActor func testFullGenerationSavingFailureAndCancellationKeepPreviousAudio() async throws {
        let session = session(); defer { session.invalidateAndCancel() }
        let store = VoiceoverStore()
        let text = String(repeating: "这是配音内容。", count: 90)
        let draft = CopyDraft(title: "不应朗读的标题", openings: ["不应朗读的备选"], scenes: [ScriptScene(seconds: 10, spoken: text, visual: "不应朗读的画面", caption: "不应朗读的屏幕文字")])
        store.voice = .mochi
        store.generate(text: draft.spokenText, config: config(), key: "test-secret", session: session)
        await store.task?.value
        XCTAssertFalse(store.busy)
        let result = try XCTUnwrap(store.result, store.message)
        defer { try? FileManager.default.removeItem(at: result.url.deletingLastPathComponent()) }
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.voice, .mochi)
        let audio = try AVAudioFile(forReading: result.url)
        XCTAssertEqual(audio.length, Int64(try VoiceoverService.chunks(text).count * 2400))
        let saved = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: saved) }
        try store.save(to: saved)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: result.url))
        try store.save(to: saved)
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: result.url))

        store.generate(text: "新稿", config: config("invalid-audio"), key: "test-secret", session: session)
        await store.task?.value
        XCTAssertEqual(store.result?.url, result.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.path))
        store.generate(text: "需要取消", config: config("slow"), key: "test-secret", session: session)
        try await Task.sleep(nanoseconds: 50_000_000)
        store.cancel()
        await store.task?.value
        XCTAssertFalse(store.busy)
        XCTAssertEqual(store.result?.url, result.url)
        XCTAssertTrue(store.message.contains("已取消"))
    }
}

final class VoiceoverMock: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    static func wav() -> Data {
        var data = Data()
        func string(_ value: String) { data.append(contentsOf: value.utf8) }
        func word(_ value: UInt32, bytes: Int) { for index in 0..<bytes { data.append(UInt8((value >> (8 * index)) & 255)) } }
        string("RIFF"); word(36 + 4800, bytes: 4); string("WAVEfmt "); word(16, bytes: 4)
        word(1, bytes: 2); word(1, bytes: 2); word(24000, bytes: 4); word(48000, bytes: 4)
        word(2, bytes: 2); word(16, bytes: 2); string("data"); word(4800, bytes: 4)
        data.append(Data(repeating: 0, count: 4800)); return data
    }
    override func startLoading() {
        if request.url!.path.contains("slow") { return }
        let download = request.url!.host!.hasSuffix(".aliyuncs.com")
        let unauthorized = request.url!.path.contains("unauthorized")
        let status = unauthorized ? 401 : 200
        let data: Data
        if download {
            // A forwarded bearer token would make the supposedly successful path fail.
            data = request.value(forHTTPHeaderField: "Authorization") != nil || request.url!.path.contains("invalid-audio") ? Data("not an audio file".utf8) : Self.wav()
        } else if unauthorized { data = Data("test-secret".utf8) }
        else if request.url!.path.contains("logical-error") { data = Data(#"{"code":"InvalidApiKey","message":"test-secret"}"#.utf8) }
        else {
            let url = request.url!.path.contains("unsafe-url") ? "https://evil.test/audio.wav" : "http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/\(request.url!.path.contains("invalid-audio") ? "invalid-audio" : "success").wav"
            data = try! JSONSerialization.data(withJSONObject: ["output": ["finish_reason": "stop", "audio": ["url": url]]])
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
