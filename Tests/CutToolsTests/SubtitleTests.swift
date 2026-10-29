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
    func testBilingualTitlesKeepIndependentTimingStyleAndPositions() throws {
        var style = SubtitleStyle()
        style.chineseX = -120; style.englishX = 80
        style.chineseBottom = 180; style.englishBottom = 70
        style.chineseColor = "123456"; style.englishColor = "ABCDEF"
        let xml = try StyledSubtitles.fcpxml(
            zh: [Cue(start: 1.01, end: 2.03, text: "中文 & <测试>", sourceNumber: 1)],
            en: [Cue(start: 1.50, end: 3.01, text: "English\nsecond line", sourceNumber: 1)],
            style: style, width: 1080, height: 1920)
        let document = try XMLDocument(xmlString: xml)
        let titles = try document.nodes(forXPath: "//title").map { $0 as! XMLElement }
        XCTAssertEqual(titles.map { $0.attribute(forName: "lane")!.stringValue! }, ["1", "2"])
        XCTAssertEqual(titles.map { $0.attribute(forName: "offset")!.stringValue! }, ["25/25s", "38/25s"])
        XCTAssertEqual(titles.map { $0.attribute(forName: "duration")!.stringValue! }, ["26/25s", "37/25s"])
        XCTAssertEqual(try document.nodes(forXPath: "//text-style-def/text-style/@fontSize").map(\.stringValue), ["48.0", "34.0"])
        XCTAssertEqual(try document.nodes(forXPath: "//title[1]/text/text-style").first?.stringValue, "中文 & <测试>")
        XCTAssertEqual(try document.nodes(forXPath: "//title[2]/text/text-style").first?.stringValue, "English\nsecond line")
        let positions = try document.nodes(forXPath: "//adjust-transform/@position").map { $0.stringValue! }
        XCTAssertNotEqual(positions[0], positions[1])
        let colors = try document.nodes(forXPath: "//text-style-def/text-style/@fontColor").map(\.stringValue)
        XCTAssertNotEqual(colors[0], colors[1])
    }

    func testEverySubtitleFrameRateAndColorSpace() throws {
        for rate in SubtitleFrameRate.allCases {
            for space in SubtitleColorSpace.allCases {
                let settings = SubtitleExportSettings(frameRate: rate, colorSpace: space)
                let xml = try StyledSubtitles.fcpxml(zh: [], en: [Cue(start: 7.18, end: 9.36, text: "Test", sourceNumber: 1)], style: SubtitleStyle(), width: 3840, height: 2160, settings: settings)
                let document = try XMLDocument(xmlString: xml)
                XCTAssertEqual(try document.nodes(forXPath: "//format/@frameDuration").first?.stringValue, rate.frameDuration)
                XCTAssertEqual(try document.nodes(forXPath: "//format/@colorSpace").first?.stringValue, space.xmlValue)
                XCTAssertEqual(try document.nodes(forXPath: "//library/@colorProcessing").first?.stringValue, space.processing)
                let offset = try XCTUnwrap(document.nodes(forXPath: "//title/@offset").first?.stringValue)
                let numerator = try XCTUnwrap(Int(offset.components(separatedBy: "/")[0]))
                XCTAssertEqual(numerator % rate.numerator, 0)
                XCTAssertEqual(Double(numerator) / Double(rate.denominator), 7.18, accuracy: rate.secondsPerFrame / 2 + 1e-10)
                XCTAssertEqual(try document.nodes(forXPath: "//title/@lane").first?.stringValue, "2")
            }
        }
        XCTAssertEqual(SubtitleFrameRate.fps2997.time(30000), "30030000/30000s")
    }

    func testSubtitleExportRejectsInvalidInputs() throws {
        let cue = Cue(start: 0, end: 1, text: "Test", sourceNumber: 1)
        XCTAssertThrowsError(try StyledSubtitles.fcpxml(zh: [], en: [], style: SubtitleStyle(), width: 1920, height: 1080))
        XCTAssertThrowsError(try StyledSubtitles.fcpxml(zh: [cue], en: [], style: SubtitleStyle(), width: 0, height: 1080))
        XCTAssertThrowsError(try StyledSubtitles.fcpxml(zh: [Cue(start: .nan, end: 2, text: "", sourceNumber: 1)], en: [], style: SubtitleStyle(), width: 1920, height: 1080))
        var style = SubtitleStyle(); style.chineseColor = "XYZ"
        XCTAssertThrowsError(try StyledSubtitles.fcpxml(zh: [cue], en: [], style: style, width: 1920, height: 1080))
    }

    func testSubtitleXMLMatchesInstalledFinalCutSchema() throws {
        let path = "/Applications/Final Cut Pro.app/Contents/Frameworks/Interchange.framework/Versions/A/Resources/FCPXMLv1_10.dtd"
        guard FileManager.default.fileExists(atPath: path) else { throw XCTSkip("未安装 Final Cut Pro 的 XML 定义") }
        let cue = Cue(start: 7.18, end: 9.36, text: "双语\nTwo lines & more", sourceNumber: 1)
        for space in SubtitleColorSpace.allCases {
            let xml = try StyledSubtitles.fcpxml(zh: [cue], en: [cue], style: SubtitleStyle(), width: 1080, height: 1920, settings: SubtitleExportSettings(frameRate: .fps2997, colorSpace: space))
            let process = Process(), input = Pipe(), errors = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
            process.arguments = ["--noout", "--dtdvalid", URL(fileURLWithPath: path).absoluteString, "-"]
            process.standardInput = input; process.standardError = errors
            try process.run()
            input.fileHandleForWriting.write(Data(xml.utf8))
            try input.fileHandleForWriting.close()
            let log = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, String(decoding: log, as: UTF8.self))
        }
    }

    func testSubtitleStyleLoadsOldSavedStylesAndPreviewBoundaries() throws {
        let json = #"{"chineseSize":48,"englishSize":34,"chineseColor":"FFFFFF","englishColor":"FFFF99","bottom":50,"gap":8}"#
        let style = try JSONDecoder().decode(SubtitleStyle.self, from: Data(json.utf8))
        XCTAssertEqual(style.bottom(chinese: true, chineseFirst: true, bilingual: true), 92)
        XCTAssertEqual(style.bottom(chinese: false, chineseFirst: true, bilingual: true), 50)
        let cues = [Cue(start: 1, end: 2, text: "first", sourceNumber: 1), Cue(start: 2, end: 3, text: "second", sourceNumber: 2)]
        XCTAssertEqual(SubtitleLayout.activeText(cues, at: 0.9), "")
        XCTAssertEqual(SubtitleLayout.activeText(cues, at: 1), "first")
        XCTAssertEqual(SubtitleLayout.activeText(cues, at: 2), "second")
        XCTAssertEqual(SubtitleLayout.activeText(cues, at: 3), "")
        let wrapped = SubtitleLayout.wrapped("Then go find yourself. 中文也要换行", chinese: false, size: 34, width: 180)
        XCTAssertTrue(wrapped.contains("\n"))
        XCTAssertEqual(wrapped.replacingOccurrences(of: "\n", with: ""), "Then go find yourself. 中文也要换行")
        XCTAssertGreaterThan(SubtitleLayout.firstBaseline("one\ntwo", chinese: false, size: 34), SubtitleLayout.firstBaseline("one", chinese: false, size: 34))
    }

    func testSubtitleXMLAlignsEndpointsToFrames() throws {
        let cues = [
            Cue(start: 7.18, end: 9.36, text: "中文\nEnglish", sourceNumber: 1),
            Cue(start: 9.36, end: 11.70, text: "下一句", sourceNumber: 2),
            Cue(start: 11.70, end: 11.701, text: "短句", sourceNumber: 3)
        ]
        let xml = try StyledSubtitles.fcpxml(zh: cues, en: [], style: SubtitleStyle(), width: 1920, height: 1080)
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
    func testStyledSubtitleEscapesAndColors() throws {
        var style = SubtitleStyle(); style.chineseColor = "123456"
        let text = StyledSubtitles.ass(zh: [Cue(start: 0,end: 2,text: "{x}\n好",sourceNumber: 1)],en: [],style: style,width: 1920,height: 1080,chineseFirst: true)
        XCTAssertTrue(text.contains("&H00563412")); XCTAssertTrue(text.contains("\\{x\\}\\N好"))
        let xml = try StyledSubtitles.fcpxml(zh: [Cue(start: 0,end: 2,text: "A & B < C",sourceNumber: 1)], en: [], style: style,width: 1920,height: 1080)
        XCTAssertTrue(xml.contains("A &amp; B &lt; C"))
    }
}
