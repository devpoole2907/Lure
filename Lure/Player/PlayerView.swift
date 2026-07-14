import SwiftUI
import AetherEngine

/// Full-screen video player. Presented as a `.fullScreenCover`.
///
/// On appear: loads the stream from Jellyfin via `PlayerViewModel.load(…)`.
/// On dismiss: stops the engine and reports playback position to Jellyfin.
///
/// On iOS playback is hosted in a native `AVPlayerViewController` (`AVPlayerHostView`)
/// and on macOS in AVKit's `AVPlayerView` (`MacPlayerHostView`) for the native decode
/// path, giving AVKit's own transport, scrubbing, AirPlay, PiP and Now Playing. The
/// software-decode path (and tvOS) uses the engine's render surface with the custom
/// SwiftUI `TransportOverlay`.
struct PlayerView: View {
    @State var vm: PlayerViewModel
    let media: PlayableMedia
    var onStopped: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(WatchTogetherCoordinator.self) private var watchTogetherCoordinator
    // Optional: injected by `PlayerPresentationModifier`'s `fullScreenCover` on iOS, but
    // `PlayerWindowView` (macOS's separate player window) doesn't have one to pass down --
    // this stays nil there rather than crashing, and the sessionError banner below is
    // simply a no-op on that path (v1 scope, see FIX 8's multi-window note).
    @Environment(InAppNotificationCenter.self) private var notificationCenter: InAppNotificationCenter?
    @State private var hasStartedLoad = false
    @State private var didStop = false

    var body: some View {
        playerContent
            .persistentSystemOverlays(.hidden)
            .preferredColorScheme(.dark)
            #if os(iOS)
            .statusBarHidden(true)
            #endif
            .onAppear {
                #if DEBUG
                print("[PlayerView] onAppear hasStartedLoad=\(hasStartedLoad) itemId=\((media.itemId ?? "").isEmpty ? "<empty>" : media.itemId ?? "") title=\(media.title) mediaType=\(media.mediaType)")
                #endif
                PlayerOrientationController.lockLandscape()
                // Joined-in-progress case: a Watch Together session may already be
                // active (this device just received one via `listenForIncomingSessions()`
                // moments before this view finished presenting), or `vm` simply needs to
                // be on record so a session this device itself starts can find it.
                watchTogetherCoordinator.registerActiveViewModel(vm)
                guard !hasStartedLoad else { return }
                hasStartedLoad = true
                Task {
                    await vm.load(media)
                }
            }
            .onDisappear {
                PlayerOrientationController.unlock()
                watchTogetherCoordinator.detach()
                // Safety net: any dismissal that bypassed stop() — the cover being
                // swapped for a newly presented video, AVKit close-delegate edge
                // cases — must still kill the engine, or its session lives on
                // headless and resumes audio on the next foreground.
                if !didStop {
                    didStop = true
                    Task { await vm.stop() }
                }
            }
            .onChange(of: vm.playbackEnded) { _, ended in
                guard ended else { return }
                Task { await stop(reportToJellyfin: false) }
            }
            // Mirrors `PlayerCoordinator.presentationError` (see PlayerCoordinator.swift):
            // a SharePlay activation failure surfaces here rather than only to the
            // `#if DEBUG` console log, since the button tap that triggers it happens
            // while this screen is already on top.
            .onChange(of: watchTogetherCoordinator.sessionError) { _, message in
                guard let message else { return }
                notificationCenter?.show(LureBannerItem(
                    title: "Watch Together",
                    message: message,
                    style: .error
                ))
                watchTogetherCoordinator.sessionError = nil
            }
    }

    @ViewBuilder
    private var playerContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            AVPlayerHostView(vm: vm) {
                Task { await stop() }
            }
            .ignoresSafeArea()

            SubtitleOverlay(vm: vm)
                .ignoresSafeArea()

            // The software backend has no AVPlayer for AVKit to drive, so fall back
            // to the full custom transport; the native backend uses AVKit's controls
            // plus a light overlay for the things AVKit can't surface.
            if vm.isSoftwareBackend {
                TransportOverlay(vm: vm) {
                    Task { await stop() }
                }
                .ignoresSafeArea()
            } else {
                nativeAuxOverlay
            }
            #elseif os(macOS)
            MacPlayerHostView(vm: vm)
                .ignoresSafeArea()

