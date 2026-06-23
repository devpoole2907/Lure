import SwiftUI
import Combine
import AVFoundation
import AetherEngine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class PlayerViewModel {

    // MARK: - Engine state (mirrored from AetherEngine @Published)
    var state: PlaybackState = .idle
    var currentTime: Double = 0
    var duration: Double = 0
    var progress: Float = 0
    var videoFormat: VideoFormat = .sdr
    var audioTracks: [TrackInfo] = []
    var subtitleTracks: [TrackInfo] = []
    var subtitleCues: [SubtitleCue] = []
    var isSubtitleActive: Bool = false
    var isLoadingSubtitles: Bool = false
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    var playbackBackend: PlaybackBackend = .none

    /// True when the engine is software-decoding (e.g. MKV / dav1d), which has no
    /// `AVPlayer` for AVKit to drive — those sessions need our custom transport.
    /// The native backend renders through AVKit's own `AVPlayer` + controls.
    var isSoftwareBackend: Bool { playbackBackend == .software }

    // MARK: - App-level state
    var title: String = ""
    var episodeLabel: String?
    var errorMessage: String?
    var isLoading: Bool = false
    var segments: [JellyfinMediaSegment] = []
    var activeIntroSegment: JellyfinMediaSegment?
    var activeOutroSegment: JellyfinMediaSegment?
    var nextEpisode: JellyfinItem?
    var showNextEpisodeCountdown: Bool = false
    var nextEpisodeCountdown: Int = 10

    // Current track selections (for UI state)
    var selectedAudioTrackId: Int? = nil
    var selectedSubtitleTrackId: Int? = nil

    // Future: PiP coordinator (AVPictureInPictureController + AVSampleBufferDisplayLayer delegate)
    // var pipCoordinator: PiPCoordinator?
    // var onRestoreFromPiP: (() -> Void)?

    // Future: Chromecast coordinator (Google Cast SDK)
    // var castCoordinator: CastCoordinator?

    // MARK: - Engine

    let engine: AetherEngine

    // MARK: - Jellyfin session state (private)
    private let jellyfinService: JellyfinService
    private(set) var jellyfinClient: JellyfinAPIClient?
    private var itemId: String = ""
    private var mediaSourceId: String = ""
    private var playSessionId: String = ""
    private var isDirect: Bool = true

    // MARK: - Combine
    private var cancellables: Set<AnyCancellable> = []
    private var progressTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var startupDiagnosticsTask: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []
    #if DEBUG
    private var lastLoggedPlaybackSecond = -1
    #endif

    // MARK: - Init

    init(jellyfinService: JellyfinService) throws {
        engine = try AetherEngine()
        self.jellyfinService = jellyfinService
        bindPublishers()
        observeLifecycle()
    }

    // MARK: - Load

    @MainActor
    func load(
        itemId: String,
        title: String,
        episodeLabel: String? = nil,
        serviceUrl: String? = nil,
        tmdbId: Int? = nil,
        releaseYear: Int? = nil,
        mediaType: String = "movie"
    ) async {
        self.title = title
        self.episodeLabel = episodeLabel
        self.itemId = itemId
        errorMessage = nil
        isLoading = true
        stopProgressReporting()
        #if DEBUG
        lastLoggedPlaybackSecond = -1
        print("[PlayerViewModel] load requested itemId=\(itemId.isEmpty ? "<empty>" : itemId) title=\(title) mediaType=\(mediaType) serviceUrl=\(serviceUrl ?? "nil") tmdbId=\(tmdbId.map(String.init) ?? "nil") releaseYear=\(releaseYear.map(String.init) ?? "nil")")
        #endif

        do {
            guard let client = jellyfinService.client else {
                throw JellyfinError.noCredentials
            }
            jellyfinClient = client

            // If no Jellyfin item ID was provided, resolve it from serviceUrl or TMDB ID
            if self.itemId.isEmpty {
                guard let found = try await jellyfinService.findItemId(
                    serviceUrl: serviceUrl,
                    tmdbId: tmdbId ?? 0,
                    mediaType: mediaType,
                    title: title,
                    releaseYear: releaseYear
                ) else {
                    throw JellyfinError.itemNotFound
                }
                self.itemId = found
            }

            // Read resume position
            let item = try await client.getItem(itemId: self.itemId)
            let resumePosition = item.resumePositionSeconds

            // Get playback info
            let info = try await client.getPlaybackInfo(itemId: self.itemId, startPositionSeconds: resumePosition)
            guard let playSessionId = info.playSessionId,
                  let mediaSource = info.mediaSources?.first
            else { throw JellyfinError.noPlayableSource }

            self.playSessionId = playSessionId
            self.mediaSourceId = mediaSource.id ?? self.itemId

            #if DEBUG
            print("[PlayerViewModel] Source: container=\(mediaSource.container ?? "nil"), directPlay=\(mediaSource.supportsDirectPlay ?? false), directStream=\(mediaSource.supportsDirectStream ?? false), transcodingURL=\(mediaSource.transcodingUrl != nil)")
            if let transcodingUrl = mediaSource.transcodingUrl {
                print("[PlayerViewModel] TranscodingURL: \(transcodingUrl.prefix(160))")
            }
            logMediaStreams(mediaSource.mediaStreams)
            #endif

            // Build stream URL
            var streamCandidates: [(url: URL, isDirect: Bool, label: String)] = []
            if mediaSource.supportsDirectPlay == true {
                if let url = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: true,
                    container: mediaSource.container
                ) {
                    streamCandidates.append((url, true, "static direct play stream.\(mediaSource.container ?? "mp4")"))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate static direct play: \(url.absoluteString)")
                    #endif
                }
                if let fallbackURL = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: true,
                    container: mediaSource.container,
                    useContainerExtension: false
                ) {
                    streamCandidates.append((fallbackURL, true, "static direct play fallback stream"))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate static direct play fallback: \(fallbackURL.absoluteString)")
                    #endif
                }
            }
            if mediaSource.supportsDirectStream == true {
                if let url = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: false,
                    container: mediaSource.container
                ) {
                    streamCandidates.append((url, true, "non-static direct stream stream.\(mediaSource.container ?? "mp4")"))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate non-static direct stream: \(url.absoluteString)")
                    #endif
                }
                if let fallbackURL = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: false,
                    container: mediaSource.container,
                    useContainerExtension: false
                ) {
                    streamCandidates.append((fallbackURL, true, "non-static direct stream fallback stream"))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate non-static direct stream fallback: \(fallbackURL.absoluteString)")
                    #endif
                }
            }
            if let transPath = mediaSource.transcodingUrl,
               let url = client.transcodingURL(path: transPath) {
                streamCandidates.append((url, false, "transcode"))
                #if DEBUG
                print("[PlayerViewModel] Candidate transcode: \(url.absoluteString)")
                #endif
            }
            guard !streamCandidates.isEmpty else {
                throw JellyfinError.noPlayableSource
            }

            // Load into engine. The engine owns its display surface and attaches the
            // appropriate layer to the bound AetherPlayerView; HDR presentation is now
            // handled internally via display-criteria matching (LoadOptions defaults).
            let startPosition = resumePosition > 0 ? resumePosition : nil
            var lastLoadError: Error?
            for candidate in streamCandidates {
                #if DEBUG
                print("[PlayerViewModel] Trying \(candidate.label): \(candidate.url.absoluteString)")
                await client.playbackURLDiagnostics(candidate.url)
                #endif
                startStartupDiagnostics(streamURL: candidate.url, startPosition: startPosition)
                do {
                    // NOTE: LoadOptions(prepareNativeSubtitles: true) would surface text
                    // subs in AVKit's native menu, but on PGS-heavy sources the engine's
                    // mov_text injection emits malformed samples (negative durations / no
                    // pts) that corrupt the fMP4 segments and fail playback with
                    // "Cannot Open" (AetherEngine #55). Until that's fixed upstream we keep
                    // subtitle selection host-rendered via our own tracks menu.
                    try await engine.load(url: candidate.url, startPosition: startPosition)
                    isDirect = candidate.isDirect
                    #if DEBUG
                    print("[PlayerViewModel] Loaded via \(candidate.label)")
                    #endif
                    lastLoadError = nil
                    break
                } catch {
                    lastLoadError = error
                    #if DEBUG
                    print("[PlayerViewModel] Load candidate failed label=\(candidate.label) error=\(String(describing: error)) localized=\(error.localizedDescription)")
                    #endif
                }
            }
            if let lastLoadError {
                throw lastLoadError
            }
            #if DEBUG
            print("[PlayerViewModel] engine.load returned state=\(String(describing: state)) current=\(String(format: "%.3f", currentTime)) duration=\(String(format: "%.3f", duration)) layer=\(displayLayerStatus())")
            #endif

            // Auto-select preferred audio track
            autoSelectAudioTrack()

            // Start playback
            engine.play()
            await recoverStartupIfNeeded(startPosition: startPosition)
            isLoading = false

            // Report start to Jellyfin
            await client.reportPlaybackStart(
                itemId: self.itemId,
                playSessionId: playSessionId,
                mediaSourceId: self.mediaSourceId,
                positionSeconds: resumePosition,
                isDirect: isDirect
            )
            startProgressReporting()

            // Fetch segments for intro skip (best-effort)
            segments = (try? await client.getMediaSegments(itemId: self.itemId)) ?? []

            // Fetch next episode for series
            if let seriesId = item.seriesId {
                nextEpisode = try? await client.getNextUp(seriesId: seriesId)
            }

        } catch {
            isLoading = false
            errorMessage = (error as? JellyfinError)?.errorDescription ?? error.localizedDescription
            #if DEBUG
            print("[PlayerViewModel] load failed error=\(error.localizedDescription) state=\(String(describing: state)) layer=\(displayLayerStatus())")
            #endif
        }
    }

    private func recoverStartupIfNeeded(startPosition: Double?) async {
        let expectedStart = startPosition ?? 0
        try? await Task.sleep(for: .milliseconds(700))
        guard case .playing = state else { return }
        guard currentTime <= expectedStart + 0.05 else { return }
        #if DEBUG
        print("[PlayerViewModel] startup recovery seek triggered expectedStart=\(String(format: "%.3f", expectedStart)) current=\(String(format: "%.3f", currentTime)) layer=\(displayLayerStatus())")
        #endif
        await engine.seek(to: expectedStart)
    }

    #if DEBUG
    private func startStartupDiagnostics(streamURL: URL, startPosition: Double?) {
        startupDiagnosticsTask?.cancel()
        startupDiagnosticsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            print("[PlayerDiagnostics] begin url=\(streamURL.absoluteString) start=\(startPosition.map { String(format: "%.3f", $0) } ?? "nil")")
            for tick in 0..<18 {
                guard !Task.isCancelled else { return }
                let audioSummary = self.audioTracks.map { "\($0.id):\($0.codec):\($0.language ?? "und")" }.joined(separator: ",")
                let subtitleSummary = self.subtitleTracks.map { "\($0.id):\($0.codec):\($0.language ?? "und")" }.joined(separator: ",")
                print("[PlayerDiagnostics] t=\(String(format: "%.1f", Double(tick) * 0.5))s state=\(String(describing: self.state)) loading=\(self.isLoading) current=\(String(format: "%.3f", self.currentTime)) duration=\(String(format: "%.3f", self.duration)) progress=\(String(format: "%.3f", self.progress)) format=\(self.videoFormat) audioTracks=[\(audioSummary)] subtitleTracks=[\(subtitleSummary)] layer=\(self.displayLayerStatus())")
                try? await Task.sleep(for: .milliseconds(500))
            }
            print("[PlayerDiagnostics] end")
        }
    }

    private func logMediaStreams(_ streams: [JellyfinMediaStream]?) {
        guard let streams, !streams.isEmpty else {
            print("[PlayerViewModel] MediaStreams: none")
            return
        }
        for stream in streams {
            let dimensions: String
            if let width = stream.width, let height = stream.height {
                dimensions = "\(width)x\(height)"
            } else {
                dimensions = "?x?"
            }
            print("[PlayerViewModel] MediaStream index=\(stream.index.map(String.init) ?? "nil") type=\(stream.type ?? "nil") codec=\(stream.codec ?? "nil") profile=\(stream.profile ?? "nil") dimensions=\(dimensions) bitrate=\(stream.bitRate.map(String.init) ?? "nil") range=\(stream.videoRange ?? "nil") rangeType=\(stream.videoRangeType ?? "nil") channels=\(stream.channels.map(String.init) ?? "nil") default=\(stream.isDefault ?? false) external=\(stream.isExternal ?? false) title=\(stream.displayTitle ?? "nil")")
        }
    }

    private func displayLayerStatus() -> String {
        // The engine no longer exposes its display layer; report the active backend
        // and decoders instead, which is what we actually want to diagnose now.
        return "backend=\(engine.playbackBackend) videoDecoder=\(engine.activeVideoDecoder ?? "nil") audioDecoder=\(engine.activeAudioDecoder ?? "nil")"
    }
    #endif

    // MARK: - Stop

    @MainActor
    func stop(reportToJellyfin: Bool = true) async {
        startupDiagnosticsTask?.cancel()
        startupDiagnosticsTask = nil
        stopProgressReporting()
        stopCountdown()
        removeLifecycleObservers()
        if reportToJellyfin, let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty {
            await client.reportStopped(
                itemId: itemId,
                playSessionId: playSessionId,
                positionSeconds: currentTime
            )
        }
        engine.stop()
    }

    private func removeLifecycleObservers() {
        for obs in lifecycleObservers {
            NotificationCenter.default.removeObserver(obs)
        }
        lifecycleObservers.removeAll()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        engine.togglePlayPause()
        guard let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty else { return }
        let isPaused = state == .playing
        let pos = currentTime
        let sess = playSessionId
        let item = itemId
        let event = isPaused ? "Pause" : "Unpause"
        Task {
            await client.reportProgress(itemId: item, playSessionId: sess, positionSeconds: pos, isPaused: isPaused, eventName: event)
        }
    }

    func seek(to seconds: Double) async {
        let clamped = max(0, min(seconds, duration))
        await engine.seek(to: clamped)
        guard let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty else { return }
        await client.reportProgress(itemId: itemId, playSessionId: playSessionId, positionSeconds: clamped, isPaused: false, eventName: "Seek")
    }

    func skip(by seconds: Double) async {
        await seek(to: currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        engine.setRate(rate)
    }

    func toggleGravity() {
        videoGravity = videoGravity == .resizeAspect ? .resizeAspectFill : .resizeAspect
        engine.videoGravity = videoGravity
    }

    func skipIntro() async {
        guard let intro = activeIntroSegment else { return }
        await seek(to: intro.endSeconds)
    }

    // MARK: - Track Selection

    func selectAudioTrack(_ track: TrackInfo) {
        engine.selectAudioTrack(index: track.id)
        selectedAudioTrackId = track.id
    }

    func selectSubtitleTrack(_ track: TrackInfo) {
        engine.selectSubtitleTrack(index: track.id)
        selectedSubtitleTrackId = track.id
    }

    func clearSubtitles() {
        engine.clearSubtitle()
        selectedSubtitleTrackId = nil
    }

    // MARK: - Next Episode

    func playNextEpisode() async {
        guard let next = nextEpisode, let id = next.id else { return }
        stopCountdown()
        showNextEpisodeCountdown = false
        await stop(reportToJellyfin: true)
        await load(
            itemId: id,
            title: next.seriesName ?? next.name ?? "",
            episodeLabel: next.episodeLabel
        )
    }

    // MARK: - Foreground Reload

    @MainActor
    func reloadAfterForeground() async {
        guard state == .paused, !itemId.isEmpty else { return }
        do {
            try await engine.reloadAtCurrentPosition()
        } catch {
            errorMessage = "Playback interrupted. Try restarting."
        }
    }

    // MARK: - Computed Helpers

    var videoFormatBadge: String? {
        switch videoFormat {
        case .dolbyVision: "Dolby Vision"
        case .hdr10Plus: "HDR10+"
        case .hdr10: "HDR10"
        case .hlg: "HLG"
        case .sdr: nil
        }
    }

    var isPlaying: Bool { state == .playing }
    var isBuffering: Bool { state == .loading || (isLoading && state == .idle) }

    var currentIntroSegment: JellyfinMediaSegment? {
        segments.first { $0.type?.lowercased() == "intro"
            && currentTime >= $0.startSeconds
            && currentTime < $0.endSeconds
        }
    }

    var currentOutroSegment: JellyfinMediaSegment? {
        segments.first { $0.type?.lowercased() == "outro"
            && currentTime >= $0.startSeconds
            && currentTime < $0.endSeconds
        }
    }

    // MARK: - Private: Publisher Bridge

    private func bindPublishers() {
        engine.$state
            .sink { [weak self] value in
                #if DEBUG
                print("[PlayerViewModel] state -> \(String(describing: value))")
                #endif
                self?.state = value
                if case .error(let message) = value {
                    self?.errorMessage = message
                    self?.isLoading = false
                }
            }
            .store(in: &cancellables)
        engine.clock.$currentTime
            .sink { [weak self] value in
                self?.currentTime = value
                self?.checkSegments()
                self?.checkNearEnd()
                #if DEBUG
                let second = Int(value.rounded(.down))
                if let self, second != self.lastLoggedPlaybackSecond, second >= 0, second <= 12 {
                    self.lastLoggedPlaybackSecond = second
                    print("[PlayerViewModel] time -> \(String(format: "%.3f", value)) layer=\(self.displayLayerStatus())")
                }
                #endif
            }
            .store(in: &cancellables)
        engine.$duration
            .sink { [weak self] value in
                self?.duration = value
                #if DEBUG
                if value > 0 {
                    print("[PlayerViewModel] duration -> \(String(format: "%.3f", value))")
                }
                #endif
            }
            .store(in: &cancellables)
        engine.clock.$progress
            .sink { [weak self] value in self?.progress = value }
            .store(in: &cancellables)
        engine.$videoFormat
            .sink { [weak self] value in
                self?.videoFormat = value
                #if DEBUG
                print("[PlayerViewModel] videoFormat -> \(value)")
                #endif
            }
            .store(in: &cancellables)
        engine.$playbackBackend
            .sink { [weak self] value in
                self?.playbackBackend = value
                #if DEBUG
                print("[PlayerViewModel] playbackBackend -> \(value)")
                #endif
            }
            .store(in: &cancellables)
        engine.$audioTracks
            .sink { [weak self] tracks in
                self?.audioTracks = tracks
                #if DEBUG
                if !tracks.isEmpty {
                    let summary = tracks.map { "\($0.id):\($0.codec):\($0.language ?? "und") default=\($0.isDefault)" }.joined(separator: ", ")
                    print("[PlayerViewModel] audioTracks -> [\(summary)]")
                }
                #endif
                self?.autoSelectAudioTrack()
            }
            .store(in: &cancellables)
        engine.$subtitleTracks
            .sink { [weak self] value in
                self?.subtitleTracks = value
                #if DEBUG
                if !value.isEmpty {
                    let summary = value.map { "\($0.id):\($0.codec):\($0.language ?? "und")" }.joined(separator: ", ")
                    print("[PlayerViewModel] subtitleTracks -> [\(summary)]")
                }
                #endif
            }
            .store(in: &cancellables)
        engine.$subtitleCues
            .sink { [weak self] value in self?.subtitleCues = value }
            .store(in: &cancellables)
        engine.$isSubtitleActive
            .sink { [weak self] value in self?.isSubtitleActive = value }
            .store(in: &cancellables)
        engine.$isLoadingSubtitles
            .sink { [weak self] value in self?.isLoadingSubtitles = value }
            .store(in: &cancellables)
    }

    // MARK: - Private: Auto Track Selection

    private func autoSelectAudioTrack() {
        guard selectedAudioTrackId == nil, !audioTracks.isEmpty else { return }
        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        let match = audioTracks.first { $0.language?.hasPrefix(preferred) == true && $0.isDefault }
            ?? audioTracks.first { $0.language?.hasPrefix(preferred) == true }
            ?? audioTracks.first { $0.isDefault }
            ?? audioTracks.first
        guard let match else { return }
        engine.selectAudioTrack(index: match.id)
        selectedAudioTrackId = match.id
    }

    // MARK: - Private: Segment Checking

    private func checkSegments() {
        activeIntroSegment = currentIntroSegment
        activeOutroSegment = currentOutroSegment
    }

    private func checkNearEnd() {
        guard duration > 60,
              let next = nextEpisode,
              next.id != nil,
              !showNextEpisodeCountdown
        else { return }
        let outroStart = segments.first(where: { $0.type?.lowercased() == "outro" })?.startSeconds
        let threshold = outroStart ?? max(duration - 30, duration * 0.9)
        if currentTime >= threshold {
            showNextEpisodeCountdown = true
            startCountdown()
        }
    }

    // MARK: - Private: Progress Reporting

    private func startProgressReporting() {
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled else { return }
                guard self.state == .playing, let client = self.jellyfinClient else { continue }
                await client.reportProgress(
                    itemId: self.itemId,
                    playSessionId: self.playSessionId,
                    positionSeconds: self.currentTime,
                    isPaused: false
                )
            }
        }
    }

    private func stopProgressReporting() {
        progressTask?.cancel()
        progressTask = nil
    }

    // MARK: - Private: Next Episode Countdown

    private func startCountdown() {
        nextEpisodeCountdown = 10
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if self.nextEpisodeCountdown <= 1 {
                    await self.playNextEpisode()
                    return
                }
                self.nextEpisodeCountdown -= 1
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    // MARK: - Private: Lifecycle

    private func observeLifecycle() {
        #if canImport(UIKit)
        let fg = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.reloadAfterForeground() }
        }
        lifecycleObservers.append(fg)
        #else
        let fg = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.reloadAfterForeground() }
        }
        lifecycleObservers.append(fg)
        #endif
    }
}
