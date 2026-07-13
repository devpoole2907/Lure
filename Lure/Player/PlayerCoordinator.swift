import SwiftUI
import Observation

/// App-level player presentation. Owns the active `PlayerPresentation` and
/// constructs `PlayerViewModel` instances on demand. Inject via
/// `.environment(playerCoordinator)` and present once via
/// `.playerPresentation()` near the root of the navigation tree.
@Observable
@MainActor
final class PlayerCoordinator {
    var activePlayer: PlayerPresentation?
    var presentationError: String?

    private let jellyfinService: JellyfinService

    init(jellyfinService: JellyfinService) {
        self.jellyfinService = jellyfinService
    }

    /// Build a `PlayerViewModel` and show the player full-screen. If the
    /// engine fails to init the error is surfaced via `presentationError`.
    func present(
        itemId: String,
        title: String,
        episodeLabel: String? = nil,
        serviceUrl: String? = nil,
        tmdbId: Int? = nil,
        releaseYear: Int? = nil,
        mediaType: String = "movie"
    ) {
        present(PlayableMedia(
            itemId: itemId,
            title: title,
            episodeLabel: episodeLabel,
            serviceUrl: serviceUrl,
            tmdbId: tmdbId,
            releaseYear: releaseYear,
            mediaType: mediaType
        ))
    }

    /// Build a `PlayerViewModel` for a portable media payload and show it. The
    /// payload stays view-model free so it can later be routed to a macOS window,
    /// tvOS player shell, or fallback engine without changing callers.
    func present(_ media: PlayableMedia) {
        do {
            let vm = try PlayerViewModel(jellyfinService: jellyfinService)
            activePlayer = PlayerPresentation(
                vm: vm,
                media: media
            )
        } catch {
            presentationError = "Player failed to start: \(error.localizedDescription)"
        }
    }

    /// Convenience for Continue Watching items, which already carry a
    /// Jellyfin item id and only need title/episode metadata derived.
    func presentResume(_ item: JellyfinItem) {
        guard item.id != nil else { return }
        present(PlayableMedia(resumeItem: item))
    }
}

// MARK: - View modifier

private struct PlayerPresentationModifier: ViewModifier {
    @Environment(PlayerCoordinator.self) private var coordinator
    @Environment(InAppNotificationCenter.self) private var notificationCenter

    func body(content: Content) -> some View {
        @Bindable var bindable = coordinator
        content
            .fullScreenCover(item: $bindable.activePlayer) { presentation in
                PlayerView(
                    vm: presentation.vm,
                    media: presentation.media
                )
                .environment(notificationCenter)
            }
            .onChange(of: coordinator.presentationError) { _, message in
                guard let message else { return }
                notificationCenter.show(LureBannerItem(
                    title: "Playback Error",
                    message: message,
                    style: .error
                ))
                coordinator.presentationError = nil
            }
    }
}

extension View {
    /// Hosts the app's `PlayerCoordinator`-driven full-screen player.
    /// Apply once near the root of the view hierarchy.
    func playerPresentation() -> some View {
        modifier(PlayerPresentationModifier())
    }
}