            SubtitleOverlay(vm: vm)
                .ignoresSafeArea()

            // Same split as iOS: AVKit's chrome drives the native backend, and the
            // full custom transport only appears when there is no AVPlayer for it.
            if vm.isSoftwareBackend {
                TransportOverlay(vm: vm) {
                    Task { await stop() }
                }
                .ignoresSafeArea()
            } else {
                nativeAuxOverlay
            }
            #else
            PlayerLayerView(engine: vm.engine)
                .ignoresSafeArea()

            SubtitleOverlay(vm: vm)
                .ignoresSafeArea()

            TransportOverlay(vm: vm) {
                Task { await stop() }
            }
            .ignoresSafeArea()
            #endif

            if vm.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            if let error = vm.errorMessage {
                errorView(error)
            }

            if vm.controlsVisible {
                watchTogetherButton
            }

            // `ContentView`'s own banner overlay lives outside this `fullScreenCover`,
            // so it's covered by this screen while the player is up (iOS) -- render the
            // same `notificationCenter` here too, otherwise a mid-session sessionError
            // banner would be set but never actually seen.
            #if !os(tvOS)
            if let banner = notificationCenter?.currentBanner {
                LureNotificationOverlay(item: banner) {
                    notificationCenter?.dismiss()
                }
                .transition(.lureNotificationBanner)
            }
            #endif
        }
        .lureBannerAlertHost(notificationCenter)
    }

    /// SharePlay entry point. Lives in the outer `ZStack` (like `isBuffering`/`errorView`
    /// above) so one call site covers the AVKit-native path, the custom `TransportOverlay`
    /// path, and macOS. Gated on `vm.controlsVisible`, the same flag `nativeAuxOverlay`
    /// fades its own chrome on, so it hides/shows together with the rest of the transport.
    private var watchTogetherButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    watchTogetherCoordinator.startSession(media: media)
                } label: {
                    overlayIcon("shareplay", tinted: watchTogetherCoordinator.isSessionActive)
                }
                // Plain style everywhere: macOS's default bordered style draws an
                // opaque plate behind the circular glass icon.
                .buttonStyle(.plain)
                .accessibilityLabel(watchTogetherCoordinator.isSessionActive ? "Watch Together (active)" : "Watch Together")
                .padding(.trailing, watchTogetherPadding.trailing)
                .padding(.top, watchTogetherPadding.top)
            }
            Spacer()
        }
        .opacity(vm.controlsVisible ? 1 : 0)
        .allowsHitTesting(vm.controlsVisible)
        .animation(.easeInOut(duration: 0.25), value: vm.controlsVisible)
        .ignoresSafeArea()
    }

    /// macOS's inline AVKit chrome parks its volume slider in the top-right corner,
    /// so the SharePlay button drops below it there; iOS keeps it tight to the corner.
    private var watchTogetherPadding: (trailing: CGFloat, top: CGFloat) {
        #if os(macOS)
        (24, 72)
        #else
        (20, 12)
        #endif
    }

    /// `tinted` marks the Watch Together button's active state (an in-progress
    /// SharePlay session) -- the other `overlayIcon` call sites just leave it `false`.
    private func overlayIcon(_ systemName: String, tinted: Bool = false) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tinted ? .blue : .white)
            .frame(width: 44, height: 44)
            .glassEffect(tinted ? .regular.tint(.blue).interactive() : .regular.interactive(), in: Circle())
    }

    #if os(iOS) || os(macOS)
    /// Where the custom aux chrome sits relative to AVKit's. iOS centers its
    /// transport bottom-left with generous safe-area margins; macOS's floating
    /// chrome hugs the window edges (volume top-right, scrubber flush bottom),
    /// so the title tucks closer to the corner and clears the scrubber row.
    private var auxTitlePadding: (horizontal: CGFloat, bottom: CGFloat) {
        #if os(macOS)
        (28, 96)
        #else
        (88, 88)
        #endif
    }

    /// Slim custom strip over AVKit's native chrome on the native backend. AVKit
    /// owns close / transport / volume / AirPlay / PiP / Enhance Dialogue and (via
    /// `prepareNativeSubtitles`) the native text-subtitle menu. We only surface what
    /// AVKit can't drive from this engine: switching among the source's alternate
    /// audio tracks and bitmap (PGS) subtitle tracks, plus skip-intro / next-episode.
    /// Empty regions are non-interactive so taps fall through to AVKit's controls.
    @ViewBuilder
    private var nativeAuxOverlay: some View {
        ZStack {
            VStack(spacing: 0) {
                Spacer()

                if hasTrackChoices {
                    HStack {
                        Spacer()
                        tracksMenu
                    }
                    .padding(.trailing, 20)
                    .opacity(vm.controlsVisible ? 1 : 0)
                    .allowsHitTesting(vm.controlsVisible)
                    .animation(.easeInOut(duration: 0.25), value: vm.controlsVisible)
                }

                Spacer()

                if vm.showNextEpisodeCountdown, let next = vm.nextEpisode {
                    nextEpisodePrompt(next)
                } else if vm.activeIntroSegment != nil {
                    HStack {
                        Spacer()
                        Button {
                            Task { await vm.skipIntro() }
                        } label: {
                            Label("Skip Intro", systemImage: "forward.end.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 24)
                    }
                    .padding(.bottom, 120)
                }
            }

            HStack {
                playerTitleBlock
                Spacer()
            }
            .padding(.horizontal, auxTitlePadding.horizontal)
            .padding(.bottom, auxTitlePadding.bottom)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .opacity(vm.controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: vm.controlsVisible)
        }
        .ignoresSafeArea()
    }

    private var playerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let ep = vm.episodeLabel {
                Text(ep)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }

            Text(vm.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Only worth showing the tracks button when there's actually a choice to make:
    /// more than one audio track, or any subtitle track the user can toggle.
    private var hasTrackChoices: Bool {
        vm.audioTracks.count > 1 || !vm.subtitleTracks.isEmpty
    }

    @ViewBuilder
    private var tracksMenu: some View {
        Menu {
            if vm.audioTracks.count > 1 {
                Menu {
                    ForEach(vm.audioTracks) { track in
                        trackButton(title: track.displayLabel, isSelected: vm.selectedAudioTrackId == track.id) {
                            vm.selectAudioTrack(track)
                        }
                    }
                } label: {
                    Label("Audio", systemImage: "waveform")
                }
            }
            if !vm.subtitleTracks.isEmpty {
                Menu {
                    trackButton(title: "Off", isSelected: vm.selectedSubtitleTrackId == nil) {
                        vm.clearSubtitles()
                    }
                    ForEach(vm.subtitleTracks) { track in
                        trackButton(title: track.displayLabel, isSelected: vm.selectedSubtitleTrackId == track.id) {
                            vm.selectSubtitleTrack(track)
                        }
                    }
                } label: {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
            }
        } label: {
            overlayIcon("captions.bubble")
        }
        // macOS renders Menu as a bordered pull-down with a disclosure chevron by
        // default; render just the glass icon like iOS does.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Audio & subtitles")
    }

    @ViewBuilder
    private func trackButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func nextEpisodePrompt(_ next: JellyfinItem) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text("Up Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(next.episodeLabel ?? next.name ?? "Next Episode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Button("Cancel") {
                        vm.cancelNextEpisodeCountdown()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))

                    Button {
                        Task { await vm.playNextEpisode() }
                    } label: {
                        Label("Play Now (\(vm.nextEpisodeCountdown)s)", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.trailing, 24)
        }
        .padding(.bottom, 96)
    }
    #endif

    private func stop(reportToJellyfin: Bool = true) async {
        didStop = true
        await vm.stop(reportToJellyfin: reportToJellyfin)
        onStopped?()
        // Rotate back to portrait *before* tearing down the cover, otherwise the
        // detail view underneath flashes in landscape and snaps round afterwards.
        PlayerOrientationController.unlock()
        try? await Task.sleep(for: .milliseconds(350))
        dismiss()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button("Retry") {
                    Task { await vm.load(media) }
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Close") {
                    Task { await stop() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
