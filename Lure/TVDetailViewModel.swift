import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class TVDetailViewModel {
    let tmdbId: Int
    private(set) var show: SeerrTVDetail?
    private(set) var ratings: SeerrRatingsCombined?
    private(set) var recommendations: [SeerrMediaItem] = []
    private(set) var isLoading: Bool = true
    private(set) var isRequesting: Bool = false
    var error: String?
    private(set) var requestSuccess: Bool = false
    private(set) var playbackAvailability: PlaybackAvailability = .unknown
    private(set) var heroArtwork: MediaArtwork?
    private(set) var isFavorite = false

    // Season selection for requests
    var selectedSeasons: Set<Int> = []

    private let apiClient: SeerrAPIClient
    private let jellyfinService: JellyfinService

    var jellyfinClient: JellyfinAPIClient? {
        jellyfinService.client
    }

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
            let loadedShow = try await apiClient.getTVDetail(tmdbId: tmdbId)
            let loadedArtwork = await artwork(for: loadedShow)
            withAnimation(.smooth(duration: 0.35)) {
                show = loadedShow
                heroArtwork = loadedArtwork
            }
            await resolvePlaybackAvailability(for: loadedShow)
        } catch {
            withAnimation(.smooth(duration: 0.25)) {
                self.error = error.localizedDescription
            }
        }

        async let ratingsLoad: () = loadRatings()
        async let recsLoad: () = loadRecommendations()
        _ = await (ratingsLoad, recsLoad)

        withAnimation(.smooth(duration: 0.3)) {
            isLoading = false
        }
    }

    func selectAllSeasons(is4k: Bool = false) {
        guard let show else { return }
        selectedSeasons = Set(
            show.requestableSeasons
                .map(\.seasonNumber)
                .filter { !isSeasonUnavailableForRequest($0, is4k: is4k) }
        )
    }

    func deselectAllSeasons() {
        selectedSeasons.removeAll()
    }

    func toggleSeason(_ number: Int) {
        if selectedSeasons.contains(number) {
            selectedSeasons.remove(number)
        } else {
            selectedSeasons.insert(number)
        }
    }

    func filterSelectedSeasons(for is4k: Bool) {
        selectedSeasons = selectedSeasons.filter { !isSeasonUnavailableForRequest($0, is4k: is4k) }
    }

    /// Whether a season is already requested or available for the selected quality
    func isSeasonUnavailableForRequest(_ seasonNumber: Int, is4k: Bool = false) -> Bool {
        guard let mediaInfo = show?.mediaInfo else { return false }

        // Check if season is already available
        if let seasonStatus = mediaInfo.seasons?.first(where: { $0.seasonNumber == seasonNumber }) {
            if seasonStatus.mediaStatus == .available || seasonStatus.mediaStatus == .processing {
                return true
            }
        }

        // Check if season is already requested
        if let requests = mediaInfo.requests {
            for request in requests {
                if let seasonReqs = request.seasons {
                    if request.is4k == is4k &&
                        seasonReqs.contains(where: { $0.seasonNumber == seasonNumber && $0.requestStatus != .declined }) {
                        return true
                    }
                }
            }
        }

        return false
    }

    func unavailableSeasonReason(_ seasonNumber: Int, is4k: Bool) -> String? {
        guard let mediaInfo = show?.mediaInfo else { return nil }

        if let seasonStatus = mediaInfo.seasons?.first(where: { $0.seasonNumber == seasonNumber }),
           seasonStatus.mediaStatus == .available || seasonStatus.mediaStatus == .processing {
            return "Already available"
        }

        if isSeasonUnavailableForRequest(seasonNumber, is4k: is4k) {
            return is4k ? "4K requested" : "HD requested"
        }

        return nil
    }

    func requestShow(is4k: Bool = false) async {
        guard !selectedSeasons.isEmpty else {
            error = "Select at least one season."
            return
        }

        isRequesting = true
        error = nil
        requestSuccess = false

        do {
            let body = SeerrCreateRequestBody(
                mediaType: "tv",
                mediaId: tmdbId,
                is4k: is4k,
                serverId: nil,
                profileId: nil,
                rootFolder: nil,
                seasons: Array(selectedSeasons).sorted(),
                tags: nil,
                userId: nil
            )
            _ = try await apiClient.createRequest(body)
            requestSuccess = true
            let updatedShow = try await apiClient.getTVDetail(tmdbId: tmdbId)
            let updatedArtwork = await artwork(for: updatedShow)
            withAnimation(.smooth(duration: 0.3)) {
                show = updatedShow
                heroArtwork = updatedArtwork
            }
            await resolvePlaybackAvailability(for: updatedShow)
            selectedSeasons.removeAll()
        } catch {
            self.error = error.localizedDescription
        }

        isRequesting = false
    }

    private func loadRatings() async {
        let loadedRatings = try? await apiClient.getTVRatings(tmdbId: tmdbId)
        withAnimation(.smooth(duration: 0.35)) {
            ratings = loadedRatings
        }
    }

    private func loadRecommendations() async {
        if let response = try? await apiClient.getTVRecommendations(tmdbId: tmdbId) {
            let loadedRecommendations = response.results.map { $0.toMediaItem() }
            withAnimation(.smooth(duration: 0.35)) {
                recommendations = loadedRecommendations
            }
        }
    }

    private func artwork(for show: SeerrTVDetail) async -> MediaArtwork {
        await MediaArtworkService.shared.artwork(
            mediaType: "tv",
            tmdbId: tmdbId,
            fallbackBackdropURL: show.heroBackdropURL ?? show.backdropURL,
            fallbackPosterURL: show.heroPosterURL
        )
    }

    func refreshPlaybackAvailability() async {
        guard let show else { return }
        await resolvePlaybackAvailability(for: show)
    }

    func addPlayableItemToFavorites() async throws {
        guard let itemId = playbackAvailability.playableItemId else {
            throw JellyfinError.itemNotFound
        }
        guard let client = jellyfinService.client else {
            throw JellyfinError.noCredentials
        }
        try await client.addFavorite(itemId: itemId)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            isFavorite = true
        }
    }

    private func resolvePlaybackAvailability(for show: SeerrTVDetail) async {
        guard show.hasPlayableContent else {
            playbackAvailability = .unknown
            isFavorite = false
            return
        }
        playbackAvailability = .checking
        isFavorite = false
        playbackAvailability = await jellyfinService.resolvePlaybackAvailability(
            tmdbId: tmdbId,
            mediaType: "tv",
            title: show.displayTitle,
            releaseYear: show.year.flatMap(Int.init),
            serviceUrl: show.mediaInfo?.serviceUrl
        )
        if let itemId = playbackAvailability.playableItemId {
            await loadFavoriteState(itemId: itemId)
        }
    }

    private func loadFavoriteState(itemId: String) async {
        guard let client = jellyfinService.client else { return }
        let item = try? await client.getItem(itemId: itemId)
        withAnimation(.smooth(duration: 0.3)) {
            isFavorite = item?.userData?.isFavorite == true
        }
    }
}
