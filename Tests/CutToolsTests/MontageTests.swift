import XCTest
@testable import CutTools

final class MontageTests:XCTestCase {
    let music = URL(fileURLWithPath:"/tmp/music.wav")
    func asset(_ name:String,_ duration:Double) -> MontageAsset { MontageAsset(url:URL(fileURLWithPath:"/tmp/"+name),duration:duration,width:1920,height:1080,frameRate:25) }
    func testAssignmentSkipsShortAssetsAndPreservesLocks() throws {
        let a = asset("short.mp4",0.3),b = asset("long.mp4",4)
        let markers = [1.0,2,3].map { BeatMarker(time:$0,strength:1,kind:"手动标记") }
        var plan = try MontagePlanner.build(assets:[a,b],markers:markers,start:0,end:4,minimum:0.5,fps:25)
        XCTAssertEqual(plan.count,4); XCTAssertTrue(plan.allSatisfy { $0.assetID == b.id })
        plan[1].locked = true; plan[1].sourceIn = 0.5
        let rebuilt = try MontagePlanner.build(assets:[b,a],markers:markers,start:0,end:4,minimum:0.5,fps:25,previous:plan)
        XCTAssertEqual(rebuilt[1],plan[1])
        XCTAssertThrowsError(try MontagePlanner.build(assets:[a,b],markers:[],start:0,end:4,minimum:0.5,fps:25,previous:plan))
    }
    func testMissingFootageCannotExport() throws {
        let a = asset("short.mp4",0.2)
        let slots = try MontagePlanner.build(assets:[a],markers:[],start:0,end:4,minimum:0.5,fps:25)
        XCTAssertNil(slots[0].assetID)
        let project = MontageProject(assets:[a],slots:slots,music:music,musicDuration:4,sourceIn:0,duration:4,fps:25)
        XCTAssertThrowsError(try MontagePlanner.xml(project))
    }
    func testXMLIncludesMusicAndValidSourceFrames() throws {
        let a = asset("clip & view.mp4",5)
        let project = MontageProject(assets:[a],slots:[MontageSlot(start:0,duration:2,assetID:a.id,sourceIn:1)],music:music,musicDuration:10,sourceIn:3,duration:2,fps:25)
        let xml = try MontagePlanner.xml(project)
        XCTAssertTrue(XMLParser(data:Data(xml.utf8)).parse()); XCTAssertTrue(xml.contains("frameDuration=\"1/25s\"")); XCTAssertTrue(xml.contains("start=\"75/25s\"")); XCTAssertTrue(xml.contains("srcEnable=\"video\""))
        XCTAssertFalse(xml.contains("frameDuration=\"0/"))
    }
    @MainActor func testRenderIncludesMusicAndCorrectDuration() async throws {
        let workspace = Workspace(); guard let ffmpeg = workspace.ffmpeg else { throw XCTSkip("FFmpeg missing") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let clip = directory.appendingPathComponent("clip.mp4"), music = directory.appendingPathComponent("music.wav"), output = directory.appendingPathComponent("output.mp4")
        _ = try await workspace.checkedProcess(ffmpeg,["-nostdin","-y","-f","lavfi","-i","color=c=blue:s=320x240:r=25:d=2","-c:v","libx264",clip.path])
        _ = try await workspace.checkedProcess(ffmpeg,["-nostdin","-y","-f","lavfi","-i","sine=frequency=440:duration=5",music.path])
        let imported = try await MontageAsset.inspect(clip)
        let suite = "montage-test-"+UUID().uuidString, defaults = UserDefaults(suiteName:suite)!; defer { defaults.removePersistentDomain(forName:suite) }
        let store = MontageStore(defaults:defaults)
        store.project = MontageProject(assets:[imported],slots:[MontageSlot(start:0,duration:1,assetID:imported.id),MontageSlot(start:1,duration:1,assetID:imported.id)],music:music,musicDuration:5,sourceIn:1,duration:2,fps:25)
        store.render(to:output,ffmpeg:ffmpeg,preview:false); await store.task?.value
        XCTAssertTrue(FileManager.default.fileExists(atPath:output.path),store.message)
        let duration = try await workspace.mediaDuration(output); XCTAssertEqual(duration,2,accuracy:0.12)
        let log = try await workspace.checkedProcess(ffmpeg,["-hide_banner","-i",output.path,"-map","0:a:0","-f","null","-"])
        XCTAssertTrue(log.contains("Audio:"))
    }
}
