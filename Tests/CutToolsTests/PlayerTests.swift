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
}
