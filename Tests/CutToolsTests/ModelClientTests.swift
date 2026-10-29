import XCTest
@testable import CutTools

final class ModelClientTests: XCTestCase {
    func testAllOnlinePresetsUseCompatibleChatAndBearer() throws {
        for provider in [ModelProvider.deepseek,.qwen,.doubao,.compatible] {
            var config = provider.defaults
            config.model = "test-model"
            if provider == .compatible { config.baseURL = "https://example.test/v1" }
            let request = try ModelClient.request(prompt:"Return JSON",config:config,key:"unit-test-key")
            XCTAssertTrue(request.url!.path.hasSuffix("/chat/completions"))
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer unit-test-key")
            let body = try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any]
            XCTAssertEqual(body["model"] as? String,"test-model")
            XCTAssertNotNil(body["messages"]); XCTAssertNil(body["prompt"]); XCTAssertNil(body["response_format"])
            if provider == .qwen { XCTAssertEqual(body["enable_thinking"] as? Bool,false) }
            let saved = String(decoding:try JSONEncoder().encode(config),as:UTF8.self)
            XCTAssertFalse(saved.contains("unit-test-key"))
        }
    }
    func testOllamaNeverReceivesBearerKey() throws {
        let request = try ModelClient.request(prompt:"JSON",config:ModelProvider.ollama.defaults,key:"unused-key")
        XCTAssertEqual(request.url!.path,"/api/generate")
        XCTAssertNil(request.value(forHTTPHeaderField:"Authorization"))
    }
    func testUnsafeEndpointsAndMissingKeyRejected() throws {
        for address in ["http://api.example.test/v1","https://key@example.test/v1","https://example.test/v1?key=secret","https://example.test/v1#secret"] {
            let config = ModelConfiguration(provider:.compatible,baseURL:address,model:"test")
            XCTAssertThrowsError(try config.endpoint("chat/completions"))
        }
        let remoteOllama = ModelConfiguration(provider:.ollama,baseURL:"http://example.test",model:"test")
        XCTAssertThrowsError(try remoteOllama.endpoint("api/generate"))
        XCTAssertThrowsError(try ModelClient.request(prompt:"JSON",config:ModelProvider.deepseek.defaults,key:""))
    }
    func testFullEndpointIsNotAppendedTwiceAndKeyAccountsAreIsolated() throws {
        let a = ModelConfiguration(provider:.compatible,baseURL:"https://one.test/v1/chat/completions",model:"m")
        let b = ModelConfiguration(provider:.compatible,baseURL:"https://two.test/v1",model:"m")
        XCTAssertEqual(try a.endpoint("chat/completions").path,"/v1/chat/completions")
        XCTAssertNotEqual(a.credentialAccount,b.credentialAccount)
    }
    func testCompatibleResponseUnwrapsJSONAndRejectsTruncation() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OnlineModelMock.self]
        let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let profile = ModelConfiguration(provider:.compatible,baseURL:"https://mock.test/v1",model:"test")
        let text = try await ModelClient.generate(prompt:"normal",config:profile,key:"test-key",session:session)
        XCTAssertEqual(text,"{\"translation\":\"hello\"}")
        do { _ = try await ModelClient.generate(prompt:"truncate",config:profile,key:"test-key",session:session); XCTFail("Truncated output must fail") } catch { XCTAssertTrue(error.localizedDescription.contains("截断")) }
    }
    func testAuthenticationErrorDoesNotEchoServerSecrets() async {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OnlineModelMock.self]
        let session = URLSession(configuration:config); defer { session.invalidateAndCancel() }
        let profile = ModelConfiguration(provider:.compatible,baseURL:"https://mock.test/fail",model:"test")
        do { _ = try await ModelClient.generate(prompt:"JSON",config:profile,key:"test-key",session:session); XCTFail("Expected 401") } catch { XCTAssertTrue(error.localizedDescription.contains("401")); XCTAssertFalse(error.localizedDescription.contains("test-key")) }
    }
}

final class OnlineModelMock: URLProtocol {
    override class func canInit(with request:URLRequest) -> Bool { true }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating:0,count:4096); while stream.hasBytesAvailable { let count = stream.read(&buffer,maxLength:buffer.count); if count <= 0 { break }; data.append(contentsOf:buffer.prefix(count)) } }
        let body = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
        let messages = body?["messages"] as? [[String:String]]
        let truncation = messages?.first?["content"] == "truncate"
        let status = request.url!.path.contains("fail") ? 401 : 200
        let object: [String:Any] = status == 401 ? ["error":"test-key"] : ["choices":[["finish_reason":truncation ? "length" : "stop","message":["content":"```json\n{\"translation\":\"hello\"}\n```"]]]]
        let response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:object)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
