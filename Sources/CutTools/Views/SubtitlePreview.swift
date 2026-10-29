import AppKit

struct SubtitlePreview {
    var chinese: [Cue]
    var english: [Cue]
    var style: SubtitleStyle
    var width: Int
    var height: Int
    var chineseFirst: Bool
}

final class SubtitleOverlay: NSView {
    var preview: SubtitlePreview? { didSet { needsDisplay = true } }
    var time: Double = 0 { didSet { needsDisplay = true } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let p = preview, p.width > 0, p.height > 0 else { return }
        let scale = min(bounds.width / Double(p.width), bounds.height / Double(p.height))
        guard scale > 0 else { return }
        let canvas = NSRect(x: (bounds.width - Double(p.width) * scale) / 2,
                            y: (bounds.height - Double(p.height) * scale) / 2,
                            width: Double(p.width) * scale, height: Double(p.height) * scale)
        NSGraphicsContext.saveGraphicsState()
        canvas.clip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        for (chinese, cues) in [(true, p.chinese), (false, p.english)] {
            let active = SubtitleLayout.activeText(cues, at: time)
            guard !active.isEmpty else { continue }
            let size = chinese ? p.style.chineseSize : p.style.englishSize
            guard size.isFinite, (16...100).contains(size), p.style.x(chinese: chinese).isFinite,
                  p.style.bottom(chinese: chinese, chineseFirst: p.chineseFirst, bilingual: true).isFinite else { continue }
            let text = SubtitleLayout.wrapped(active, chinese: chinese, size: size, width: Double(p.width) - 80)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: SubtitleLayout.font(chinese: chinese, size: size * scale),
                .foregroundColor: SubtitleLayout.color(chinese ? p.style.chineseColor : p.style.englishColor),
                .strokeColor: NSColor.black, .strokeWidth: -4, .paragraphStyle: paragraph
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let width = max(1, (Double(p.width) - 80) * scale)
            let height = ceil(string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
            let bottom = p.style.bottom(chinese: chinese, chineseFirst: p.chineseFirst, bilingual: !p.chinese.isEmpty && !p.english.isEmpty)
            let rect = NSRect(x: canvas.minX + (40 + p.style.x(chinese: chinese)) * scale,
                              y: canvas.minY + bottom * scale, width: width, height: height)
            string.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }
}
