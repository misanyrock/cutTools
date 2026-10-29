import Foundation
import Security

enum ModelProvider: String, Codable, CaseIterable, Identifiable {
    case ollama, deepseek, qwen, doubao, compatible
    var id: String { rawValue }
    var title: String { switch self { case .ollama: return "本地 Ollama"; case .deepseek: return "DeepSeek"; case .qwen: return "千问 · 阿里云百炼"; case .doubao: return "豆包 · 火山方舟"; case .compatible: return "其他兼容接口" } }
    var defaults: ModelConfiguration {
        switch self {
        case .ollama: return .init(provider: self, baseURL: "http://127.0.0.1:11434", model: UserDefaults.standard.string(forKey: "copyModel") ?? UserDefaults.standard.string(forKey: "translationModel") ?? "qwen3:8b")
        case .deepseek: return .init(provider: self, baseURL: "https://api.deepseek.com", model: "deepseek-flash")
        case .qwen: return .init(provider: self, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-plus")
        case .doubao: return .init(provider: self, baseURL: "https://ark.cn-beijing.volces.com/api/v3", model: "")
        case .compatible: return .init(provider: self, baseURL: "", model: "")
        }
    }
}
struct ModelConfiguration: Codable, Equatable {
    var provider: ModelProvider
    var baseURL: String
    var model: String
    var jsonMode = false
    var credentialAccount: String { provider.rawValue + "|" + baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    func endpoint(_ operation: String) throws -> URL {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              provider == .ollama ? (["http","https"].contains(components.scheme ?? "") && ["localhost","127.0.0.1","::1"].contains(host)) : components.scheme == "https",
              let url = components.url else { throw StudioError.message("在线接口需填写有效 HTTPS Base URL；Ollama 仅支持本机地址，地址不能包含密钥、查询参数或用户名") }
        if url.path.hasSuffix("/chat/completions") && operation == "chat/completions" { return url }
        return url.appendingPathComponent(operation)
    }
}
struct ModelCredentials {
    static let service = "local.cuttools.model-api-keys"
    static func read(_ config: ModelConfiguration) throws -> String {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:config.credentialAccount,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else { throw StudioError.message("无法读取钥匙串中的 API Key（\(status)）") }
        return String(decoding:data,as:UTF8.self)
    }
    static func save(_ key: String, config: ModelConfiguration) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:config.credentialAccount]
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if update == errSecItemNotFound { var add = query; add[kSecValueData as String] = data; let status = SecItemAdd(add as CFDictionary,nil); guard status == errSecSuccess else { throw StudioError.message("保存 API Key 失败（\(status)）") } }
        else if update != errSecSuccess { throw StudioError.message("更新 API Key 失败（\(update)）") }
    }
    static func delete(_ config: ModelConfiguration) throws {
        let status = SecItemDelete([kSecClass:kSecClassGenericPassword,kSecAttrService:service,kSecAttrAccount:config.credentialAccount] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StudioError.message("删除 API Key 失败（\(status)）") }
    }
}

private final class NoModelRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
enum ModelClient {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral; config.urlCredentialStorage = nil; config.httpCookieStorage = nil
        return URLSession(configuration:config,delegate:NoModelRedirect(),delegateQueue:nil)
    }()
    static func request(prompt: String, config: ModelConfiguration, key: String) throws -> URLRequest {
        guard !config.model.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw StudioError.message("请先填写模型名称；豆包也可填写已开通的推理接入点 ID") }
        let local = config.provider == .ollama
        var request = URLRequest(url:try config.endpoint(local ? "api/generate" : "chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 300; request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body: [String:Any]
        if local { body = ["model":config.model,"prompt":prompt,"stream":false,"format":"json","options":["num_predict":6000]] }
        else {
            guard !key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, !key.contains("\n"), !key.contains("\r") else { throw StudioError.message("请在模型设置中保存有效 API Key") }
            request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization")
            body = ["model":config.model,"messages":[["role":"user","content":prompt]],"stream":false]
            if config.provider == .qwen { body["enable_thinking"] = false }
            if config.jsonMode { body["response_format"] = ["type":"json_object"] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject:body); return request
    }
    static func generate(prompt: String, config: ModelConfiguration, key: String = "", session: URLSession = ModelClient.session) async throws -> String {
        let request = try request(prompt:prompt,config:config,key:key)
        let (data,response) = try await session.data(for:request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let hint: String
            switch status { case 401,403: hint = "请检查 API Key、地域与模型权限"; case 404: hint = "请检查 Base URL 和模型/接入点 ID"; case 429: hint = "请求过于频繁或额度不足，请稍后重试"; case 300...399: hint = "接口发生重定向，请直接填写最终接口地址"; default: hint = "服务未完成请求，请稍后重试" }
            throw StudioError.message("\(config.provider.title) 请求失败（HTTP \(status)）：\(hint)")
        }
        let text: String
        if config.provider == .ollama {
            struct Local: Decodable { var response: String; var done_reason: String? }
            let result = try JSONDecoder().decode(Local.self,from:data)
            guard result.done_reason != "length" else { throw StudioError.message("模型输出达到长度限制，请缩短需求后重试") }; text = result.response
        } else {
            struct Message: Decodable { var content: String? }
            struct Choice: Decodable { var message: Message; var finish_reason: String? }
            struct Remote: Decodable { var choices: [Choice] }
            guard let choice = try JSONDecoder().decode(Remote.self,from:data).choices.first else { throw StudioError.message("模型没有返回结果") }
            guard choice.finish_reason != "length", choice.finish_reason != "content_filter" else { throw StudioError.message("模型输出被截断或未通过服务审核，请调整需求后重试") }
            text = choice.message.content ?? ""
        }
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StudioError.message("模型返回空内容，请换用支持文本输出的模型") }
        // Some compatible APIs wrap valid JSON in a Markdown code block.
        if trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), let newline = trimmed.firstIndex(of:"\n") { return String(trimmed[trimmed.index(after:newline)..<trimmed.index(trimmed.endIndex,offsetBy:-3)]).trimmingCharacters(in:.whitespacesAndNewlines) }
        return trimmed
    }
}
