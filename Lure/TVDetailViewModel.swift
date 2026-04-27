import Foundation
import Observation

@Observable
final class TVDetailViewModel {
    let tmdbId: Int
    private(set) var show: SeerrTVDetail?
    private(set) var ratings: SeerrRatingsCombined?
    private(set) var recommendations: [SeerrMediaItem] = []
    private(set) var isLoading: Bool = false
    private(set) var isRequesting: Bool = false
    var error: String?
    private(set) var requestSuccess: Bool = false

    // Season selection for requests
    var selectedSeasons: Set<Int> = []

    private let apiClient: SeerrAPIClient

    init(tmdbId: Int, apiClient: SeerrAPIClient) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        error = nil

        do {
            show = try await apiClient.getTVDetail(tmdbId: tmdbId)
        } catch {
            self.error = error.localizedDescription
        }

        async let ratingsLoad: () = loadRatings()
        async let recsLoad: () = loadRecommendations()
        _ = await (ratingsLoad, recsLoad)

        isLoading = false
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
            show = try await apiClient.getTVDetail(tmdbId: tmdbId)
            selectedSeasons.removeAll()
        } catch {
            self.error = error.localizedDescription
        }

        isRequesting = false
    }

    private func loadRatings() async {
        ratings = try? await apiClient.getTVRatings(tmdbId: tmdbId)
    }

    private func loadRecommendations() async {
        if let response = try? await apiClient.getTVRecommendations(tmdbId: tmdbId) {
            recommendations = response.results.map { $0.toMediaItem() }
        }
    }
}
