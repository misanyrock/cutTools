import SwiftUI
import AppKit
import AVKit

/// Avoids the SwiftUI VideoPlayer overlay: its generic class metadata aborts on
/// the current macOS runtime. The coordinator owns playback for one view lifetime.
struct StudioPlayer: NSViewRepresentable {
    let url: URL?
    var seekTime: Double = 0
    var subtitles: SubtitlePreview?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        if let overlay = view.contentOverlayView {
            let subtitles = context.coordinator.overlay
            subtitles.frame = overlay.bounds
            subtitles.autoresizingMask = [.width, .height]
            overlay.addSubview(subtitles)
        }
        context.coordinator.observeTime()
        context.coordinator.update(url: url, seekTime: seekTime, subtitles: subtitles)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.update(url: url, seekTime: seekTime, subtitles: subtitles)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        view.player = nil
    }

    @MainActor final class Coordinator {
        let player = AVPlayer()
        private(set) var loadedURL: URL?
        private var lastSeek: Double?
        let overlay = SubtitleOverlay()
        private var timeObserver: Any?

        func observeTime() {
            guard timeObserver == nil else { return }
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { self?.overlay.time = time.seconds.isFinite ? time.seconds : 0 }
            }
        }

        func update(url: URL?, seekTime: Double, subtitles: SubtitlePreview? = nil) {
            overlay.preview = subtitles
            let changed = loadedURL != url
            if changed {
                player.pause()
                overlay.time = 0
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
            overlay.time = seekTime
            // Loading a new video starts at zero; unrelated SwiftUI updates do
            // not seek or pause a video the user is already playing.
            if seekTime > 0 || !changed {
                player.pause()
                player.seek(to: CMTime(seconds: seekTime, preferredTimescale: 600))
            }
        }

        func stop() {
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeObserver = nil
            overlay.preview = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            loadedURL = nil
            lastSeek = nil
        }
    }
}
