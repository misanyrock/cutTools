import Foundation

@MainActor final class AIModelStore: ObservableObject {
    @Published var config: ModelConfiguration { didSet { persist() } }
    @Published var keyInput = ""
    @Published var voiceoverConfig: VoiceoverConfiguration {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(voiceoverConfig), forKey: "voiceoverConfig") }
    }
    @Published var voiceoverKeyInput = ""
    @Published var voiceoverMessage = "使用百炼语音服务的 Key，与写稿模型配置独立"
    @Published var message = "翻译与写稿共用当前模型；服务商配置分别保存"
    @Published var busy = false
    private var task: Task<Void,Never>?
    init() {
        voiceoverConfig = UserDefaults.standard.data(forKey: "voiceoverConfig").flatMap { try? JSONDecoder().decode(VoiceoverConfiguration.self, from: $0) } ?? VoiceoverConfiguration()
        let provider = UserDefaults.standard.string(forKey:"activeModelProvider").flatMap(ModelProvider.init(rawValue:)) ?? .ollama
        config = UserDefaults.standard.data(forKey:"modelProfile.\(provider.rawValue)").flatMap { try? JSONDecoder().decode(ModelConfiguration.self,from:$0) } ?? provider.defaults
    }
    func persist() {
        UserDefaults.standard.set(config.provider.rawValue,forKey:"activeModelProvider")
        UserDefaults.standard.set(try? JSONEncoder().encode(config),forKey:"modelProfile.\(config.provider.rawValue)")
    }
    func select(_ provider: ModelProvider) {
        guard !busy else { return }
        config = UserDefaults.standard.data(forKey:"modelProfile.\(provider.rawValue)").flatMap { try? JSONDecoder().decode(ModelConfiguration.self,from:$0) } ?? provider.defaults
        keyInput = ""; message = "已切换至 \(provider.title)"
    }
    func saveKey() {
        do {
            _ = try config.endpoint("chat/completions")
            guard !keyInput.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw StudioError.message("请填写新 API Key；留空不会清除已保存的密钥") }
            try ModelCredentials.save(keyInput.trimmingCharacters(in:.whitespacesAndNewlines),config:config)
            keyInput = ""; message = "API Key 已保存到当前服务地址的钥匙串项"
        } catch { message = error.localizedDescription }
    }
    func deleteKey() {
        do { try ModelCredentials.delete(config); keyInput = ""; message = "已删除当前服务地址的 API Key" } catch { message = error.localizedDescription }
    }
    func snapshot() throws -> (ModelConfiguration,String) {
        if config.provider == .ollama { return (config,"") }
        let key = try ModelCredentials.read(config)
        guard !key.isEmpty else { throw StudioError.message("请先在模型设置中保存当前服务地址的 API Key") }
        return (config,key)
    }
    func test() {
        guard !busy else { return }
        do {
            let (profile,key) = try snapshot(); busy = true; message = "正在测试 \(profile.provider.title)…"
            task = Task { @MainActor in
                defer { busy = false }
                do { _ = try await ModelClient.generate(prompt:"Reply with JSON only: {\"ok\":true}",config:profile,key:key); message = "测试成功，\(profile.model) 可返回文本结果" }
                catch { message = error is CancellationError || (error as? URLError)?.code == .cancelled ? "已取消测试" : error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    func cancel() { task?.cancel() }
    func saveVoiceoverKey() {
        do {
            _ = try voiceoverConfig.endpoint()
            let key = voiceoverKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key.rangeOfCharacter(from: .newlines) == nil else { throw StudioError.message("请填写有效的百炼 API Key") }
            try ModelCredentials.save(key, config: voiceoverConfig.credentials)
            voiceoverKeyInput = ""; voiceoverMessage = "配音 Key 已保存到当前语音地址的钥匙串项"
        } catch { voiceoverMessage = error.localizedDescription }
    }
    func deleteVoiceoverKey() {
        do { try ModelCredentials.delete(voiceoverConfig.credentials); voiceoverKeyInput = ""; voiceoverMessage = "配音 Key 已删除" }
        catch { voiceoverMessage = error.localizedDescription }
    }
    func voiceoverSnapshot() throws -> (VoiceoverConfiguration, String) {
        _ = try voiceoverConfig.endpoint()
        let key = try ModelCredentials.read(voiceoverConfig.credentials)
        guard !key.isEmpty else { throw StudioError.message("请先在设置 → AI 配音中保存当前语音地址的百炼 API Key") }
        return (voiceoverConfig, key)
    }
}
