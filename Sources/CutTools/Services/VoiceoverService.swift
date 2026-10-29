import Foundation
import AVFoundation

enum NarrationVoice: String, CaseIterable, Codable {
    case ethan = "Ethan", kai = "Kai", cherry = "Cherry", serena = "Serena", mochi = "Mochi", pip = "Pip"
    var title: String {
        switch self {
        case .ethan: return "自然男声 · 晨煦"
        case .kai: return "舒缓男声 · 凯"
        case .cherry: return "亲切女声 · 芊悦"
        case .serena: return "温柔女声 · 苏瑶"
        case .mochi: return "童声 · 沙小弥"
        case .pip: return "活泼童声 · 顽屁小孩"
        }
    }
}

struct VoiceoverConfiguration: Codable {
    var baseURL = "https://dashscope.aliyuncs.com/api/v1"
    var model = "qwen3-tts-flash"
    var credentials: ModelConfiguration { ModelConfiguration(provider: .qwen, baseURL: baseURL, model: model) }
    func endpoint() throws -> URL { try credentials.endpoint("services/aigc/multimodal-generation/generation") }
}

enum VoiceoverService {
    static func chunks(_ text: String) throws -> [String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 20000 else {
            throw StudioError.message("请先写好口播文字；单次配音最多支持 20000 字符")
        }
        var result: [String] = [], current = "", length = 0
        for character in text {
            let count = String(character).utf16.count
            guard count <= 500 else { throw StudioError.message("口播文字包含过长的组合字符，请检查内容") }
            if length + count > 500 { result.append(current); current = ""; length = 0 }
            current.append(character); length += count
            if length >= 250 && "。！？!?；;\n".contains(character) {
                result.append(current); current = ""; length = 0
            }
        }
        if !current.isEmpty { result.append(current) }
        return result.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func request(text: String, voice: NarrationVoice, config: VoiceoverConfiguration, key: String) throws -> URLRequest {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 600,
              !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StudioError.message("语音模型或文本无效") }
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key.rangeOfCharacter(from: .newlines) == nil else { throw StudioError.message("请在设置的 AI 配音中保存有效的百炼 API Key") }
        var request = URLRequest(url: try config.endpoint())
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": config.model, "input": ["text": text, "voice": voice.rawValue, "language_type": "Auto"]])
        return request
    }

    static func audioURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value), let host = parts.host?.lowercased(),
              host.hasSuffix(".aliyuncs.com"), ["https", "http"].contains(parts.scheme ?? ""),
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil else {
            throw StudioError.message("语音服务返回了无效的音频下载地址")
        }
        // DashScope can return HTTP OSS URLs; keep downloads encrypted and never forward the API key.
        parts.scheme = "https"
        guard let url = parts.url else { throw StudioError.message("无法读取音频地址") }
        return url
    }

    static func synthesize(text: String, voice: NarrationVoice, config: VoiceoverConfiguration, key: String,
                           session: URLSession = ModelClient.session) async throws -> Data {
        let (data, response) = try await session.data(for: request(text: text, voice: voice, config: config, key: key))
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw StudioError.message("配音请求失败（HTTP \(status)），请检查语音服务地址、Key、模型权限和额度") }
        struct Response: Decodable {
            struct Output: Decodable { struct Audio: Decodable { var url: String }; var audio: Audio; var finish_reason: String? }
            var output: Output?; var code: String?
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.code == nil || result.code == "", let output = result.output, output.finish_reason == "stop" else {
            throw StudioError.message("语音服务未完成合成，请检查模型权限与额度后重试")
        }
        let url = try audioURL(output.audio.url)
        var download = URLRequest(url: url); download.timeoutInterval = 180
        let (audio, audioResponse) = try await session.data(for: download)
        try Task.checkCancellation()
        guard (audioResponse as? HTTPURLResponse)?.statusCode == 200, audio.count >= 44,
              audio.count <= 50_000_000, String(decoding: audio.prefix(4), as: UTF8.self) == "RIFF",
              String(decoding: audio.dropFirst(8).prefix(4), as: UTF8.self) == "WAVE" else {
            throw StudioError.message("下载的音频不是有效 WAV 文件，请重试")
        }
        return audio
    }

    static func concatenate(_ files: [URL], to destination: URL) throws {
        guard let first = files.first else { throw StudioError.message("没有可用的配音片段") }
        let format = try AVAudioFile(forReading: first).fileFormat
        let output = try AVAudioFile(forWriting: destination, settings: format.settings)
        for url in files {
            try Task.checkCancellation()
            let input = try AVAudioFile(forReading: url)
            guard input.length > 0, input.processingFormat == output.processingFormat,
                  let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32768) else {
                throw StudioError.message("语音片段的音频格式不一致或内容为空，请重新生成")
            }
            while input.framePosition < input.length {
                try Task.checkCancellation()
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { throw StudioError.message("无法读取完整语音片段") }
                try output.write(from: buffer)
            }
        }
    }
}
