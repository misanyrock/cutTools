import AppKit

enum SubtitleLayout {
    static func color(_ hex: String) -> NSColor {
        let value = UInt32(hex, radix: 16) ?? 0xFFFFFF
        return NSColor(srgbRed: Double(value >> 16 & 255) / 255, green: Double(value >> 8 & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
    }
    static func font(chinese: Bool, size: Double) -> NSFont {
        NSFont(name: chinese ? "PingFang SC" : "Arial", size: size) ?? .systemFont(ofSize: size)
    }
    static func activeText(_ cues: [Cue], at time: Double) -> String {
        cues.filter { $0.start <= time && time < $0.end }.map(\.text).joined(separator: "\n")
    }
    static func firstBaseline(_ text: String, chinese: Bool, size: Double) -> Double {
        let font = font(chinese: chinese, size: size)
        let extraLines = max(0, text.components(separatedBy: "\n").count - 1)
        return -font.descender + Double(extraLines) * NSLayoutManager().defaultLineHeight(for: font)
    }
    static func wrapped(_ text: String, chinese: Bool, size: Double, width: Double) -> String {
        let storage = NSTextStorage(string: text, attributes: [.font: font(chinese: chinese, size: size)])
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var lines: [String] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphs, _ in
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: range).trimmingCharacters(in: .newlines))
        }
        return lines.joined(separator: "\n")
    }
}
