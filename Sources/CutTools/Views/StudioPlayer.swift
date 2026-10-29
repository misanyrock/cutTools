import SwiftUI
import AppKit
import AVKit

/// Avoids the SwiftUI VideoPlayer overlay: its generic class metadata aborts on
/// the current macOS runtime. The coordinator owns playback for one view lifetime.
struct StudioPlayer: NSViewRepresentable {
    let url: URL?
    var seekTime: Double = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.update(url: url, seekTime: seekTime)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.update(url: url, seekTime: seekTime)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.player = nil
    }

    @MainActor final class Coordinator {
        let player = AVPlayer()
        private(set) var loadedURL: URL?
        private var lastSeek: Double?

        func update(url: URL?, seekTime: Double) {
            let changed = loadedURL != url
            if changed {
                player.pause()
                loadedURL = url
                lastSeek = nil
                if let url, url.isFileURL,
                   FileManager.default.isReadableFile(atPath: url.path),
                   !url.hasDirectoryPath {
                    player.replaceCurrentItem(with: AVPlayerItem(url: url))
                } else {
                    player.replaceCurrentItem(with: nil)
                }
            }
            guard player.currentItem != nil, seekTime.isFinite, seekTime >= 0,
                  lastSeek != seekTime else { return }
            lastSeek = seekTime
            // Loading a new video starts at zero; unrelated SwiftUI updates do
            // not seek or pause a video the user is already playing.
            if seekTime > 0 || !changed {
                player.pause()
                player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))
            }
        }

        func stop() {
            player.pause()
            player.replaceCurrentItem(with: nil)
            loadedURL = nil
            lastSeek = nil
        }
    }
}
