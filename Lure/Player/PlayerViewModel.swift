import SwiftUI
import Combine
import AVFoundation
import AetherEngine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private typealias StreamCandidate = (
    url: URL,
    isDirect: Bool,
    label: String,
    playMethod: String,
    playSessionId: String,
    mediaSourceId: String
)

@MainActor
@Observable
final class PlayerViewModel {
    #if DEBUG
    nonisolated(unsafe) private static var didInstallEngineLogHandler = false
    #endif

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
    /// Mirrors `engine.$playbackPhase` (ISSUE-012): finer-grained than `state`, distinguishing
    /// mid-playback rebuffers/stalls from the startup-only `isLoading` flag so the transport
    /// UI can surface a "Reconnecting…" indicator instead of a frozen frame.
    var playbackPhase: PlaybackPhase = .idle

    /// True when the engine is software-decoding (e.g. MKV / dav1d), which has no
    /// `AVPlayer` for AVKit to drive — those sessions need our custom transport.
    /// The native backend renders through AVKit's own `AVPlayer` + controls.
    var isSoftwareBackend: Bool { playbackBackend == .software }

    /// Mirrors AVKit's transport-chrome visibility on the native path. AVKit has no
    /// public "controls visible" signal, so `PlayerHostController` tracks the same
    /// tap-to-toggle + auto-hide behavior and updates this; our custom overlay
    /// controls fade in/out with it so they hide together with AVKit's chrome.
    var controlsVisible: Bool = true

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
    /// Set when `PlaybackState.ended` is reached with no known next episode (ISSUE-006):
    /// a dismissable end-of-playback signal for the view, since the custom transport's
    /// play button is otherwise dead at end of media with no explanation. Reset at the
    /// top of `load()`.
    var playbackEnded: Bool = false

    // Current track selections (for UI state)
    var selectedAudioTrackId: Int? = nil
    var selectedSubtitleTrackId: Int? = nil
    var playbackRate: Float = 1.0
    var videoSize: CGSize?

    // MARK: - Engine

    let engine: AetherEngine

    // MARK: - Jellyfin session state (private)
    private let jellyfinService: JellyfinService
    private(set) var jellyfinClient: JellyfinAPIClient?
    private var itemId: String = ""
    private var mediaSourceId: String = ""
    private var playSessionId: String = ""
    /// Chosen candidate's report method for `reportPlaybackStart` (ISSUE-013): "DirectPlay"
    /// for an untouched-file static candidate, "DirectStream" for a non-static direct
    /// candidate, "Transcode" otherwise. Distinct from "DirectStream", which used to be
    /// reported for both direct cases.
    private var playMethod: String = "DirectStream"

    /// True while the `load()` candidate loop is in flight. AetherEngine sets
    /// `state = .error(...)` *before* throwing on a failed candidate load; without this
    /// guard, a direct-play candidate that fails followed by a transcode candidate that
    /// succeeds would leave the stale `errorMessage` from the failed candidate rendering
    /// over successfully-playing video (ISSUE-002).
    private var suppressEngineErrors = false

    // MARK: - Combine
    private var cancellables: Set<AnyCancellable> = []
    private var progressTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var nextEpisodeCountdownSuppressed = false
    private var startupDiagnosticsTask: Task<Void, Never>?
    private let lifecycleObserverBag = LifecycleObserverBag()
    private let directCandidateLoadTimeoutSeconds: Double = 24
    private let transcodeCandidateLoadTimeoutSeconds: Double = 75
    private let transcodeCandidateStartupTimeoutSeconds: Double = 35
    #if DEBUG
    private var lastLoggedPlaybackSecond = -1
    #endif

    // MARK: - Init

