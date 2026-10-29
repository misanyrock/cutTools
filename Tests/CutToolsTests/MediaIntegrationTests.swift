import XCTest
@testable import CutTools

final class MediaIntegrationTests: XCTestCase {
    @MainActor func testQualityScanAndRoughCutExport() async throws {
        let w = Workspace()
        guard let ffmpeg = w.ffmpeg else { throw XCTSkip("本机未安装 FFmpeg") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("sample.mp4")
        _ = try await w.checkedProcess(ffmpeg,["-nostdin","-y","-f","lavfi","-i","color=c=black:s=320x240:r=25:d=3","-f","lavfi","-i","anullsrc=r=48000:cl=stereo","-t","3","-c:v","libx264","-c:a","aac",source.path])
        w.selectedVideo = source; w.output = directory
        w.analyzeVideo(quality: true)
        await w.studioTask?.value
        XCTAssertTrue(w.findings.contains { $0.message.contains("黑场") },w.message)
        XCTAssertTrue(w.findings.contains { $0.message.contains("静音") },w.message)
        w.cutsVideo = source
        w.cuts = [TimeRange(start: 1,end: 2,reason: "test",selected: true)]
        w.chinese = [Cue(start: 0.5,end: 2.5,text: "跨越删除点",sourceNumber: 1)]
        w.exportRoughCut(); await w.studioTask?.value
        let output = directory.appendingPathComponent("sample-粗剪.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path),w.message)
        let duration = try await w.mediaDuration(output)
        XCTAssertEqual(duration,2,accuracy: 0.15)
        let subtitles = try SRT.read(directory.appendingPathComponent("sample-粗剪-中文.srt"))
        XCTAssertEqual(subtitles.count,2)
        XCTAssertEqual(subtitles.last!.end,1.5,accuracy: 0.01)
    }
}
