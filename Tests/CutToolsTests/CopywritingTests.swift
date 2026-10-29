import XCTest
@testable import CutTools

final class CopywritingTests: XCTestCase {
    let draft = CopyDraft(title: "测试稿",openings: ["你是否遇到过这个问题？"],scenes: [ScriptScene(seconds: 60,spoken: "这是完整口播。",visual: "人物近景",caption: "核心观点")])
    func testOutlineIsExplicitlyEditableAndMatchesDuration() throws {
        var brief = CopyBrief(); brief.topic = "如何整理素材"; brief.seconds = 45
        let result = try CopywritingService.outline(brief)
        XCTAssertEqual(result.plannedSeconds,45)
        XCTAssertTrue(result.spokenText.contains("[待补充事实素材]"))
        XCTAssertTrue(result.markdown.contains("## 口播稿"))
    }
    func testInvalidBriefAndModelOutputFail() {
        XCTAssertThrowsError(try CopywritingService.prompt(CopyBrief()))
        XCTAssertThrowsError(try CopyDraft(title: "",openings: [],scenes: []).validated())
    }
    func testLocalRequestAndStructuredResponse() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CopyMockProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var brief = CopyBrief(); brief.topic = "如何整理素材"; brief.facts = "每天花十分钟整理"
        let result = try await CopywritingService.generate(brief,model: "test-local-model",session: session)
        XCTAssertEqual(result.title,"测试稿")
        XCTAssertEqual(result.scenes[0].spoken,"这是完整口播。")
        let project = CopyProject(brief: brief,draft: result)
        let decoded = try JSONDecoder().decode(CopyProject.self,from: JSONEncoder().encode(project))
        XCTAssertEqual(decoded.draft.spokenText,result.spokenText)
    }
    func testServerErrorIsNotAcceptedAsDraft() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CopyMockProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        var brief = CopyBrief(); brief.topic = "测试"
        do { _ = try await CopywritingService.generate(brief,model: "missing-model",session: session); XCTFail("Expected HTTP error") } catch { XCTAssertTrue(error.localizedDescription.contains("Ollama")) }
    }
}

final class CopyMockProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.host,"127.0.0.1")
        XCTAssertEqual(request.url?.path,"/api/generate")
        XCTAssertEqual(request.httpMethod,"POST")
        var bodyData = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0,count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes,maxLength: bytes.count); if count <= 0 { break }; bodyData.append(contentsOf: bytes.prefix(count)) }
        }
        let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
        let missing = body?["model"] as? String == "missing-model"
        let draft = CopyDraft(title: "测试稿",openings: ["你是否遇到过这个问题？"],scenes: [ScriptScene(seconds: 60,spoken: "这是完整口播。",visual: "人物近景",caption: "核心观点")])
        let content = String(decoding: try! JSONEncoder().encode(draft),as: UTF8.self)
        let data = try! JSONSerialization.data(withJSONObject: missing ? ["error":"model not found"] : ["response":content])
        let response = HTTPURLResponse(url: request.url!,statusCode: missing ? 404 : 200,httpVersion: nil,headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive: response,cacheStoragePolicy: .notAllowed); client?.urlProtocol(self,didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BeatSelectionTests: XCTestCase {
    let markers = [BeatMarker(time: 0.5,strength: 1,kind: "强拍候选"),BeatMarker(time: 1,strength: 0.5,kind: "能量转折候选",enabled: false),BeatMarker(time: 1.5,strength: 0.2,kind: "节拍候选"),BeatMarker(time: 2,strength: 1,kind: "手动标记")]
    func testCombinedFilterAndExportSelection() {
        XCTAssertEqual(markers.filter(BeatFilter.highlights.includes).count,2)
        let selected = BeatFilter.highlights.enabledOnly(markers)
        XCTAssertEqual(selected.count,4)
        XCTAssertEqual(selected.filter(\.enabled).map(\.kind),["强拍候选","能量转折候选"])
        XCTAssertFalse(BeatExport.csv(selected).contains("手动标记"))
    }
    @MainActor func testBulkSelectionUndoRestoresExactFlags() {
        let store = BeatStore(); store.markers = markers
        store.keepOnly(.transition)
        XCTAssertEqual(store.markers.filter(\.enabled).map(\.kind),["能量转折候选"])
        store.undoSelection()
        XCTAssertEqual(store.markers,markers)
        store.filter = .strong
        XCTAssertEqual(store.visibleMarkers.count,1)
        XCTAssertEqual(store.markers,markers)
    }
}
