import XCTest
import AVKit
@testable import CutTools

final class PlayerTests: XCTestCase {
    @MainActor func testNativePlayerCreationAndEmptyLifecycle() {
        // Exercise the native control itself; the old SwiftUI overlay crashed
        // even when entering the rough-cut page with no selected video.
        let view = AVPlayerView()
        let coordinator = StudioPlayer.Coordinator()
        view.player = coordinator.player
        coordinator.update(url: nil, seekTime: 0)
        XCTAssertNil(coordinator.player.currentItem)
        coordinator.update(url: URL(fileURLWithPath: "/missing-cuttools-video.mp4"), seekTime: .nan)
        XCTAssertNil(coordinator.player.currentItem)
        coordinator.stop()
        XCTAssertNil(coordinator.loadedURL)
        view.player = nil
    }

    @MainActor func testPlayerKeepsItemAcrossUnrelatedUpdates() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data().write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        let coordinator = StudioPlayer.Coordinator()
        coordinator.update(url: path, seekTime: 0)
        let item = coordinator.player.currentItem
        XCTAssertNotNil(item)
        coordinator.update(url: path, seekTime: 0)
        XCTAssertTrue(coordinator.player.currentItem === item)
        coordinator.update(url: nil, seekTime: 0)
        XCTAssertNil(coordinator.player.currentItem)
    }

    @MainActor func testSubtitleOverlayUpdatesAndReleasesObserver() {
        let coordinator = StudioPlayer.Coordinator()
        let preview = SubtitlePreview(chinese: [Cue(start: 1, end: 2, text: "中文", sourceNumber: 1)], english: [], style: SubtitleStyle(), width: 1920, height: 1080, chineseFirst: true)
        coordinator.observeTime()
        coordinator.update(url: nil, seekTime: 0, subtitles: preview)
        XCTAssertEqual(coordinator.overlay.preview?.chinese.first?.text, "中文")
        coordinator.overlay.frame = NSRect(x: 0, y: 0, width: 640, height: 360)
        coordinator.overlay.time = 1
        let bitmap = coordinator.overlay.bitmapImageRepForCachingDisplay(in: coordinator.overlay.bounds)!
        coordinator.overlay.cacheDisplay(in: coordinator.overlay.bounds, to: bitmap)
        let hasInk = (0..<bitmap.pixelsHigh).contains { y in
            (0..<bitmap.pixelsWide).contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 }
        }
        XCTAssertTrue(hasInk, "当前时间的字幕应绘制到视频叠加层")
        coordinator.stop()
        XCTAssertNil(coordinator.overlay.preview)
        coordinator.observeTime()
        coordinator.stop()
    }
}
