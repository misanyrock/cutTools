import SwiftUI
import AppKit

/// A plain-text AppKit editor with explicit text-container insets. SwiftUI's
/// TextEditor on the current runtime clips the first line in nested scroll views.
struct InsetTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced = false
    var accessibilityLabel = "多行文本"
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = Self.makeScrollView(monospaced: monospaced)
        let editor = scroll.documentView as! NSTextView
        editor.delegate = context.coordinator
        editor.string = text
        editor.isEditable = isEnabled
        editor.setAccessibilityLabel(accessibilityLabel)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.text = $text
        editor.isEditable = isEnabled
        editor.textColor = isEnabled ? .textColor : .secondaryLabelColor
        editor.setAccessibilityLabel(accessibilityLabel)
        // Never reset selection, scroll, or an active Chinese IME composition
        // when the SwiftUI binding reflects the editor's own change notification.
        if editor.string != text && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location,length),length: 0))
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.delegate = nil
    }

    @MainActor static func makeScrollView(monospaced: Bool) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x:0,y:0,width:300,height:120))
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top:0,left:0,bottom:0,right:0)
        scroll.backgroundColor = .textBackgroundColor
        scroll.drawsBackground = true

        let editor = NSTextView(frame: NSRect(origin:.zero,size:scroll.contentSize))
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.font = monospaced ? .monospacedSystemFont(ofSize: NSFont.systemFontSize,weight:.regular) : .systemFont(ofSize:NSFont.systemFontSize)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.drawsBackground = true
        editor.textContainerInset = NSSize(width:8,height:8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.minSize = .zero
        editor.maxSize = NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width:max(1,scroll.contentSize.width-16),height:CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.lineFragmentPadding = 2
        scroll.documentView = editor
        return scroll
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if text.wrappedValue != editor.string { text.wrappedValue = editor.string }
        }
    }
}