    init(jellyfinService: JellyfinService) throws {
        #if DEBUG
        Self.installEngineLogHandlerIfNeeded()
        #endif
        engine = try AetherEngine()
        #if os(iOS)
        // AetherEngine 4.12.1 sets .longFormAudio which blocks PiP (engine #116, fixed in 5.0.1); override until we bump to 5.x
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, policy: .default)
        #endif
        self.jellyfinService = jellyfinService
        bindPublishers()
        observeLifecycle()
    }

    // MARK: - Load

    @MainActor
    func load(_ media: PlayableMedia) async {
        await load(
            itemId: media.itemId ?? "",
            title: media.title,
            episodeLabel: media.episodeLabel,
            serviceUrl: media.serviceUrl,
            tmdbId: media.tmdbId,
            releaseYear: media.releaseYear,
            mediaType: media.mediaType
        )
    }

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
        playbackEnded = false
        videoSize = nil
        selectedAudioTrackId = nil
        selectedSubtitleTrackId = nil
        nextEpisodeCountdownSuppressed = false
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
            #if DEBUG
            print("[PlayerViewModel] resume: itemId=\(self.itemId) resumePositionSeconds=\(String(format: "%.1f", resumePosition)) playbackPositionTicks=\(item.userData?.playbackPositionTicks.map(String.init) ?? "nil") played=\(item.userData?.played.map(String.init) ?? "nil")")
            #endif

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
                if let url = client.transcodingURL(path: transcodingUrl) {
                    print("[PlayerViewModel] TranscodingURL: \(Self.diagnosticURL(url))")
                } else {
                    print("[PlayerViewModel] TranscodingURL: <unresolved>")
                }
            }
            logMediaStreams(mediaSource.mediaStreams)
            #endif

            // Build stream URL
            var streamCandidates: [StreamCandidate] = []
            var directFallbackCandidates: [StreamCandidate] = []
            if mediaSource.supportsDirectPlay == true {
                if let url = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: true,
                    container: mediaSource.container
                ) {
                    streamCandidates.append((url, true, "static direct play stream.\(mediaSource.container ?? "mp4")", "DirectPlay", playSessionId, self.mediaSourceId))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate static direct play: \(Self.diagnosticURL(url))")
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
                    directFallbackCandidates.append((fallbackURL, true, "static direct play fallback stream", "DirectPlay", playSessionId, self.mediaSourceId))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate static direct play fallback: \(Self.diagnosticURL(fallbackURL))")
                    #endif
                }
            }
            if mediaSource.supportsDirectPlay != true, mediaSource.supportsDirectStream == true {
                if let url = client.streamURL(
                    itemId: self.itemId,
                    mediaSourceId: self.mediaSourceId,
                    playSessionId: playSessionId,
                    isStatic: false,
                    container: mediaSource.container
                ) {
                    streamCandidates.append((url, true, "non-static direct stream stream.\(mediaSource.container ?? "mp4")", "DirectStream", playSessionId, self.mediaSourceId))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate non-static direct stream: \(Self.diagnosticURL(url))")
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
                    directFallbackCandidates.append((fallbackURL, true, "non-static direct stream fallback stream", "DirectStream", playSessionId, self.mediaSourceId))
                    #if DEBUG
                    print("[PlayerViewModel] Candidate non-static direct stream fallback: \(Self.diagnosticURL(fallbackURL))")
                    #endif
                }
            }
            if let transPath = mediaSource.transcodingUrl,
               let url = client.transcodingURL(path: transPath) {
                streamCandidates.append((url, false, "transcode", "Transcode", playSessionId, self.mediaSourceId))
                #if DEBUG
                print("[PlayerViewModel] Candidate transcode: \(Self.diagnosticURL(url))")
                #endif
            }
            streamCandidates.append(contentsOf: directFallbackCandidates)
            guard !streamCandidates.isEmpty else {
                throw JellyfinError.noPlayableSource
            }

            // Load into engine. The engine owns its display surface and attaches the
            // appropriate layer to the bound AetherPlayerView; HDR presentation is now
            // handled internally via display-criteria matching (LoadOptions defaults).
            let startPosition = resumePosition > 0 ? resumePosition : nil

            // Jellyfin's own MediaInfo track counts, used below to validate the tight
            // probe budget hasn't silently dropped late-resolving tracks (ISSUE-005).
            let embeddedAudioCount = mediaSource.mediaStreams?.filter { $0.type == "Audio" }.count ?? 0
            let embeddedSubtitleCount = mediaSource.mediaStreams?.filter { $0.type == "Subtitle" && $0.isExternal != true }.count ?? 0

            // Jellyfin external (sidecar) subtitle streams — decoded via `deliveryUrl` in
            // JellyfinModels.swift but otherwise unused until now. Map them to AetherEngine
            // 4.12.1's first-class external-subtitle support (#88) so sidecar srt/ass/vtt
            // tracks actually show up (ISSUE-007).
            let externalSubtitleTracks: [ExternalSubtitleTrack] = (mediaSource.mediaStreams ?? []).compactMap { stream in
                guard stream.type == "Subtitle",
                      stream.isExternal == true,
                      let deliveryUrl = stream.deliveryUrl,
                      let url = client.serverRelativeURL(path: deliveryUrl)
                else { return nil }
                return ExternalSubtitleTrack(
                    url: url,
                    name: stream.displayTitle,
                    language: stream.language,
                    isDefault: stream.isDefault ?? false
                )
            }

            // Mirror of `UIScreen.main.currentEDRHeadroom > 1` so an HDR-capable display
            // accepts the HDR10-to-DV upgrade path upfront instead of the conservative SDR
            // branch (ISSUE-015; see LoadOptions.panelIsInHDRMode doc).
            #if os(iOS)
            let panelIsInHDRMode = UIScreen.main.currentEDRHeadroom > 1
            #else
            let panelIsInHDRMode = false
            #endif
            let preferredAudioLanguages = Self.preferredAudioLanguages()

            var lastLoadError: Error?
            // Suppress the engine.$state sink's error writes while candidates are being
            // tried in turn: AetherEngine sets `state = .error(...)` before throwing on a
            // failed load, and without suppression a failed direct-play candidate would
            // flash the error overlay even when a later transcode candidate succeeds.
            suppressEngineErrors = true
            defer { suppressEngineErrors = false }
            for candidate in streamCandidates {
                #if DEBUG
                print("[PlayerViewModel] Trying \(candidate.label): \(Self.diagnosticURL(candidate.url))")
                Task { await client.playbackURLDiagnostics(candidate.url) }
                #endif
                startStartupDiagnostics(streamURL: candidate.url, startPosition: startPosition)
                do {
                    // NOTE: LoadOptions(prepareNativeSubtitles: true) would surface text
                    // subs in AVKit's native menu; kept host-rendered via our own tracks
                    // menu for now (the mov_text approach this used to rely on was replaced
                    // by native WebVTT renditions in AetherEngine 4.9.0, but wiring that up
                    // is a separate change).
                    //
                    // Track layout is already known from Jellyfin's MediaInfo, so a bounded
                    // remote probe budget is safe (AetherEngine #68): it avoids 4K remux
                    // startup stalls where sparse PGS/bitmap subtitle tracks force the full
                    // 50MB/60s engine default before the first frame. Audio is still validated
                    // below because a missing audio stream is playback-breaking; sparse
                    // subtitles are allowed to resolve late or be absent rather than blocking
                    // startup.
                    let probeBudget = Self.probeBudget(for: candidate, mediaSource: mediaSource)
                    let loadOptions = LoadOptions(
                        suppressDisplayCriteria: false,
                        matchContentEnabled: Self.matchContentEnabled,
                        panelIsInHDRMode: panelIsInHDRMode,
                        audioBridgeMode: .surroundCompat,
                        probesize: probeBudget.probesize,
                        maxAnalyzeDuration: probeBudget.maxAnalyzeDuration,
                        preferredAudioLanguages: preferredAudioLanguages,
                        externalSubtitles: externalSubtitleTracks
                    )
                    let probe = try await loadEngineCandidate(
                        candidate.label,
                        url: candidate.url,
                        startPosition: startPosition,
                        timeoutSeconds: candidate.isDirect ? directCandidateLoadTimeoutSeconds : transcodeCandidateLoadTimeoutSeconds,
                        options: loadOptions
                    )
                    if let probe {
                        videoSize = Self.videoSize(from: probe)
                    }
                    if candidate.isDirect, let probe {
                        let resolvedAudioCount = probe.audioTracks.filter { !$0.isExternal }.count
                        let resolvedSubtitleCount = probe.subtitleTracks.filter { !$0.isExternal }.count
                        if resolvedAudioCount < embeddedAudioCount {
                            #if DEBUG
                            print("[PlayerViewModel] Bounded probe under-resolved audio tracks (audio \(resolvedAudioCount)/\(embeddedAudioCount), subtitle \(resolvedSubtitleCount)/\(embeddedSubtitleCount)) — retrying \(candidate.label) with unbounded probe budget")
                            #endif
                            let retryProbe = try await loadEngineCandidate(
                                "\(candidate.label) full-probe retry",
                                url: candidate.url,
                                startPosition: startPosition,
                                timeoutSeconds: directCandidateLoadTimeoutSeconds,
                                options: LoadOptions(
                                    panelIsInHDRMode: panelIsInHDRMode,
                                    preferredAudioLanguages: preferredAudioLanguages,
                                    externalSubtitles: externalSubtitleTracks
                                )
                            )
                            if let retryProbe {
                                videoSize = Self.videoSize(from: retryProbe)
                            }
                        } else if resolvedSubtitleCount < embeddedSubtitleCount {
                            #if DEBUG
                            print("[PlayerViewModel] Bounded probe under-resolved sparse subtitle tracks (subtitle \(resolvedSubtitleCount)/\(embeddedSubtitleCount)); accepting to avoid delaying first frame")
                            #endif
                        }
                    }
                    if !candidate.isDirect {
                        let startupSucceeded = await waitForStartupEvidence(
                            candidate.label,
                            timeoutSeconds: transcodeCandidateStartupTimeoutSeconds
                        )
                        guard startupSucceeded else {
                            throw PlayerStartupTimeoutError(label: candidate.label, seconds: transcodeCandidateStartupTimeoutSeconds)
                        }
                    }
                    playMethod = candidate.playMethod
                    self.playSessionId = candidate.playSessionId
                    self.mediaSourceId = candidate.mediaSourceId
                    #if DEBUG
                    print("[PlayerViewModel] Loaded and started via \(candidate.label)")
                    #endif
                    lastLoadError = nil
                    // Clear any stale error from an earlier failed candidate now that this
                    // one succeeded (ISSUE-002).
                    errorMessage = nil
                    break
                } catch {
                    lastLoadError = error
                    engine.stop()
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

            await recoverStartupIfNeeded(startPosition: startPosition)
            if case .error(let message) = state {
                throw PlayerStartupFailedError(message: message)
            }
            isLoading = false

            // Report start to Jellyfin
            await client.reportPlaybackStart(
                itemId: self.itemId,
                playSessionId: self.playSessionId,
                mediaSourceId: self.mediaSourceId,
                positionSeconds: resumePosition,
                playMethod: playMethod
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

    /// The native HLS path can drop the engine's load-time seek when it's issued
    /// before the AVPlayer item is ready / `duration` is known — the seek clamps to
    /// 0 and playback starts from the beginning instead of the resume point. So for
    /// a resume we wait until playback is genuinely established (duration known +
    /// playing), then seek to the target ourselves, but only if we're not already
    /// there (a no-op when the engine's own seek lands correctly).
    private func recoverStartupIfNeeded(startPosition: Double?) async {
        let target = startPosition ?? 0

        // Wait for playback to establish: duration is what the seek clamps against,
        // so seeking before it's known is exactly the bug we're recovering from.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if case .playing = state, target == 0 || duration > 0 { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard case .playing = state else { return }

        if target > 0 {
            guard duration > 0, currentTime < target - 5 else { return }
            #if DEBUG
            print("[PlayerViewModel] resume seek -> \(String(format: "%.1f", target)) (current=\(String(format: "%.1f", currentTime)) duration=\(String(format: "%.1f", duration)))")
            #endif
            await engine.seek(to: max(0, min(target, duration - 1)))
        } else {
            guard currentTime <= 0.05 else { return }
            await engine.seek(to: 0)
        }
    }

    #if DEBUG
    private static func installEngineLogHandlerIfNeeded() {
        guard !didInstallEngineLogHandler else { return }
        didInstallEngineLogHandler = true
        EngineLog.handler = { line in
            print(Self.redactedDiagnosticLine(line))
        }
    }

    private func startStartupDiagnostics(streamURL: URL, startPosition: Double?) {
        startupDiagnosticsTask?.cancel()
        startupDiagnosticsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            print("[PlayerDiagnostics] begin url=\(Self.diagnosticURL(streamURL)) start=\(startPosition.map { String(format: "%.3f", $0) } ?? "nil")")
            for tick in 0..<18 {
                guard !Task.isCancelled else { return }
                let audioSummary = self.audioTracks.map { "\($0.id):\($0.codec):\($0.language ?? "und")" }.joined(separator: ",")
                let subtitleSummary = self.subtitleTracks.map { "\($0.id):\($0.codec):\($0.language ?? "und")" }.joined(separator: ",")
                print("[PlayerDiagnostics] t=\(String(format: "%.1f", Double(tick) * 0.5))s state=\(String(describing: self.state)) loading=\(self.isLoading) current=\(String(format: "%.3f", self.currentTime)) duration=\(String(format: "%.3f", self.duration)) progress=\(String(format: "%.3f", self.progress)) format=\(self.videoFormat) audioTracks=[\(audioSummary)] subtitleTracks=[\(subtitleSummary)] layer=\(self.displayLayerStatus()) av=\(self.avPlayerDiagnosticStatus())")
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

    private func avPlayerDiagnosticStatus() -> String {
        guard let player = engine.currentAVPlayer else { return "player=nil" }
        let item = player.currentItem
        let itemStatus = item.map { Self.avPlayerItemStatusDescription($0.status) } ?? "nil"
        let timeControl = Self.timeControlStatusDescription(player.timeControlStatus)
        let waiting = player.reasonForWaitingToPlay?.rawValue ?? "nil"
        let error = item?.error.map { Self.redactedDiagnosticLine($0.localizedDescription) } ?? "nil"
        let events = item?.errorLog()?.events.suffix(2).map { event in
            let comment = event.errorComment ?? "nil"
            let uri = event.uri ?? "nil"
            return "\(event.errorStatusCode):\(event.errorDomain):\(comment):\(uri)"
        }.joined(separator: " | ") ?? "none"
        return "item=\(itemStatus) tcs=\(timeControl) waiting=\(waiting) itemError=\(error) errorLog=\(Self.redactedDiagnosticLine(events))"
    }

    private static func avPlayerItemStatusDescription(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown: "unknown"
        case .readyToPlay: "ready"
        case .failed: "failed"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    private static func timeControlStatusDescription(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused: "paused"
        case .waitingToPlayAtSpecifiedRate: "waiting"
        case .playing: "playing"
        @unknown default: "unknown(\(status.rawValue))"
        }
    }

    nonisolated private static func redactedDiagnosticLine(_ line: String) -> String {
        var redacted = line
        for key in ["api_key", "ApiKey", "apikey", "PlaySessionId"] {
            redacted = redacted.replacingOccurrences(
                of: "\(key)=[^&\\s]+",
                with: "\(key)=<redacted>",
                options: .regularExpression
            )
        }
        return redacted
    }
    #endif

    // MARK: - Stop

    @MainActor
    func stop(reportToJellyfin: Bool = true) async {
        startupDiagnosticsTask?.cancel()
        startupDiagnosticsTask = nil
        stopProgressReporting()
        stopCountdown()
        // Lifecycle observers are intentionally NOT removed here: `playNextEpisode()`
        // calls stop() then load() on the same VM, and reloadAfterForeground()'s own
        // `guard state == .paused` already makes the observer a no-op while stopped.
        // Removing them here left every episode after the first without foreground
        // recovery. They live for the VM's lifetime via `lifecycleObserverBag`.
        if reportToJellyfin, let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty {
            await client.reportStopped(
                itemId: itemId,
                playSessionId: playSessionId,
                positionSeconds: currentTime
            )
        }
        engine.stop()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        // Pause/Unpause reporting happens in the engine.$state sink (ISSUE-003): AetherEngine
        // is @MainActor and its Combine sink delivers synchronously, so reading `state` here
        // (after the toggle) would already reflect the post-toggle value, inverting the
        // reported event. Reporting from the sink's previous/new state comparison instead
        // also captures AVKit-native-control toggles, which never call this method.
        engine.togglePlayPause()
    }

    func seek(to seconds: Double) async {
        let clamped = max(0, min(seconds, duration))
        // Workaround AetherEngine #122 (paused seek re-engages playback), fixed upstream in
        // 5.0.3: capture the paused state before seeking and re-pause after if needed (ISSUE-011).
        let wasPaused = state == .paused
        await engine.seek(to: clamped)
        if wasPaused {
            engine.pause()
        }
        guard let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty else { return }
        await client.reportProgress(itemId: itemId, playSessionId: playSessionId, positionSeconds: clamped, isPaused: wasPaused, eventName: "Seek")
    }

    func skip(by seconds: Double) async {
        await seek(to: currentTime + seconds)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
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

    func cancelNextEpisodeCountdown() {
        stopCountdown()
        showNextEpisodeCountdown = false
        nextEpisodeCountdownSuppressed = true
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
    /// Derived from `playbackPhase` (ISSUE-012) instead of just `state`, so mid-playback
    /// rebuffers/stalls/seeks surface the same buffering signal as startup loading does.
    var isBuffering: Bool {
        switch playbackPhase {
        case .loading, .rebuffering, .seeking, .stalled: true
        default: isLoading
        }
    }

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
                guard let self else { return }
                #if DEBUG
                print("[PlayerViewModel] state -> \(String(describing: value))")
                #endif
                let previous = self.state
                self.state = value
                if case .error(let message) = value, self.suppressEngineErrors != true {
                    self.errorMessage = message
                    self.isLoading = false
                }

                // ISSUE-003: report Pause/Unpause from the state transition itself (instead
                // of from togglePlayPause(), which read `state` after a synchronous engine
                // toggle and reported the inverted event). This also captures AVKit-native-
                // control toggles, which never call togglePlayPause().
                if previous == .playing, value == .paused {
                    self.reportPauseTransition(isPaused: true, eventName: "Pause")
                } else if previous == .paused, value == .playing {
                    self.reportPauseTransition(isPaused: false, eventName: "Unpause")
                }

                // ISSUE-006: PlaybackState.ended is terminal like .idle but reached by
                // natural end-of-media rather than stop(). Report stopped/played once, then
                // auto-advance or surface a dismissable end-of-playback signal.
                if previous != .ended, value == .ended {
                    self.handlePlaybackEnded()
                }
            }
            .store(in: &cancellables)
        engine.$playbackPhase
            .sink { [weak self] value in
                self?.playbackPhase = value
                #if DEBUG
                print("[PlayerViewModel] playbackPhase -> \(value)")
                #endif
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
            }
            .store(in: &cancellables)
        engine.$activeAudioTrackIndex
            .sink { [weak self] value in
                self?.selectedAudioTrackId = value
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

    private static func videoSize(from probe: SourceProbe) -> CGSize? {
        guard probe.videoWidth > 0, probe.videoHeight > 0 else { return nil }
        return CGSize(width: CGFloat(probe.videoWidth), height: CGFloat(probe.videoHeight))
    }

    // MARK: - Private: Pause/Unpause + End-of-Playback Reporting

    /// Fires the Jellyfin Pause/Unpause progress event from an observed `engine.$state`
    /// transition (ISSUE-003). See the sink in `bindPublishers()`.
    private func reportPauseTransition(isPaused: Bool, eventName: String) {
        guard let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty else { return }
        let pos = currentTime
        let sess = playSessionId
        let item = itemId
        Task {
            await client.reportProgress(itemId: item, playSessionId: sess, positionSeconds: pos, isPaused: isPaused, eventName: eventName)
        }
    }

    /// Handles the transition into `PlaybackState.ended` (ISSUE-006): reports the stopped
    /// position and marks the item played, then either auto-advances to the known next
    /// episode or surfaces `playbackEnded` for the view to dismiss on.
    private func handlePlaybackEnded() {
        guard let client = jellyfinClient, !itemId.isEmpty, !playSessionId.isEmpty else {
            if nextEpisode == nil { playbackEnded = true }
            return
        }
        let item = itemId
        let sess = playSessionId
        let pos = duration > 0 ? duration : currentTime
        let hasNext = nextEpisode != nil
        Task { [weak self] in
            await client.reportStopped(itemId: item, playSessionId: sess, positionSeconds: pos)
            try? await client.markPlayed(itemId: item)
            guard let self else { return }
            if hasNext {
                await self.playNextEpisode()
            } else {
                self.playbackEnded = true
            }
        }
    }

    // MARK: - Private: Engine Load Helpers

    private func loadEngineCandidate(
        _ label: String,
        url: URL,
        startPosition: Double?,
        timeoutSeconds: Double,
        options: LoadOptions
    ) async throws -> SourceProbe? {
        try await withThrowingTaskGroup(of: SourceProbe?.self) { group in
            group.addTask { @MainActor [engine] in
                try await engine.load(url: url, startPosition: startPosition, options: options)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw PlayerLoadTimeoutError(label: label, seconds: timeoutSeconds)
            }

            do {
                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw CancellationError()
                }
                group.cancelAll()
                return result
            } catch let error as PlayerLoadTimeoutError {
                group.cancelAll()
                engine.stop()
                throw error
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private func waitForStartupEvidence(_ label: String, timeoutSeconds: Double) async -> Bool {
        let startedAt = Date()
        let baselineTime = currentTime
        while Date().timeIntervalSince(startedAt) < timeoutSeconds {
            if Task.isCancelled { return false }
            if case .error = state { return false }
            if currentTime > baselineTime + 0.35 {
                return true
            }
            #if DEBUG
            if Date().timeIntervalSince(startedAt) > 4,
               Int(Date().timeIntervalSince(startedAt) * 10) % 20 == 0 {
                print("[PlayerViewModel] Waiting for startup evidence label=\(label) state=\(String(describing: state)) phase=\(playbackPhase) current=\(String(format: "%.3f", currentTime)) duration=\(String(format: "%.3f", duration))")
            }
            #endif
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private static func preferredAudioLanguages() -> [String] {
        var languages: [String] = []
        if let identifier = Locale.current.language.languageCode?.identifier, !identifier.isEmpty {
            languages.append(identifier)
        }
        if !languages.contains("en") {
            languages.append("en")
        }
        return languages
    }

    private static var matchContentEnabled: Bool {
        #if os(tvOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first
        else { return true }
        return window.avDisplayManager.isDisplayCriteriaMatchingEnabled
        #else
        return true
        #endif
    }

    private static func probeBudget(
        for candidate: StreamCandidate,
        mediaSource: JellyfinMediaSource
    ) -> (probesize: Int64?, maxAnalyzeDuration: Int64?) {
        guard candidate.isDirect else { return (nil, nil) }
        let path = mediaSource.path?.lowercased() ?? ""
        let isExternalURL = path.hasPrefix("http://") || path.hasPrefix("https://")
        let isSizedServerFile = (mediaSource.size ?? 0) > 0 && !isExternalURL
        guard isSizedServerFile else { return (nil, nil) }
        return (16 * 1024 * 1024, 10 * 1_000_000)
    }

    private static func diagnosticURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else { return url.absoluteString }

        components.queryItems = queryItems.map { item in
            switch item.name.lowercased() {
            case "api_key", "apikey", "playsessionid":
                URLQueryItem(name: item.name, value: "<redacted>")
            default:
                item
            }
        }
        return components.url?.absoluteString ?? url.absoluteString
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
              !showNextEpisodeCountdown,
              !nextEpisodeCountdownSuppressed
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
        lifecycleObserverBag.add(fg)
        #else
        let fg = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.reloadAfterForeground() }
        }
        lifecycleObserverBag.add(fg)
        #endif
    }
}

/// Holds NotificationCenter observer tokens for the VM's lifetime and removes them on
/// deallocation, mirroring AetherEngine's own `LifecycleObserverBag` pattern. Using a
/// separate reference type (rather than removing observers in `stop()`) lets the same
/// VM instance be reused across `stop()` + `load()` cycles (e.g. `playNextEpisode()`)
/// without losing foreground-recovery.
private final class LifecycleObserverBag: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

private struct PlayerLoadTimeoutError: LocalizedError {
    let label: String
    let seconds: Double

    var errorDescription: String? {
        "Timed out loading \(label) after \(Int(seconds)) seconds"
    }
}

private struct PlayerStartupTimeoutError: LocalizedError {
    let label: String
    let seconds: Double

    var errorDescription: String? {
        "Timed out starting \(label) after \(Int(seconds)) seconds"
    }
}

private struct PlayerStartupFailedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
