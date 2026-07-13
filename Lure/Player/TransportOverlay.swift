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
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var controlsVisible = true
    #if os(tvOS)
    @FocusState private var focusedControl: TVTransportFocus?
    @State private var tvScrubbing = false
    @State private var tvScrubPosition: Double = 0
    #endif

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

            // Mid-playback stall/rebuffer indicator (ISSUE-012), distinct from the
            // startup-only spinner on the play/pause button: a healthy-connection
            // rebuffer already shows there via isBuffering, but a source-connection
            // drop/backoff (.stalled) gets no signal at all otherwise.
            if case .stalled = vm.playbackPhase {
                reconnectingIndicator
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
        .onAppear {
            resetHideTimer()
            #if os(tvOS)
            focusedControl = .playPause
            #endif
        }
        .onDisappear {
            hideTask?.cancel()
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            vm.togglePlayPause()
            showTVControls(focusing: .playPause)
        }
        .onExitCommand {
            handleTVExitCommand()
        }
        .onMoveCommand { direction in
            handleTVMoveCommand(direction)
        }
        .onChange(of: focusedControl) { _, _ in
            guard controlsVisible else { return }
            resetHideTimer()
        }
        .onChange(of: vm.showNextEpisodeCountdown) { _, visible in
            guard visible else { return }
            focusTVOverlayAction(.nextPlay)
        }
        .onChange(of: vm.activeIntroSegment != nil) { _, visible in
            guard visible, !vm.showNextEpisodeCountdown else { return }
            focusTVOverlayAction(.skipIntro)
        }
        #endif
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
                #if os(tvOS)
                .focused($focusedControl, equals: .done)
                #endif

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
            #if os(tvOS)
            .focused($focusedControl, equals: .rewind)
            #endif

            playPauseButton

            skipButton(systemImage: "goforward.15", label: "Skip forward 15 seconds") {
                Task { await vm.skip(by: 15) }
            }
            #if os(tvOS)
            .focused($focusedControl, equals: .forward)
            #endif
        }
        #if os(tvOS)
        .focusSection()
        .defaultFocus($focusedControl, .playPause)
        #endif
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
        #if os(tvOS)
        .focused($focusedControl, equals: .playPause)
        #endif
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
            tvScrubber
            #endif

            HStack {
                #if os(tvOS)
                Text(formatTime(tvDisplayedTime))
                Spacer()
                Text("-\(formatTime(max(0, vm.duration - tvDisplayedTime)))")
                #else
                Text(formatTime(vm.currentTime))
                Spacer()
                Text("-\(formatTime(max(0, vm.duration - vm.currentTime)))")
                #endif
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    #if os(tvOS)
    private var tvScrubber: some View {
        Button {
            toggleTVScrub()
        } label: {
            VStack(spacing: 8) {
                if tvScrubbing {
                    Text(formatTime(tvScrubPosition))
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }

                GeometryReader { proxy in
                    let progress = tvDisplayedProgress
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(focusedControl == .scrubber ? 0.34 : 0.25))

                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * progress)

                        Circle()
                            .fill(.white)
                            .frame(width: tvScrubbing || focusedControl == .scrubber ? 16 : 10, height: tvScrubbing || focusedControl == .scrubber ? 16 : 10)
                            .offset(x: max(0, min(proxy.size.width - 16, proxy.size.width * progress - 8)))
                            .opacity(tvScrubbing || focusedControl == .scrubber ? 1 : 0)
                    }
                    .frame(height: tvScrubbing || focusedControl == .scrubber ? 8 : 4)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 24)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: .scrubber)
        .disabled(vm.duration <= 0)
        .accessibilityLabel(tvScrubbing ? "Commit seek" : "Seek position")
        .accessibilityValue(formatTime(tvDisplayedTime))
    }
    #endif

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
            #if os(tvOS)
            .focused($focusedControl, equals: .subtitles)
            #endif

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
            #if os(tvOS)
            .focused($focusedControl, equals: .audio)
            #endif

            Spacer()

            // Playback speed
            Menu {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        vm.setRate(rate)
                        resetHideTimer()
                    } label: {
                        if rate == vm.playbackRate {
                            Label(rateLabel(rate), systemImage: "checkmark")
                        } else {
                            Text(rateLabel(rate))
                        }
                    }
                }
            } label: {
                Text(rateLabel(vm.playbackRate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(vm.playbackRate == 1.0 ? .white.opacity(0.7) : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .accessibilityLabel("Playback speed: \(rateLabel(vm.playbackRate))")
            #if os(tvOS)
            .focused($focusedControl, equals: .rate)
            #endif

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
            #if os(tvOS)
            .focused($focusedControl, equals: .aspect)
            #endif
        }
        #if os(tvOS)
        .focusSection()
        #endif
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
                #if os(tvOS)
                .focused($focusedControl, equals: .skipIntro)
                #endif
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
                            vm.cancelNextEpisodeCountdown()
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        #if os(tvOS)
                        .focused($focusedControl, equals: .nextCancel)
                        #endif

                        Button("Play Now (\(vm.nextEpisodeCountdown)s)") {
                            Task { await vm.playNextEpisode() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
                        #if os(tvOS)
                        .focused($focusedControl, equals: .nextPlay)
                        #endif
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.trailing, 24)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Reconnecting Indicator

    /// Small top-centered capsule shown while `playbackPhase` is `.stalled` (ISSUE-012):
    /// a source-connection drop/retry-backoff, distinct from the ordinary `isBuffering`
    /// spinner already on the play/pause button. Not interactive; always visible
    /// regardless of `controlsVisible` so a silent stall doesn't look like a freeze.
    private var reconnectingIndicator: some View {
        VStack {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.7)
                Text("Reconnecting…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(.top, 60)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .accessibilityLabel("Reconnecting")
    }

    // MARK: - Track Pickers

    @ViewBuilder
    private var audioPickerActions: some View {
        ForEach(vm.audioTracks) { track in
            Button {
                vm.selectAudioTrack(track)
            } label: {
                if track.id == vm.selectedAudioTrackId {
                    Label(track.displayLabel, systemImage: "checkmark")
                } else {
                    Text(track.displayLabel)
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
        #if os(tvOS)
        if tvScrubbing {
            cancelTVScrub(scheduleHide: false)
        }
        #endif
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible.toggle()
        }
        if controlsVisible {
            #if os(tvOS)
            focusedControl = .playPause
            #endif
            resetHideTimer()
        } else {
            hideTask?.cancel()
            #if os(tvOS)
            focusedControl = nil
            #endif
        }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            #if os(tvOS)
            guard !tvScrubbing, !vm.showNextEpisodeCountdown, vm.activeIntroSegment == nil else { return }
            #endif
            withAnimation(.easeInOut(duration: 0.3)) {
                controlsVisible = false
            }
            #if os(tvOS)
            focusedControl = nil
            #endif
        }
    }

    #if os(tvOS)
    private var tvDisplayedTime: Double {
        tvScrubbing ? tvScrubPosition : vm.currentTime
    }

    private var tvDisplayedProgress: CGFloat {
        guard vm.duration > 0 else { return 0 }
        return CGFloat(max(0, min(tvDisplayedTime / vm.duration, 1)))
    }

    private var tvScrubStep: Double {
        guard vm.duration > 0 else { return 15 }
        return max(10, min(60, vm.duration / 120))
    }

    private func showTVControls(focusing focus: TVTransportFocus? = nil) {
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = true
        }
        focusedControl = focus ?? focusedControl ?? .playPause
        resetHideTimer()
    }

    private func focusTVOverlayAction(_ focus: TVTransportFocus) {
        tvScrubbing = false
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsVisible = false
        }
        focusedControl = focus
    }

    private func handleTVExitCommand() {
        if tvScrubbing {
            cancelTVScrub()
            return
        }

        if vm.showNextEpisodeCountdown {
            vm.cancelNextEpisodeCountdown()
            if vm.activeIntroSegment != nil {
                focusTVOverlayAction(.skipIntro)
            } else {
                showTVControls(focusing: .playPause)
            }
            return
        }

        if controlsVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                controlsVisible = false
            }
            hideTask?.cancel()
            focusedControl = nil
            return
        }

        onDismiss()
    }

    private func handleTVMoveCommand(_ direction: MoveCommandDirection) {
        if tvScrubbing {
            switch direction {
            case .left:
                adjustTVScrub(by: -tvScrubStep)
            case .right:
                adjustTVScrub(by: tvScrubStep)
            default:
                break
            }
            return
        }

        if !controlsVisible {
            showTVControls()
        } else {
            resetHideTimer()
        }
    }

    private func toggleTVScrub() {
        guard vm.duration > 0 else { return }
        if tvScrubbing {
            let target = tvScrubPosition
            tvScrubbing = false
            Task {
                await vm.seek(to: target)
                resetHideTimer()
            }
        } else {
            tvScrubPosition = max(0, min(vm.currentTime, vm.duration))
            tvScrubbing = true
            showTVControls(focusing: .scrubber)
            hideTask?.cancel()
        }
    }

    private func adjustTVScrub(by seconds: Double) {
        guard vm.duration > 0 else { return }
        tvScrubPosition = max(0, min(vm.duration, tvScrubPosition + seconds))
        hideTask?.cancel()
    }

    private func cancelTVScrub(scheduleHide: Bool = true) {
        tvScrubbing = false
        tvScrubPosition = max(0, min(vm.currentTime, vm.duration))
        if scheduleHide {
            resetHideTimer()
        }
    }
    #endif

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

}

#if os(tvOS)
private enum TVTransportFocus: Hashable {
    case done
    case rewind
    case playPause
    case forward
    case scrubber
    case subtitles
    case audio
    case rate
    case aspect
    case skipIntro
    case nextCancel
    case nextPlay
}
#endif
