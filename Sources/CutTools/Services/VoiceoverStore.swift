import AppKit
import UniformTypeIdentifiers

struct VoiceoverResult {
    let url: URL
    let text: String
    let voice: NarrationVoice
}

@MainActor final class VoiceoverStore: ObservableObject {
    @Published var voice: NarrationVoice = .ethan
    @Published private(set) var busy = false
    @Published private(set) var result: VoiceoverResult?
    @Published var message = "选好音色后，一键生成全部口播的 AI 配音"
    private(set) var task: Task<Void, Never>?

    func generate(text: String, config: VoiceoverConfiguration, key: String, session: URLSession = ModelClient.session) {
        guard !busy else { return }
        do {
            let chunks = try VoiceoverService.chunks(text)
            let selectedVoice = voice
            _ = try VoiceoverService.request(text: chunks[0], voice: selectedVoice, config: config, key: key)
            busy = true
            task = Task { @MainActor in
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CutTools-voice-" + UUID().uuidString)
                var completed = false
                defer { busy = false; if !completed { try? FileManager.default.removeItem(at: directory) } }
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    var files: [URL] = []
                    for (index, chunk) in chunks.enumerated() {
                        try Task.checkCancellation()
                        message = "AI 正在配音 \(index + 1)/\(chunks.count)…"
                        let audio = try await VoiceoverService.synthesize(text: chunk, voice: selectedVoice, config: config, key: key, session: session)
                        let file = directory.appendingPathComponent("\(index).wav")
                        try audio.write(to: file, options: .atomic); files.append(file)
                    }
                    let destination = directory.appendingPathComponent("口播配音.wav")
                    let audioFiles = files
                    let merge = Task.detached { try VoiceoverService.concatenate(audioFiles, to: destination) }
                    try await withTaskCancellationHandler(operation: { try await merge.value }, onCancel: { merge.cancel() })
                    try Task.checkCancellation()
                    let previous = result
                    result = VoiceoverResult(url: destination, text: text, voice: selectedVoice)
                    completed = true
                    for file in files { try? FileManager.default.removeItem(at: file) }
                    if let previous { try? FileManager.default.removeItem(at: previous.url.deletingLastPathComponent()) }
                    message = "AI 配音已生成 · \(selectedVoice.title)，可试听或保存 WAV"
                } catch {
                    message = error is CancellationError || (error as? URLError)?.code == .cancelled ? "已取消配音，之前生成的音频已保留" : error.localizedDescription
                }
            }
        } catch { message = error.localizedDescription }
    }

    func cancel() { task?.cancel() }
    func save(to destination: URL) throws {
        guard let result else { throw StudioError.message("请先生成配音") }
        let staging = destination.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: result.url, to: staging)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
    }
    func save() {
        guard result != nil else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.wav]; panel.nameFieldStringValue = "口播配音.wav"
        if panel.runModal() == .OK, let url = panel.url {
            do { try save(to: url); message = "配音已保存：\(url.lastPathComponent)" }
            catch { message = error.localizedDescription }
        }
    }
}
