import XCTest
import Foundation
@testable import CutTools

final class BeatTests: XCTestCase {
    func testSilenceHasNoBeatsOrTempo() throws {
        let result = try BeatDetector.analyze([Float](repeating: 0,count: 22050*3))
        XCTAssertTrue(result.markers.isEmpty); XCTAssertNil(result.bpm)
    }
    func testSyntheticKickTrainFinds120BPM() throws {
        let rate = 22050.0
        var samples = [Float](repeating: 0,count: Int(rate*6))
        let times = stride(from: 0.5,through: 5.5,by: 0.5).map { $0 }
        for t in times {
            let offset = Int(t*rate)
            for j in 0..<2205 { let x = Double(j)/rate; samples[offset+j] += Float(sin(2 * .pi * 80*x)*exp(-50*x)) }
        }
        let result = try BeatDetector.analyze(samples)
        let beats = result.markers.filter { $0.kind != "能量转折候选" }
        XCTAssertGreaterThanOrEqual(beats.count,9)
        for t in times { XCTAssertTrue(beats.contains { abs($0.time-t) < 0.06 },"missing \(t); found \(beats.map(\.time))") }
        XCTAssertEqual(result.bpm ?? 0,120,accuracy: 3)
    }
    func testExportQuantizesAndExcludesDisabledMarkers() {
        let markers = [BeatMarker(time: 0.51,strength: 1,kind: "A & B"),BeatMarker(time: 0.515,strength: 1,kind: "duplicate"),BeatMarker(time: 1,strength: 1,kind: "disabled",enabled: false)]
        let text = BeatExport.xml(source: URL(fileURLWithPath: "/tmp/music & mix.wav"),duration: 2,markers: markers,fps: 25)
        XCTAssertTrue(XMLParser(data: Data(text.utf8)).parse())
        XCTAssertTrue(text.contains("start=\"13/25s\"")); XCTAssertTrue(text.contains("A &amp; B"))
        XCTAssertEqual(text.components(separatedBy: "<marker ").count-1,1)
        XCTAssertFalse(BeatExport.csv(markers).contains("disabled"))
    }
    func testSessionPreservesManualEdits() throws {
        let session = BeatSession(source: URL(fileURLWithPath: "/tmp/music.wav"),duration: 2,markers: [BeatMarker(time: 0.75,strength: 1,kind: "手动标记",enabled: false)],fps: 30)
        let decoded = try JSONDecoder().decode(BeatSession.self,from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.markers,session.markers); XCTAssertEqual(decoded.fps,30)
    }
}
