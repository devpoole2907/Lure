#if canImport(UIKit)
import SwiftUI
import UIKit
import AVKit
import AVFoundation
import Combine
import AetherEngine

/// Hosts AetherEngine playback inside a native `AVPlayerViewController` so the
/// transport bar, scrubbing, Now Playing, AirPlay, Picture in Picture and (on
/// capable hardware) Dolby Atmos all come from AVKit — the most native-feeling
/// playback we can offer.
///
/// - **Native backend** (formats AVFoundation can decode): the engine publishes a
///   real `AVPlayer` via `engine.$currentAVPlayer`; we hand it to AVKit and AVKit
///   renders + drives everything.
/// - **Software backend** (MKV / dav1d / VP9 etc.): there is no `AVPlayer`, so we
///   mount the engine's own render surface into `contentOverlayView`, hide AVKit's
///   (inert) controls, and let the SwiftUI `TransportOverlay` drive playback.
///
/// The few things AVKit can't drive from this engine on iOS — audio- and
/// subtitle-track selection — are surfaced by `PlayerView` as native SwiftUI
/// `Menu`s overlaid on the player.
@MainActor
final class PlayerHostController: AVPlayerViewController, AVPlayerViewControllerDelegate {
    private let vm: PlayerViewModel
    private let onClose: () -> Void
    private let aetherView = AetherPlayerView()
    private var aetherViewMounted = false
    private var subscriptions: Set<AnyCancellable> = []

    init(vm: PlayerViewModel, onClose: @escaping () -> Void) {
        self.vm = vm
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        videoGravity = .resizeAspect
        allowsPictureInPicturePlayback = true
        delegate = self

        // The engine republishes its native AVPlayer on every internal reload
        // (an audio-track switch rebuilds the native host), so re-bind each time.
        // nil on the software path — assigning nil drops AVKit's stale player so it
        // stops drawing its own loading spinner over the engine's frames.
        vm.engine.$currentAVPlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] avPlayer in
                self?.player = avPlayer
            }
            .store(in: &subscriptions)

        vm.engine.$playbackBackend
            .receive(on: RunLoop.main)
            .sink { [weak self] backend in
                self?.applyBackend(backend)
            }
            .store(in: &subscriptions)
    }

    // MARK: - Backend presentation

    private func applyBackend(_ backend: PlaybackBackend) {
        let isSoftware = (backend == .software)
        // AVKit's controls can only drive a real AVPlayer; suppress them on the
        // software path where the SwiftUI TransportOverlay takes over.
        showsPlaybackControls = !isSoftware
        if isSoftware {
            mountAetherView()
        } else {
            unmountAetherView()
        }
    }

    /// Mount the engine surface in AVKit's `contentOverlayView` (which sits above
    /// the empty player layer and below the chrome) for the software path.
    private func mountAetherView() {
        guard !aetherViewMounted else { return }
        let host = contentOverlayView ?? view!
        aetherView.frame = host.bounds
        aetherView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.insertSubview(aetherView, at: 0)
        vm.engine.bind(view: aetherView)
        aetherViewMounted = true
    }

    private func unmountAetherView() {
        guard aetherViewMounted else { return }
        vm.engine.unbind(view: aetherView)
        aetherView.removeFromSuperview()
        aetherViewMounted = false
    }

    // MARK: - AVPlayerViewControllerDelegate

    /// AVKit's own close control collapses the full-screen player; route it to the
    /// host so the engine stops and the cover dismisses (no duplicate close button).
    ///
    /// AVKit also emits this during initial setup — before playback starts — as it
    /// settles its presentation. Honoring that spurious fire tore the player down
    /// before it ever played, so we ignore any close until real playback is under
    /// way (currentTime past the first second).
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        guard vm.currentTime > 1.0 else { return }
        let close = onClose
        coordinator.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled else { return }
            close()
        }
    }
}

extension TrackInfo {
    /// Human-readable track label, e.g. "English · 5.1 · AC3".
    var displayLabel: String {
        var parts: [String] = []
        if !name.isEmpty {
            parts.append(name)
        } else if let lang = language, !lang.isEmpty {
            parts.append(lang.uppercased())
        } else {
            parts.append("Track \(id)")
        }
        if isAtmos {
            parts.append("Atmos")
        } else if channels == 6 {
            parts.append("5.1")
        } else if channels == 8 {
            parts.append("7.1")
        }
        if !codec.isEmpty {
            parts.append(codec.uppercased())
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - SwiftUI bridge

/// Embeds `PlayerHostController` in SwiftUI. Playback is loaded/stopped by the
/// surrounding `PlayerView`; this view only owns the native presentation surface.
struct AVPlayerHostView: UIViewControllerRepresentable {
    let vm: PlayerViewModel
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> PlayerHostController {
        PlayerHostController(vm: vm, onClose: onClose)
    }

    func updateUIViewController(_ controller: PlayerHostController, context: Context) {}
}
#endif
