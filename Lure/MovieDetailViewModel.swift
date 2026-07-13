import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MovieDetailViewModel {
    let tmdbId: Int
    private(set) var movie: SeerrMovieDetail?
    private(set) var ratings: SeerrRatingsCombined?
    private(set) var recommendations: [SeerrMediaItem] = []
    private(set) var isLoading: Bool = true
    private(set) var isRequesting: Bool = false
    var error: String?
    private(set) var requestSuccess: Bool = false
    private(set) var playbackAvailability: PlaybackAvailability = .unknown
    private(set) var mediaQuality: MediaQualityInfo?
    private(set) var resumePositionSeconds: Double = 0
    private(set) var heroArtwork: MediaArtwork?

    /// True when Jellyfin has a saved playback position partway through the film,
    /// so the Watch button should offer to continue instead of restart.
    var canResume: Bool { resumePositionSeconds > 30 }

    private let apiClient: SeerrAPIClient
    private let jellyfinService: JellyfinService

    init(tmdbId: Int, apiClient: SeerrAPIClient, jellyfinService: JellyfinService) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
        self.jellyfinService = jellyfinService
    }

    func load() async {
        withAnimation(.smooth(duration: 0.3)) {
            isLoading = true
            error = nil
            heroArtwork = nil
        }

        do {
            let loadedMovie = try await apiClient.getMovieDetail(tmdbId: tmdbId)
            withAnimation(.smooth(duration: 0.35)) {
                movie = loadedMovie
            }
            await resolvePlaybackAvailability(for: loadedMovie)
        } catch {
            withAnimation(.smooth(duration: 0.25)) {
                self.error = error.localizedDescription
            }
        }

        // Load ratings and recommendations concurrently (non-critical)
        async let artworkLoad: () = loadArtwork()
        async let ratingsLoad: () = loadRatings()
        async let recsLoad: () = loadRecommendations()
        _ = await (artworkLoad, ratingsLoad, recsLoad)

        withAnimation(.smooth(duration: 0.3)) {
            isLoading = false
        }
    }

    func requestMovie(is4k: Bool = false) async {
        isRequesting = true
        error = nil
        requestSuccess = false

        do {
            let body = SeerrCreateRequestBody(
                mediaType: "movie",
                mediaId: tmdbId,
                is4k: is4k,
                serverId: nil,
                profileId: nil,
                rootFolder: nil,
                seasons: nil,
                tags: nil,
                userId: nil
            )
            _ = try await apiClient.createRequest(body)
            requestSuccess = true
            // Reload to get updated mediaInfo
            movie = try await apiClient.getMovieDetail(tmdbId: tmdbId)
            if let movie {
                await resolvePlaybackAvailability(for: movie)
            }
        } catch {
            self.error = error.localizedDescription
        }

        isRequesting = false
    }

    private func loadRatings() async {
        let loadedRatings = try? await apiClient.getMovieRatings(tmdbId: tmdbId)
        withAnimation(.smooth(duration: 0.35)) {
            ratings = loadedRatings
        }
    }

    private func loadRecommendations() async {
        if let response = try? await apiClient.getMovieRecommendations(tmdbId: tmdbId) {
            let loadedRecommendations = response.results.map { $0.toMediaItem() }
            withAnimation(.smooth(duration: 0.35)) {
                recommendations = loadedRecommendations
            }
        }
    }

    private func loadArtwork() async {
        guard let movie else { return }
        let artwork = await MediaArtworkService.shared.artwork(
            mediaType: "movie",
            tmdbId: tmdbId,
            fallbackBackdropURL: movie.backdropURL,
            fallbackPosterURL: movie.heroPosterURL
        )
        withAnimation(.smooth(duration: 0.35)) {
            heroArtwork = artwork
        }
    }

    func refreshPlaybackAvailability() async {
        guard let movie else { return }
        await resolvePlaybackAvailability(for: movie)
    }

    private func resolvePlaybackAvailability(for movie: SeerrMovieDetail) async {
        guard movie.mediaInfo?.isAvailable == true else {
            playbackAvailability = .unknown
            mediaQuality = nil
            resumePositionSeconds = 0
            return
        }
        playbackAvailability = .checking
        mediaQuality = nil
        resumePositionSeconds = 0
        playbackAvailability = await jellyfinService.resolvePlaybackAvailability(
            tmdbId: tmdbId,
            mediaType: "movie",
            title: movie.displayTitle,
            releaseYear: movie.year.flatMap(Int.init),
            serviceUrl: movie.mediaInfo?.serviceUrl
        )
        if let itemId = playbackAvailability.playableItemId {
            await loadPlayableDetails(itemId: itemId)
        }
    }

    private func loadPlayableDetails(itemId: String) async {
        guard let client = jellyfinService.client else { return }
        async let infoTask = client.getPlaybackInfo(itemId: itemId)
        async let itemTask = client.getItem(itemId: itemId)
        let info = try? await infoTask
        let item = try? await itemTask

        let quality = MediaQualityInfo(mediaSources: info?.mediaSources)
        let resume = item?.resumePositionSeconds ?? 0
        withAnimation(.smooth(duration: 0.3)) {
            mediaQuality = quality
            resumePositionSeconds = resume
        }
    }
}
