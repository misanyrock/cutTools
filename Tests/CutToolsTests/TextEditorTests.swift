import XCTest
import AppKit
import SwiftUI
@testable import CutTools

final class TextEditorTests: XCTestCase {
    @MainActor func testChineseFirstLineAndWrappedTextStayInsideInsets() throws {
        let scroll = InsetTextEditor.makeScrollView(monospaced:false)
        let editor = try XCTUnwrap(scroll.documentView as? NSTextView)
        editor.string = "王莽岭，挂壁公路，南太行旅游公路\n自驾南太行，我的观点很直接。\nEnglish ascenders: HAT, accents: ÉÀ."
        for width in [160.0,300.0,600.0] {
            scroll.setFrameSize(NSSize(width:width,height:120))
            scroll.tile()
            guard let manager = editor.layoutManager, let container = editor.textContainer else { return XCTFail("Missing text layout") }
            manager.ensureLayout(for:container)
            let firstGlyph = manager.boundingRect(forGlyphRange:NSRange(location:0,length:1),in:container).offsetBy(dx:editor.textContainerOrigin.x,dy:editor.textContainerOrigin.y)
            XCTAssertGreaterThanOrEqual(firstGlyph.minY,8)
            XCTAssertGreaterThanOrEqual(firstGlyph.minX,8)
            XCTAssertGreaterThan(firstGlyph.height,0)
            XCTAssertEqual(editor.textContainerInset.height,8)
            XCTAssertTrue(container.widthTracksTextView)
        }
    }
    @MainActor func testTypingUpdatesBindingAndSupportsPlainTextUndo() throws {
        let scroll = InsetTextEditor.makeScrollView(monospaced:true)
        let editor = try XCTUnwrap(scroll.documentView as? NSTextView)
        var text = ""
        let binding = Binding(get:{ text },set:{ text = $0 })
        let coordinator = InsetTextEditor.Coordinator(text:binding)
        editor.string = "新增中文与 English\n第二行"
        coordinator.textDidChange(Notification(name:NSText.didChangeNotification,object:editor))
        XCTAssertEqual(text,editor.string)
        XCTAssertTrue(editor.allowsUndo)
        XCTAssertFalse(editor.isRichText)
        XCTAssertFalse(editor.isHorizontallyResizable)
    }
}
