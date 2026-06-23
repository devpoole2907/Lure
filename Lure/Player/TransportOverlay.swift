import SwiftUI
import AVFoundation
import AetherEngine

struct TransportOverlay: View {
    let vm: PlayerViewModel
    let onDismiss: () -> Void

    @State private var scrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var showAudioPicker = false
    @State private var showSubtitlePicker = false
    @State private var currentRate: Float = 1.0
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var controlsVisible = true

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            if controlsVisible {
                ZStack {
                    // Two-band gradient: dark at top/bottom, clear in middle (matches system player)
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 160)
                        Spacer()
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 200)
                    }
                    .ignoresSafeArea()

                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        centerControls
                        Spacer()
                        bottomBar
                    }
                }
                .transition(.opacity)
            }

            // Intro skip (always visible when in intro)
            if let intro = vm.activeIntroSegment {
                introSkipButton(intro)
            }

            // Next episode countdown
            if vm.showNextEpisodeCountdown, let next = vm.nextEpisode {
                nextEpisodeOverlay(next)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.001))
        .contentShape(Rectangle())
        .onTapGesture { toggleControls() }
        .confirmationDialog(
            "Audio Track",
            isPresented: $showAudioPicker,
            titleVisibility: .visible
        ) {
            audioPickerActions
        }
        .confirmationDialog(
            "Subtitles",
            isPresented: $showSubtitlePicker,
            titleVisibility: .visible
        ) {
            subtitlePickerActions
        }
        .onAppear { resetHideTimer() }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Done") { onDismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Close player")

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let ep = vm.episodeLabel {
                    Text(ep)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge = vm.videoFormatBadge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.2), in: Capsule())
                    .accessibilityLabel("Video format: \(badge)")
            }

            // Placeholder: replaced with AVRoutePickerView when AirPlay is implemented
            Color.clear.frame(width: 44, height: 44)
            // Placeholder: replaced with PiP trigger when Picture in Picture is implemented
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Center Controls

    private var centerControls: some View {
        HStack(spacing: 44) {
            skipButton(systemImage: "gobackward.15", label: "Skip back 15 seconds") {
                Task { await vm.skip(by: -15) }
            }

            playPauseButton

            skipButton(systemImage: "goforward.15", label: "Skip forward 15 seconds") {
                Task { await vm.skip(by: 15) }
            }
        }
    }

    private var playPauseButton: some View {
        Button {
            vm.togglePlayPause()
            resetHideTimer()
        } label: {
            Group {
                if vm.isBuffering {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
        }
        .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            resetHideTimer()
        } label: {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            scrubBar
            bottomButtons
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private var scrubBar: some View {
        VStack(spacing: 4) {
            #if !os(tvOS)
            Slider(
                value: scrubbing ? $scrubPosition : .init(
                    get: { vm.duration > 0 ? vm.currentTime / vm.duration : 0 },
                    set: { _ in }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing {
                        Task {
                            await vm.seek(to: scrubPosition * vm.duration)
                        }
                        resetHideTimer()
                    } else {
                        scrubPosition = vm.duration > 0 ? vm.currentTime / vm.duration : 0
                        hideTask?.cancel()
                    }
                }
            )
            .tint(.white)
            .accessibilityLabel("Seek position")
            #else
            // tvOS: show a progress bar (seek is handled via Siri Remote focus/swipe)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * (vm.duration > 0 ? min(vm.currentTime / vm.duration, 1) : 0))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 20)
            .accessibilityLabel("Seek position")
            #endif

            HStack {
                Text(formatTime(vm.currentTime))
                Spacer()
                Text("-\(formatTime(max(0, vm.duration - vm.currentTime)))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var bottomButtons: some View {
        HStack(spacing: 20) {
            // Subtitles first (CC | Audio order matches system player)
            Button {
                showSubtitlePicker = true
                resetHideTimer()
            } label: {
                Label("Subtitles", systemImage: vm.isSubtitleActive ? "captions.bubble.fill" : "captions.bubble")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }

            // Audio track
            Button {
                showAudioPicker = true
                resetHideTimer()
            } label: {
                Label("Audio", systemImage: "speaker.wave.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .disabled(vm.audioTracks.isEmpty)

            Spacer()

            // Playback speed
            Menu {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        currentRate = rate
                        vm.setRate(rate)
                        resetHideTimer()
                    } label: {
                        if rate == currentRate {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(rateLabel(currentRate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(currentRate == 1.0 ? .white.opacity(0.7) : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .accessibilityLabel("Playback speed: \(rateLabel(currentRate))")

            // Aspect ratio
            Button {
                vm.toggleGravity()
                resetHideTimer()
            } label: {
                Image(systemName: vm.videoGravity == .resizeAspect ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel(vm.videoGravity == .resizeAspect ? "Fill screen" : "Fit to screen")
        }
    }

    // MARK: - Intro Skip

    private func introSkipButton(_ segment: JellyfinMediaSegment) -> some View {
        VStack {
            Spacer()
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
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                        )
                }
                .padding(.trailing, 24)
                .padding(.bottom, 120)
            }
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: vm.activeIntroSegment != nil)
    }

    // MARK: - Next Episode Overlay

    private func nextEpisodeOverlay(_ item: JellyfinItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 10) {
                    if let ep = item.episodeLabel {
                        Text("Next: \(ep)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(item.seriesName ?? item.name ?? "Next Episode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            vm.showNextEpisodeCountdown = false
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))

                        Button("Play Now (\(vm.nextEpisodeCountdown)s)") {
                            Task { await vm.playNextEpisode() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.trailing, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Track Pickers

    @ViewBuilder
    private var audioPickerActions: some View {
        ForEach(vm.audioTracks) { track in
            Button {
                vm.selectAudioTrack(track)
            } label: {
                if track.id == vm.selectedAudioTrackId {
                    Label(trackLabel(track), systemImage: "checkmark")
                } else {
                    Text(trackLabel(track))
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    private var subtitlePickerActions: some View {
        if vm.isSubtitleActive {
            Button("Off") { vm.clearSubtitles() }
        }
        ForEach(vm.subtitleTracks) { track in
            Button {
                vm.selectSubtitleTrack(track)
            } label: {
                if track.id == vm.selectedSubtitleTrackId {
                    Label(track.name, systemImage: "checkmark")
                } else {
                    Text(track.name)
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Helpers

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible { resetHideTimer() }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                controlsVisible = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "1×" : String(format: "%g×", rate)
    }

    private func trackLabel(_ track: TrackInfo) -> String {
        var parts: [String] = []
        if let lang = track.language { parts.append(lang.uppercased()) }
        parts.append(track.name)
        if track.isAtmos { parts.append("Atmos") }
        else if track.channels == 6 { parts.append("5.1") }
        else if track.channels == 8 { parts.append("7.1") }
        return parts.joined(separator: " \u{2022} ")
    }
}
