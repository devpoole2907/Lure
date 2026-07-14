#if os(macOS)
import SwiftUI
import AppKit
import AVKit
import AVFoundation
import Combine
import AetherEngine

/// Hosts AetherEngine playback inside AVKit's `AVPlayerView` — macOS's
/// counterpart to `PlayerHostController` (iOS). The native transport chrome
/// (center play/skip cluster, bottom scrubber, volume, PiP, subtitle/speed
/// menus, fullscreen) all comes from AVKit, matching the Apple TV app's player.
///
/// - **Native backend** (formats AVFoundation can decode): the engine publishes a
///   real `AVPlayer` via `engine.$currentAVPlayer`; we hand it to `AVPlayerView`
///   and AVKit renders + drives everything.
/// - **Software backend** (MKV / dav1d / VP9 etc.): there is no `AVPlayer`, so we
///   mount the engine's own render surface into `contentOverlayView`, hide AVKit's
///   (inert) controls, and let the SwiftUI `TransportOverlay` drive playback.
///
/// AVKit exposes no controls-visibility signal on macOS either, so this view
/// mirrors the chrome's mouse-driven show/hide into `vm.controlsVisible` for the
/// custom overlays (tracks menu, skip intro, Watch Together). The mirroring is
/// deliberately self-correcting so overlays can never be left stranded:
/// - any mouse movement shows controls and (re)arms the hide timer,
/// - every transition into `.playing` rearms the hide timer (a timer that fired
///   while paused would otherwise never hide the chrome after resume),
/// - any non-playing state pins controls visible, like AVKit does while paused.
@MainActor
final class PlayerHostNSView: NSView {
    private let vm: PlayerViewModel
    private let playerView = AVPlayerView()
    private let aetherView = AetherPlayerView()
    private var aetherViewMounted = false
    private var subscriptions: Set<AnyCancellable> = []
    private var hideControlsTask: Task<Void, Never>?
    private var hostTrackingArea: NSTrackingArea?

    init(vm: PlayerViewModel) {
        self.vm = vm
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // `.inline` = the full-width bottom transport bar (what Safari video uses),
        // the closest native match to the TV app's player; `.floating` is the small
        // centered QuickTime panel. (The TV app itself is Catalyst running the iOS
        // AVPlayerViewController chrome, which AppKit's AVPlayerView can't render.)
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        playerView.allowsPictureInPicturePlayback = true
        // AVKit reserves a second slot in the top-left button cluster for its
        // optional buttons (all off by default), which otherwise renders as dead
        // space next to PiP. Fill it with the fullscreen toggle — useful anyway
        // now that the player window has no title bar.
        playerView.showsFullScreenToggleButton = true
        playerView.frame = bounds
        playerView.autoresizingMask = [.width, .height]
        addSubview(playerView)

        bindEngine()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func bindEngine() {
        // The engine republishes its native AVPlayer on every internal reload
        // (an audio-track switch rebuilds the native host), so re-bind each time.
        // nil on the software path — assigning nil drops AVKit's stale player so it
        // stops drawing its own loading spinner over the engine's frames.
        vm.engine.$currentAVPlayer
            .receive(on: RunLoop.main)
            .sink { [weak self] avPlayer in
                self?.playerView.player = avPlayer
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
                guard let self else { return }
                if state == .playing {
                    self.scheduleControlsAutoHide()
                } else {
                    // Paused / stalled / ended: keep the chrome up (AVKit does the
                    // same) so the tracks button stays reachable while stopped.
                    self.hideControlsTask?.cancel()
                    self.setControlsVisible(true)
                }
            }
            .store(in: &subscriptions)
    }

    /// Called from `dismantleNSView` — SwiftUI may keep the NSView alive briefly
    /// after removal, so stop mirroring and release the player deterministically.
    func teardown() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        subscriptions.removeAll()
        unmountAetherView()
        playerView.player = nil
    }

    // MARK: - Backend presentation

    private func applyBackend(_ backend: PlaybackBackend) {
        let isSoftware = (backend == .software)
        // AVKit's controls can only drive a real AVPlayer; suppress them on the
        // software path where the SwiftUI TransportOverlay takes over.
        playerView.controlsStyle = isSoftware ? .none : .inline
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
        let host = playerView.contentOverlayView ?? self
        aetherView.frame = host.bounds
        aetherView.autoresizingMask = [.width, .height]
        host.addSubview(aetherView, positioned: .below, relativeTo: host.subviews.first)
        vm.engine.bind(view: aetherView)
        aetherViewMounted = true
    }

    private func unmountAetherView() {
        guard aetherViewMounted else { return }
        vm.engine.unbind(view: aetherView)
        aetherView.removeFromSuperview()
        aetherViewMounted = false
    }

    // MARK: - Controls visibility (mirrors AVKit's mouse-driven chrome)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hostTrackingArea {
            removeTrackingArea(hostTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hostTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        revealControls()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        revealControls()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Leaving the window hides the chrome mid-playback (AVKit's behavior);
        // while paused it stays up.
        guard vm.state == .playing else { return }
        hideControlsTask?.cancel()
        setControlsVisible(false)
    }

    private func revealControls() {
        setControlsVisible(true)
        scheduleControlsAutoHide()
    }

    private func setControlsVisible(_ visible: Bool) {
        guard vm.controlsVisible != visible else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.controlsVisible = visible
        }
    }

    /// Auto-hide after the same idle window AVKit uses. The `.playing` guard is
    /// re-checked at fire time, and the timer is rearmed on every resume (see
    /// `bindEngine`), so a fire-while-paused can't strand the overlays visible.
    private func scheduleControlsAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.vm.state == .playing else { return }
            self.setControlsVisible(false)
        }
    }
}

// MARK: - SwiftUI bridge

/// Embeds `PlayerHostNSView` in SwiftUI. Playback is loaded/stopped by the
/// surrounding `PlayerView`; this view only owns the native presentation surface.
struct MacPlayerHostView: NSViewRepresentable {
    let vm: PlayerViewModel

    func makeNSView(context: Context) -> PlayerHostNSView {
        PlayerHostNSView(vm: vm)
    }

    func updateNSView(_ nsView: PlayerHostNSView, context: Context) {}

    static func dismantleNSView(_ nsView: PlayerHostNSView, coordinator: ()) {
        nsView.teardown()
    }
}
#endif
