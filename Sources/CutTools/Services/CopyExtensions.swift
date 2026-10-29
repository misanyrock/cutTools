import Foundation
import AppKit
import UniformTypeIdentifiers

extension CopyStore {
    func checkpoint(_ label:String) {
        guard let draft else { return }
        versions.append(CopyVersion(label:label,draft:draft)); versions = Array(versions.suffix(30)); saveVersions()
    }
    func saveVersions() { defaults.set(try? JSONEncoder().encode(versions),forKey:"copyVersions") }
    func restore(_ version:CopyVersion) {
        guard !busy else { return }; checkpoint("恢复版本前"); draft = version.draft; pendingRewrite = nil; message = "已恢复：\(version.label)，恢复前内容已保留在版本历史"
    }
    func rewrite(sceneID:UUID,mode:String,config:ModelConfiguration,key:String) {
        guard !busy,let original = draft?.scenes.first(where:{ $0.id == sceneID }) else { return }
        let brief = brief; busy = true; message = "正在局部改写：\(mode)，原段落保持不变"
        task = Task { @MainActor in
            defer { busy = false }
            do { let replacement = try await SceneRewriter.rewrite(original,mode:mode,brief:brief,config:config,key:key); try Task.checkCancellation(); pendingRewrite = RewriteProposal(original:original,replacement:replacement,mode:mode); message = "改写完成，请比较后决定是否应用" }
            catch { message = error is CancellationError || (error as? URLError)?.code == .cancelled ? "已取消改写，原稿已保留" : error.localizedDescription }
        }
    }
    func applyRewrite(_ proposal:RewriteProposal) {
        guard !busy,var current = draft,let i = current.scenes.firstIndex(where:{ $0.id == proposal.original.id }),current.scenes[i] == proposal.original else { message = "原段落已变化，请重新改写，未覆盖当前内容"; return }
        checkpoint("局部改写前 · \(proposal.mode)"); current.scenes[i] = proposal.replacement; draft = current; checkpoint("局部改写 · \(proposal.mode)"); pendingRewrite = nil; message = "已应用这一段改写，其他段落保持原样"
    }
    func saveTemplate(name:String) throws {
        var name = name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.count <= 80 else { throw StudioError.message("模板名需为 1–80 个字") }
        let stem = name; var n = 2
        while templates.contains(where:{ $0.name == name }) { name = String(stem.prefix(72))+" (\(n))"; n += 1 }
        templates.append(try CreativeTemplate(name:name,brief:brief).validated()); saveTemplates(); message = "已保存模板：\(name)（不含主题与事实素材）"
    }
    func saveTemplates() { defaults.set(try? JSONEncoder().encode(templates),forKey:"creativeTemplates") }
    func applyTemplate(_ template:CreativeTemplate) {
        guard !busy else { return }; brief = template.applying(to:brief); message = "已应用模板：\(template.name)，当前主题与事实素材已保留"
    }
    func exportTemplates() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "个人创作模板.json"
        if panel.runModal() == .OK,let url = panel.url { do { try JSONEncoder().encode(templates).write(to:url,options:.atomic) } catch { message = error.localizedDescription } }
    }
    func importTemplates() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK,let url = panel.url {
            do {
                let incoming = try JSONDecoder().decode([CreativeTemplate].self,from:Data(contentsOf:url)); guard incoming.count <= 100 else { throw StudioError.message("单次最多导入 100 个模板") }
                let valid = try incoming.map { try $0.validated() }
                for var template in valid { template.id = UUID(); let stem = template.name; var n = 2; while templates.contains(where:{ $0.name == template.name }) { template.name = String(stem.prefix(72))+" (\(n))"; n += 1 }; templates.append(template) }
                saveTemplates(); message = "已导入 \(valid.count) 个模板，同名模板已加序号"
            } catch { message = error.localizedDescription }
        }
    }
    func applyAlignment(_ plan:MusicAlignment) {
        guard !busy,var current = draft else { return }
        let spoken = plan.rows.filter { $0.sceneID != nil }
        guard spoken.map(\.sceneID) == current.scenes.map({ Optional($0.id) }), zip(spoken,current.scenes).allSatisfy({ $0.spoken == $1.spoken }) else { message = "文案已变化，请重新生成音乐对齐方案"; return }
        checkpoint("应用音乐节奏前")
        for i in current.scenes.indices { current.scenes[i].seconds = max(1,Int((spoken[i].end-spoken[i].start).rounded())) }
        draft = current; checkpoint("音乐节奏安排"); message = "已更新段落预计口播时长（整数秒）；留白及精确帧时间保存在对齐导出中"
    }
}
