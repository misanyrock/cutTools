import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor final class CopyStore: ObservableObject {
    @Published var brief: CopyBrief { didSet { persist() } }
    @Published var draft: CopyDraft? { didSet { persist() } }
    let defaults: UserDefaults
    @Published var versions: [CopyVersion] = []
    @Published var templates: [CreativeTemplate] = []
    @Published var pendingRewrite: RewriteProposal?
    @Published var busy = false
    @Published var message = "先写清主题、受众和素材，再生成完整初稿"
    var task: Task<Void,Never>?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        brief = defaults.data(forKey: "copyBrief").flatMap { try? JSONDecoder().decode(CopyBrief.self,from: $0) } ?? CopyBrief()
        draft = defaults.data(forKey: "copyDraft").flatMap { try? JSONDecoder().decode(CopyDraft.self,from: $0) }
        versions = defaults.data(forKey:"copyVersions").flatMap { try? JSONDecoder().decode([CopyVersion].self,from:$0) } ?? []
        versions = Array(versions.filter { (try? $0.draft.validated()) != nil }.suffix(30))
        templates = defaults.data(forKey:"creativeTemplates").flatMap { try? JSONDecoder().decode([CreativeTemplate].self,from:$0) } ?? []
    }
    func persist() {
        defaults.set(try? JSONEncoder().encode(brief),forKey: "copyBrief")
        if let draft { defaults.set(try? JSONEncoder().encode(draft),forKey: "copyDraft") }
    }
    func generate(offline: Bool, config: ModelConfiguration = ModelProvider.ollama.defaults, key: String = "") {
        guard !busy else { return }
        let snapshot = brief
        if offline {
            do { checkpoint("生成提纲前"); draft = try CopywritingService.outline(snapshot); checkpoint("写作提纲"); message = "已生成写作提纲（非 AI 文案），方括号内容需要你填写" }
            catch { message = error.localizedDescription }; return
        }
        busy = true; message = "\(config.provider.title) 正在写稿，可取消；已有文案会保留到新稿成功生成"
        task = Task { @MainActor in
            defer { busy = false }
            do {
                let result = try await CopywritingService.generate(snapshot,config:config,key:key)
                try Task.checkCancellation(); checkpoint("生成新稿前"); draft = result; checkpoint("AI 初稿")
                message = "初稿已生成，请核对事实并修改。口播估算按每秒约 3.5 字，仅供参考。"
            } catch { message = error is CancellationError || (error as? URLError)?.code == .cancelled ? "已取消，已有文案保持不变" : error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
    func copyText() {
        guard let draft else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(draft.spokenText,forType: .string); message = "口播稿已复制"
    }
    func save(project: Bool) {
        guard let draft else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "文案." + (project ? "json" : "md")
        if panel.runModal() == .OK, let url = panel.url {
            do {
                if project { try JSONEncoder().encode(CopyProject(brief: brief,draft: draft,versions:versions)).write(to: url,options: .atomic) }
                else { try draft.markdown.write(to: url,atomically: true,encoding: .utf8) }
                message = "已保存 \(url.lastPathComponent)"
            } catch { message = error.localizedDescription }
        }
    }
    func open() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { let project = try JSONDecoder().decode(CopyProject.self,from: Data(contentsOf: url)); _ = try CopywritingService.prompt(project.brief); let validated = try project.draft.validated(); checkpoint("载入工程前"); brief = project.brief; draft = validated; if let imported = project.versions { versions.append(contentsOf:imported.filter { (try? $0.draft.validated()) != nil }.suffix(30).map { var v = $0; v.id = UUID(); return v }); versions = Array(versions.suffix(30)); saveVersions() }; message = "已载入文案工程" }
            catch { message = "无法载入：\(error.localizedDescription)" }
        }
    }
}
