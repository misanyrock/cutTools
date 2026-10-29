import XCTest
import Foundation
@testable import CutTools

final class CreativeWorkflowTests:XCTestCase {
    func draft() -> CopyDraft { CopyDraft(title:"稿件",openings:["开场"],scenes:[ScriptScene(seconds:8,spoken:"先看路，再看景。",visual:"公路",caption:"开场"),ScriptScene(seconds:12,spoken:"慢一点，看看山。",visual:"山",caption:"重点"),ScriptScene(seconds:10,spoken:"留下时间感受风景。",visual:"空镜",caption:"结尾")]) }
    func testSceneIDsSurviveRoundTripAndLegacyStillLoads() throws {
        let original = draft(), decoded = try JSONDecoder().decode(CopyDraft.self,from:JSONEncoder().encode(original))
        XCTAssertEqual(original,decoded)
        let legacy = Data("{\"seconds\":3,\"spoken\":\"旧稿\",\"visual\":\"景\",\"caption\":\"词\"}".utf8)
        XCTAssertEqual(try JSONDecoder().decode(ScriptScene.self,from:legacy).spoken,"旧稿")
    }
    func testTemplateDoesNotOverwriteFactsOrTopic() throws {
        var original = CopyBrief(); original.topic = "今天的故事"; original.facts = "保留我的素材"; original.audience = "旅行朋友"
        let template = CreativeTemplate(name:"旅行",brief:original)
        var target = CopyBrief(); target.topic = "新主题"; target.facts = "新素材"
        let applied = template.applying(to:target)
        XCTAssertEqual(applied.topic,"新主题"); XCTAssertEqual(applied.facts,"新素材"); XCTAssertEqual(applied.audience,"旅行朋友")
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(template),as:UTF8.self).contains("保留我的素材"))
    }
    @MainActor func testRewriteOnlyTouchesTargetAndHistoryRestores() throws {
        let suite = "copy-test-"+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let store = CopyStore(defaults:defaults), original = draft(); store.draft = original
        var replacement = original.scenes[1]; replacement.spoken = "新的文字"
        let proposal = RewriteProposal(original:original.scenes[1],replacement:replacement,mode:"更精简")
        store.applyRewrite(proposal)
        XCTAssertEqual(store.draft!.scenes[0],original.scenes[0]); XCTAssertEqual(store.draft!.scenes[2],original.scenes[2]); XCTAssertEqual(store.draft!.scenes[1].id,original.scenes[1].id)
        let previous = store.versions.first!; store.restore(previous)
        XCTAssertEqual(store.draft!,original)
        store.draft!.scenes[1].spoken = "用户刚改过"
        store.applyRewrite(proposal)
        XCTAssertEqual(store.draft!.scenes[1].spoken,"用户刚改过")
        let reopened = CopyStore(defaults:defaults); XCTAssertFalse(reopened.versions.isEmpty)
    }
    func testMusicAlignmentAnchorsAndPreservesGaps() throws {
        let d = draft(), music = URL(fileURLWithPath:"/tmp/music.wav")
        let plan = try MusicAlignment.create(draft:d,music:music,musicDuration:60,start:10,end:40,markers:[],keyScene:1,anchor:20,breath:0.5,fps:25)
        XCTAssertEqual(plan.rows.first!.start,0); XCTAssertEqual(plan.rows.last!.end,30)
        XCTAssertEqual(plan.rows.first { $0.sceneID == d.scenes[1].id }!.start,10)
        XCTAssertEqual(plan.rows.filter { $0.sceneID == nil }.count,2)
        for (a,b) in zip(plan.rows,plan.rows.dropFirst()) { XCTAssertEqual(a.end,b.start,accuracy:0.0001) }
        XCTAssertTrue(XMLParser(data:Data(plan.fcpxml.utf8)).parse()); XCTAssertTrue(plan.fcpxml.contains("start=\"500/25s\""))
        XCTAssertEqual(plan.subtitles.first!.start,0)
        XCTAssertThrowsError(try MusicAlignment.create(draft:d,music:music,musicDuration:60,start:0,end:1,markers:[],keyScene:1,anchor:0.1,breath:1,fps:25))
    }
    func testSceneRewriterUsesConfiguredModelAndKeepsTiming() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RewriteMock.self]
        let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let scene = draft().scenes[0]
        let result = try await SceneRewriter.rewrite(scene,mode:"更精简",brief:CopyBrief(),config:ModelConfiguration(provider:.compatible,baseURL:"https://mock.test/v1",model:"test"),key:"test",session:session)
        XCTAssertEqual(result.spoken,"精简后的口播"); XCTAssertEqual(result.id,scene.id); XCTAssertEqual(result.seconds,scene.seconds)
    }
}
final class RewriteMock:URLProtocol {
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url!.path,"/v1/chat/completions")
        let content = "{\"spoken\":\"精简后的口播\",\"visual\":\"镜头\",\"caption\":\"文字\"}"
        let data = try! JSONSerialization.data(withJSONObject:["choices":[["finish_reason":"stop","message":["content":content]]]])
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed); client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
