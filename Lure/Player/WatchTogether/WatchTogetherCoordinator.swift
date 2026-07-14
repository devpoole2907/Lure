import AetherEngine
import Combine
import Foundation
import GroupActivities
import Observation

/// Drives SharePlay "Watch Together" as a pure message transport. Deliberately does
/// NOT use `AVPlayerPlaybackCoordinator`: `AetherEngine`'s native backend already owns
/// and actively drives its `AVPlayer` (`engine.currentAVPlayer`), and handing a second
/// controller the same player risks the two fighting over rate/seek. Instead this
/// coordinator carries small play/pause/seek/rate events over `GroupSessionMessenger`
/// and always applies them through `PlayerViewModel`'s existing control methods --
/// the same uniform path AetherEngine already uses across all three backends.
///
/// Same shape as `PlayerCoordinator`: inject via `.environment(watchTogetherCoordinator)`
/// and drive an app-launch `.task { await watchTogetherCoordinator.listenForIncomingSessions() }`
/// near the root of the logged-in navigation tree.
@MainActor
@Observable
final class WatchTogetherCoordinator {
    /// Length of the window, starting the instant a remote command is applied, during
    /// which a resulting local-signal callback is treated as an echo of that command
    /// rather than a genuine new local change to re-broadcast. Owned entirely here --
    /// `PlayerViewModel` has no notion of "this change came from SharePlay".
    private static let echoSuppressionWindow: TimeInterval = 1.0
    private static let heartbeatInterval: Duration = .seconds(5)
    /// Drift tolerances: play/pause/seek messages correct any position gap beyond a
    /// tight threshold (the sender just observed a real seek), heartbeats are advisory
    /// reconciliation and use a looser threshold so ordinary network jitter and each
    /// side's own clock ticking don't cause a fight.
    private static let commandDriftTolerance: Double = 1.0
    private static let heartbeatDriftTolerance: Double = 3.0

    private let playerCoordinator: PlayerCoordinator

    private var session: GroupSession<WatchTogetherActivity>?
    private var messenger: GroupSessionMessenger?
    private var messageTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var participantsWatchTask: Task<Void, Never>?
    private var echoSuppressUntil: Date?

    /// A play/pause/heartbeat command that arrived while it couldn't be applied yet --
    /// either no `activeViewModel` is registered at all (this device joined before its
    /// `PlayerView` finished presenting, ISSUE watch-together #4), or the VM isn't in
    /// `.playing`/`.paused` (mid-`load()`; `AetherEngine.togglePlayPause()` no-ops
    /// outside `.playing/.paused/.loading`, and even within `.loading` position/duration
    /// aren't meaningful yet, ISSUE watch-together #1). Replayed once the VM becomes
    /// ready: `registerActiveViewModel(_:)` runs with a session already active, or
    /// `handleLocalSignal` sees the VM's own `.play` signal fire as `load()` lands
    /// (state passes `.loading -> .paused -> .playing` at the tail of every normal load).
    private var pendingRemoteState: (position: Double, isPlaying: Bool)?

    /// The `PlayerViewModel` currently on screen, registered by `PlayerView.onAppear`
    /// and cleared on `onDisappear` -- regardless of whether a session is active yet.
    /// `startSession(media:)` is called from that same screen, and the `GroupSession`
    /// it creates only arrives back asynchronously via `listenForIncomingSessions()`;
    /// by then `PlayerCoordinator.activePlayer` may already be nil (the macOS path
    /// clears it immediately after opening the player window), so this is the only
    /// reliable way to find "the view model for the session that was just started."
    private weak var activeViewModel: PlayerViewModel?

    /// True once a session has been joined; drives the "Watch Together" button's
    /// active/inactive appearance.
    var isSessionActive: Bool { session != nil }

    /// Set when `startSession(media:)`'s `activate()` throws or the system declines to
    /// activate (e.g. no FaceTime call in progress). Unlike the `#if DEBUG` console log
    /// alongside it, this needs a real user-facing surface so a release build doesn't
    /// silently swallow a failed SharePlay launch. Mirrors `PlayerCoordinator.
    /// presentationError`: a view with access to `InAppNotificationCenter` shows a
    /// banner on change, then resets this to nil.
    var sessionError: String?

