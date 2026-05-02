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

    private let apiClient: SeerrAPIClient

    init(tmdbId: Int, apiClient: SeerrAPIClient) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
    }

    func load() async {
        withAnimation(.smooth(duration: 0.3)) {
            isLoading = true
            error = nil
        }

        do {
            let loadedMovie = try await apiClient.getMovieDetail(tmdbId: tmdbId)
            withAnimation(.smooth(duration: 0.35)) {
                movie = loadedMovie
            }
        } catch {
            withAnimation(.smooth(duration: 0.25)) {
                self.error = error.localizedDescription
            }
        }

        // Load ratings and recommendations concurrently (non-critical)
        async let ratingsLoad: () = loadRatings()
        async let recsLoad: () = loadRecommendations()
        _ = await (ratingsLoad, recsLoad)

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
}
