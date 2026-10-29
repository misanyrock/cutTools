import XCTest
@testable import CutTools
final class SubtitleTests: XCTestCase {
    func testParseAndRoundTrip() throws {
        let input = "1\n00:00:01,000 --> 00:00:02,500\n你好\n\n2\n00:00:03,000 --> 00:00:04,000\n世界\n"
        let parsed = try SRT.parse(input)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(try SRT.parse(SRT.render(parsed)).map(\.text), ["你好", "世界"])
    }
    func testOneToManyIsFlagged() throws {
        let zh = try SRT.parse("1\n00:00:01,000 --> 00:00:04,000\n你好\n")
        let en = try SRT.parse("1\n00:00:01,000 --> 00:00:02,000\nHello\n\n2\n00:00:02,000 --> 00:00:04,000\nworld\n")
        let matches = SRT.match(zh, en, chineseFirst: true)
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].1)
        XCTAssertEqual(matches[0].0.text, "你好\nHello\nworld")
    }
    func testIssuesAndTime() throws {
        XCTAssertEqual(SRT.stamp(-1), "00:00:00,000")
        let cues = try SRT.parse("4\n00:00:01,000 --> 00:00:01,500\n\n")
        XCTAssertGreaterThanOrEqual(SRT.issues(cues).count, 3)
    }
}

final class StudioTests: XCTestCase {
    func testSubtitleXMLAlignsEndpointsToFrames() throws {
        let cues = [
            Cue(start: 7.18, end: 9.36, text: "中文\nEnglish", sourceNumber: 1),
            Cue(start: 9.36, end: 11.70, text: "下一句", sourceNumber: 2),
            Cue(start: 11.70, end: 11.701, text: "短句", sourceNumber: 3)
        ]
        let xml = StyledSubtitles.fcpxml(cues, style: SubtitleStyle(), width: 1920, height: 1080)
        let document = try XMLDocument(xmlString: xml)
        let titles = try document.nodes(forXPath: "//title").map { $0 as! XMLElement }
        XCTAssertEqual(titles.map { $0.attribute(forName: "offset")?.stringValue }, ["180/25s", "234/25s", "293/25s"])
        XCTAssertEqual(titles.map { $0.attribute(forName: "duration")?.stringValue }, ["54/25s", "59/25s", "1/25s"])
        XCTAssertEqual(try document.nodes(forXPath: "//sequence/@duration").first?.stringValue, "294/25s")
        XCTAssertEqual(try document.nodes(forXPath: "//gap/@duration").first?.stringValue, "294/25s")
        XCTAssertEqual(try document.nodes(forXPath: "//title[1]/text/text-style").first?.stringValue, "中文\nEnglish")
    }

    func testDeletionMergesAndClamps() {
        let cuts = [TimeRange(start: -1,end: 3,reason: "a",selected: true), TimeRange(start: 2,end: 5,reason: "b",selected: true), TimeRange(start: 8,end: 15,reason: "c",selected: true)]
        let kept = Timeline.kept(cuts, duration: 10)
        XCTAssertEqual(kept.count,1); XCTAssertEqual(kept[0].0,5); XCTAssertEqual(kept[0].1,8)
    }
    func testSubtitleRemappingSplitsAtCuts() {
        let cue = Cue(start: 1,end: 9,text: "Hello",sourceNumber: 1)
        let result = Timeline.remap([cue],kept: [(0,3),(7,10)])
        XCTAssertEqual(result.map(\.start),[1,3]); XCTAssertEqual(result.map(\.end),[3,5]); XCTAssertNotEqual(result[0].id,result[1].id)
    }
    func testDetectionParsesTrailingSilence() {
        let result = Timeline.events("silence_start: 1.5\nsilence_end: 3\nsilence_start: 8", name: "silence", duration: 10)
        XCTAssertEqual(result.count,2); XCTAssertEqual(result[1].1,10)
    }
    func testStyledSubtitleEscapesAndColors() {
        var style = SubtitleStyle(); style.chineseColor = "123456"
        let text = StyledSubtitles.ass(zh: [Cue(start: 0,end: 2,text: "{x}\n好",sourceNumber: 1)],en: [],style: style,width: 1920,height: 1080,chineseFirst: true)
        XCTAssertTrue(text.contains("&H00563412")); XCTAssertTrue(text.contains("\\{x\\}\\N好"))
        let xml = StyledSubtitles.fcpxml([Cue(start: 0,end: 2,text: "A & B < C",sourceNumber: 1)],style: style,width: 1920,height: 1080)
        XCTAssertTrue(xml.contains("A &amp; B &lt; C"))
    }
}
