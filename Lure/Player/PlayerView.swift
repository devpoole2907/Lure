import SwiftUI
import AetherEngine

/// Full-screen video player. Presented as a `.fullScreenCover`.
///
/// On appear: loads the stream from Jellyfin via `PlayerViewModel.load(…)`.
/// On dismiss: stops the engine and reports playback position to Jellyfin.
///
/// On UIKit platforms playback is hosted in a native `AVPlayerViewController`
/// (`AVPlayerHostView`) for the native decode path, giving AVKit's own transport,
/// scrubbing, AirPlay, PiP and Now Playing. The software-decode path (and macOS)
/// uses the engine's render surface with the custom SwiftUI `TransportOverlay`.
struct PlayerView: View {
    @State var vm: PlayerViewModel
    let media: PlayableMedia

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartedLoad = false

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
                guard !hasStartedLoad else { return }
                hasStartedLoad = true
                Task {
                    await vm.load(media)
                }
            }
            .onDisappear {
                PlayerOrientationController.unlock()
            }
            .onChange(of: vm.playbackEnded) { _, ended in
                guard ended else { return }
                Task { await stop(reportToJellyfin: false) }
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
        }
    }

    #if os(iOS)
    private func overlayIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: Circle())
    }

    /// Slim custom strip over AVKit's native chrome on the native backend. AVKit
    /// owns close / transport / volume / AirPlay / PiP / Enhance Dialogue and (via
    /// `prepareNativeSubtitles`) the native text-subtitle menu. We only surface what
    /// AVKit can't drive from this engine: switching among the source's alternate
    /// audio tracks and bitmap (PGS) subtitle tracks, plus skip-intro / next-episode.
    /// Empty regions are non-interactive so taps fall through to AVKit's controls.
    @ViewBuilder
    private var nativeAuxOverlay: some View {
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
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 120)
            }
        }
        .ignoresSafeArea()
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
        await vm.stop(reportToJellyfin: reportToJellyfin)
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
