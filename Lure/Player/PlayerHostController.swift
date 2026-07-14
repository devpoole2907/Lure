#if os(iOS)
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
final class PlayerHostController: AVPlayerViewController, AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
    private let vm: PlayerViewModel
    private let onClose: () -> Void
    private let aetherView = AetherPlayerView()
    private var aetherViewMounted = false
    private var subscriptions: Set<AnyCancellable> = []
    private var hideControlsWork: DispatchWorkItem?
    /// When this controller finished loading its view — used to give AVKit's
    /// settle-time spurious close-delegate fire a short grace window (ISSUE-016)
    /// without also swallowing a real user close during a slow load.
    private var viewLoadedAt = Date()
    /// True once the engine has reported `.playing` at least once this session.
    private var hasEverPlayed = false
    /// Tracked from our own PiP delegate callbacks below — `AVPlayerViewController`
    /// does not itself expose an `isPictureInPictureActive` property.
    private var isPipActive = false

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
        viewLoadedAt = Date()

        // AVKit exposes no controls-visibility signal, so mirror its tap-to-toggle:
        // a non-intrusive recognizer (runs alongside AVKit's own gesture, ignores
        // taps on AVKit's buttons/scrubber) flips `vm.controlsVisible` in lockstep.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleControlsTap))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        scheduleControlsAutoHide()

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

        vm.engine.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self, state == .playing else { return }
                self.hasEverPlayed = true
                // Rearm the auto-hide on every resume: a timer that fired while
                // paused bails on its `.playing` guard without rescheduling, which
                // used to strand the custom overlays (tracks menu, SharePlay
                // button) on screen for the rest of the session.
                if self.vm.controlsVisible {
                    self.scheduleControlsAutoHide()
                }
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

    // MARK: - Controls visibility (mirrors AVKit's chrome)

    @objc private func handleControlsTap() {
        setControlsVisible(!vm.controlsVisible)
    }

    private func setControlsVisible(_ visible: Bool) {
        vm.controlsVisible = visible
        if visible {
            scheduleControlsAutoHide()
        } else {
            hideControlsWork?.cancel()
        }
    }

    /// Auto-hide after the same idle window AVKit uses, but keep the chrome up while
    /// paused (AVKit does the same) so the tracks button stays reachable when stopped.
    private func scheduleControlsAutoHide() {
        hideControlsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.vm.state == .playing else { return }
            self.vm.controlsVisible = false
        }
        hideControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Don't toggle when the user is actually operating AVKit's controls
        // (play/pause, scrubber, volume) — only bare taps on the video toggle chrome.
        !(touch.view is UIControl)
    }

    // MARK: - AVPlayerViewControllerDelegate

    /// AVKit's own close control collapses the full-screen player; route it to the
    /// host so the engine stops and the cover dismisses (no duplicate close button).
    ///
    /// AVKit also emits this during initial setup — before playback starts — as it
    /// settles its presentation, and again when Picture in Picture starts (which also
    /// collapses the full-screen presentation). Honoring either spurious fire tore the
    /// player down before it ever played, or the instant PiP kicked in, so we ignore
    /// the close: while PiP is active, and until either real playback has started or a
    /// short settle-time grace window has elapsed (whichever the load takes — a slow
    /// load should never eat a genuine user close).
    func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator
    ) {
        guard !isPipActive else { return }
        guard hasEverPlayed || Date().timeIntervalSince(viewLoadedAt) > 2.0 else { return }
        let close = onClose
        coordinator.animate(alongsideTransition: nil) { context in
            guard !context.isCancelled else { return }
            close()
        }
    }

    // MARK: - Picture in Picture

    /// The engine's background-keepalive policy reads `pictureInPictureActive` to
    /// decide whether a paused PiP session should be torn down; wire it to AVKit's
    /// own PiP lifecycle so it reflects reality.
    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPipActive = true
        vm.engine.pictureInPictureActive = true
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        isPipActive = false
        vm.engine.pictureInPictureActive = false
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