    init(playerCoordinator: PlayerCoordinator) {
        self.playerCoordinator = playerCoordinator
    }

    // MARK: - Starting / joining

    /// Builds a `WatchTogetherActivity` for `media` and activates it, which triggers
    /// Apple's system SharePlay UI during an active FaceTime call (or prompts to start
    /// one). The resulting `GroupSession` -- for this device too -- only arrives via
    /// `listenForIncomingSessions()`; SharePlay always round-trips through
    /// `ActivityType.sessions()`, even for the device that called `activate()`.
    func startSession(media: PlayableMedia) {
        // Without this, tapping the button again mid-session (e.g. a double-tap) would
        // call `activate()` a second time and race a second `GroupSession` against the
        // one already wired up in `attach(session:vm:)`.
        guard session == nil else { return }
        Task {
            let activity = WatchTogetherActivity(media: media)
            do {
                let activated = try await activity.activate()
                if !activated {
                    sessionError = "SharePlay couldn't start. Make sure you're on a FaceTime call."
                }
            } catch {
                #if DEBUG
                print("[WatchTogetherCoordinator] activate() failed: \(error)")
                #endif
                sessionError = "SharePlay couldn't start. Make sure you're on a FaceTime call."
            }
        }
    }

    /// Awaits incoming (and this device's own outgoing) SharePlay sessions for the
    /// app's lifetime. Wire this from a `.task` scoped to the logged-in session so
    /// SwiftUI cancels it automatically on logout.
    func listenForIncomingSessions() async {
        for await session in WatchTogetherActivity.sessions() {
            if !session.isLocallyInitiated {
                // A remote participant started this session; open the same title here.
                playerCoordinator.present(session.activity.media)
            }
            attach(session: session, vm: activeViewModel)
        }
    }

    // MARK: - Attaching a view model

    /// Joins `session`, wires up the messenger, and (if a view model is already known)
    /// starts applying/broadcasting sync messages immediately.
    private func attach(session: GroupSession<WatchTogetherActivity>, vm: PlayerViewModel?) {
        self.session = session

        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger

        messageTask?.cancel()
        messageTask = Task { [weak self] in
            for await (message, _) in messenger.messages(of: SyncMessage.self) {
                await self?.handle(message)
            }
        }

        participantsWatchTask?.cancel()
        participantsWatchTask = Task { [weak self, weak session] in
            guard let session else { return }
            for await _ in session.$activeParticipants.values {
                await self?.sendHeartbeatIfOriginator()
            }
        }

        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard !Task.isCancelled else { break }
                await self?.sendHeartbeatIfOriginator()
            }
        }

        if let vm {
            activeViewModel = vm
            wireVM(vm)
        }

        session.join()
    }

    /// Called from `PlayerView.onAppear`. Covers three things: the joined-in-progress
    /// case (a session already exists -- e.g. this device just received one via
    /// `listenForIncomingSessions()` before its player finished presenting), the plain
    /// "remember which view model is on screen" bookkeeping needed so a locally-started
    /// session can find its view model once `activate()` round-trips, and replaying any
    /// `pendingRemoteState` a command that arrived before this VM was registered left
    /// behind (ISSUE watch-together #4). Named to not read as an overload of the private
    /// session-attach below -- this one only needs a VM, not a `GroupSession`.
    func registerActiveViewModel(_ vm: PlayerViewModel) {
        if let activeViewModel, activeViewModel !== vm {
            // Multi-window guard (ISSUE watch-together #8, macOS): a different VM is
            // taking over as "the" active one -- e.g. a second player window opened.
            // Clear the outgoing VM's hook so it doesn't keep firing into this
            // coordinator (and racing the new VM's own signals) after the fact. Full
            // multi-window SharePlay support is out of scope; this just prevents the
            // dangling closure.
            activeViewModel.onLocalPlaybackSignal = nil
        }
        activeViewModel = vm
        guard session != nil else { return }
        wireVM(vm)
        replayPendingRemoteStateIfNeeded(to: vm)
    }

    /// Called from `PlayerView.onDisappear`. Leaves the session and tears down the
    /// messenger task; safe to call even when no session is active.
    func detach() {
        activeViewModel?.onLocalPlaybackSignal = nil
        activeViewModel = nil

        messageTask?.cancel()
        messageTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        participantsWatchTask?.cancel()
        participantsWatchTask = nil

        session?.leave()
        session = nil
        messenger = nil
        echoSuppressUntil = nil
        pendingRemoteState = nil
    }

    private func wireVM(_ vm: PlayerViewModel) {
        vm.onLocalPlaybackSignal = { [weak self] signal in
            self?.handleLocalSignal(signal)
        }
    }

    // MARK: - Local -> remote

    /// Fired from `PlayerViewModel.onLocalPlaybackSignal`, itself fed from the engine
    /// state / clock sinks in `bindPublishers()` -- so this fires regardless of
    /// whether the change came from AVKit's native chrome, the custom
    /// `TransportOverlay`, or a just-applied remote command (suppressed below).
    private func handleLocalSignal(_ signal: PlaybackSyncSignal) {
        guard let messenger else { return }
        if let until = echoSuppressUntil, Date() < until { return }

        // `load()` landing fires a `.play` signal of its own (state passes
        // `.loading -> .paused -> .playing` at the tail of every normal load). If a
        // remote command arrived before this VM was ready to accept it, that transition
        // races the pending command -- apply the stashed state now instead of
        // broadcasting this as a genuine local "I just pressed play," which would stomp
        // whatever the pending command actually asked for (ISSUE watch-together #1).
        if case .play = signal, pendingRemoteState != nil, let vm = activeViewModel {
            replayPendingRemoteStateIfNeeded(to: vm)
            return
        }

        let message: SyncMessage
        switch signal {
        case .play(let position):
            message = .play(position: position)
        case .pause(let position):
            message = .pause(position: position)
        case .seek(let position):
            message = .seek(position: position)
        case .mediaChanged(let itemId, let title, let episodeLabel):
            message = .mediaChanged(itemId: itemId, title: title, episodeLabel: episodeLabel)
        }
        Task { try? await messenger.send(message) }
    }

    private func sendHeartbeatIfOriginator() async {
        guard let session, session.isLocallyInitiated,
              let messenger, let vm = activeViewModel else { return }
        let message = SyncMessage.heartbeat(position: vm.currentTime, isPlaying: vm.state == .playing)
        try? await messenger.send(message)
    }

    // MARK: - Remote -> local

    /// Applies an incoming `SyncMessage` through `PlayerViewModel`'s existing control
    /// methods -- the same path AetherEngine already uses uniformly across backends.
    /// `seek(to:)` is async, so this must run from a `Task`, never called synchronously.
    private func handle(_ message: SyncMessage) async {
        guard let vm = activeViewModel else {
            // Joined-in-progress race (ISSUE watch-together #4): this device's
            // `PlayerView` hasn't registered its VM yet. Stash state-bearing messages
            // instead of dropping them; `registerActiveViewModel(_:)` replays whatever
            // lands here once the VM is known.
            switch message {
            case .play(let position):
                pendingRemoteState = (position, true)
            case .pause(let position):
                pendingRemoteState = (position, false)
            case .heartbeat(let position, let isPlaying):
                pendingRemoteState = (position, isPlaying)
            case .seek(let position):
                // A bare seek carries no `isPlaying`; preserve whatever a same-window
                // play/pause/heartbeat already stashed, or assume playing -- the common
                // case for an in-session seek.
                pendingRemoteState = (position, pendingRemoteState?.isPlaying ?? true)
            case .rateChanged, .mediaChanged:
                break
            }
            return
        }

        switch message {
        case .play(let position):
            await applyRemoteState(to: vm, position: position, isPlaying: true, tolerance: Self.commandDriftTolerance)
        case .pause(let position):
            await applyRemoteState(to: vm, position: position, isPlaying: false, tolerance: Self.commandDriftTolerance)
        case .seek(let position):
            // Drift guard (ISSUE watch-together #2), same tolerance as .play/.pause:
            // without it, every remote seek re-seeks locally even when we're already
            // within a second of it, which can retrigger the sender's own seek detector
            // and ping-pong.
            guard abs(vm.currentTime - position) > Self.commandDriftTolerance else { return }
            beginEchoSuppression()
            await vm.seek(to: position)
            // Re-arm after the seek actually completes (ISSUE watch-together #2): the
            // pre-seek suppression above only covers buffering time up to this point,
            // and `detectLocalSeek` fires off the *post*-seek clock tick, which can land
            // after the original window already expired.
            beginEchoSuppression()
        case .rateChanged(let rate):
            beginEchoSuppression()
            vm.setRate(rate)
        case .heartbeat(let position, let isPlaying):
            await applyRemoteState(to: vm, position: position, isPlaying: isPlaying, tolerance: Self.heartbeatDriftTolerance)
        case .mediaChanged(let itemId, let title, let episodeLabel):
            guard itemId != vm.currentItemId else { return }
            beginEchoSuppression()
            await vm.load(itemId: itemId, title: title, episodeLabel: episodeLabel)
            // Covers `load()`'s own `mediaChanged` self-signal (fired near the top of
            // `load()`, well before this call returns) plus anything `load()` lands on
            // afterward, mirroring the seek re-arm above.
            beginEchoSuppression()
        }
    }

    /// Applies a play/pause/heartbeat command to `vm`: seeks first if position drift
    /// exceeds `tolerance`, then toggles play/pause state -- `vm.seek(to:)` already
    /// re-pauses after a paused seek (AetherEngine #122 workaround), so seek-then-toggle
    /// can't leave a stray toggle behind. Consolidates the three call sites that used to
    /// duplicate this (and fixes the previous inconsistency where `.pause` toggled then
    /// seeked while a paused heartbeat seeked then toggled).
    ///
    /// `AetherEngine.togglePlayPause()` silently no-ops outside `.playing/.paused/
    /// .loading` (ISSUE watch-together #1), and even within `.loading` position/duration
    /// aren't meaningful yet -- so anything short of `.playing`/`.paused` gets stashed as
    /// `pendingRemoteState` instead, replayed once `handleLocalSignal` sees the VM's own
    /// `.play` signal (load() landing) or `registerActiveViewModel(_:)` wires a session
    /// that's already active.
    private func applyRemoteState(to vm: PlayerViewModel, position: Double, isPlaying: Bool, tolerance: Double) async {
        guard vm.state == .playing || vm.state == .paused else {
            pendingRemoteState = (position, isPlaying)
            return
        }

        if abs(vm.currentTime - position) > tolerance {
            beginEchoSuppression()
            await vm.seek(to: position)
            // Re-arm after the seek completes (ISSUE watch-together #2), same reasoning
            // as the `.seek` case in `handle(_:)`.
            beginEchoSuppression()
        }
        if isPlaying, vm.state != .playing {
            beginEchoSuppression()
            vm.togglePlayPause()
        } else if !isPlaying, vm.state == .playing {
            beginEchoSuppression()
            vm.togglePlayPause()
        }
    }

    /// Replays `pendingRemoteState` against `vm` if there is one, clearing it either
    /// way it's consumed. Called from `registerActiveViewModel(_:)` (VM attaches after a
    /// command already arrived) and `handleLocalSignal` (VM becomes ready mid-session).
    private func replayPendingRemoteStateIfNeeded(to vm: PlayerViewModel) {
        guard let pending = pendingRemoteState else { return }
        pendingRemoteState = nil
        Task { await applyRemoteState(to: vm, position: pending.position, isPlaying: pending.isPlaying, tolerance: Self.commandDriftTolerance) }
    }

    private func beginEchoSuppression() {
        echoSuppressUntil = Date().addingTimeInterval(Self.echoSuppressionWindow)
    }
}
