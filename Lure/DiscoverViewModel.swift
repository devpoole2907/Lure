import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var trending: [SeerrMediaItem] = []
    private(set) var popularMovies: [SeerrMediaItem] = []
    private(set) var popularTV: [SeerrMediaItem] = []
    private(set) var newReleases: [SeerrMediaItem] = []
    private(set) var upcomingMovies: [SeerrMediaItem] = []
    private(set) var collections: [SeerrCollection] = []
    private(set) var continueWatching: [JellyfinItem] = []
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    private let apiClient: SeerrAPIClient
    private let jellyfinService: JellyfinService

    var jellyfinClient: JellyfinAPIClient? { jellyfinService.client }

    init(apiClient: SeerrAPIClient, jellyfinService: JellyfinService) {
        self.apiClient = apiClient
        self.jellyfinService = jellyfinService
    }

    func loadInitialData() async {
        isLoading = true
        error = nil

        async let trendingLoad = loadTrending()
        async let moviesLoad = loadPopularMovies()
        async let tvLoad = loadPopularTV()
        async let newReleasesLoad = loadNewReleases()
        async let upcomingLoad = loadUpcomingMovies()
        async let collectionsLoad = loadCollections()
        async let continueWatchingLoad = loadContinueWatching()

        _ = await (trendingLoad, moviesLoad, tvLoad, newReleasesLoad, upcomingLoad, collectionsLoad, continueWatchingLoad)
        isLoading = false
    }

    func refresh() async {
        await loadInitialData()
    }

    private func loadTrending() async {
        do {
            let response = try await apiClient.getDiscoverTrending()
            trending = response.results.map { $0.toMediaItem() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPopularMovies() async {
        do {
            let response = try await apiClient.getDiscoverMovies(page: 1, sortBy: "popularity.desc")
            popularMovies = response.results.map { $0.toMediaItem() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPopularTV() async {
        do {
            let response = try await apiClient.getDiscoverTV(page: 1, sortBy: "popularity.desc")
            popularTV = response.results.map { $0.toMediaItem() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadNewReleases() async {
        do {
            let response = try await apiClient.getDiscoverMoviesNewReleases()
            newReleases = response.results.map { $0.toMediaItem() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadUpcomingMovies() async {
        do {
            let response = try await apiClient.getDiscoverMoviesUpcoming()
            upcomingMovies = response.results.map { $0.toMediaItem() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadCollections() async {
        let result = await CollectionsViewModel.loadCollections(using: apiClient)
        collections = result
        if result.isEmpty {
            if error == nil {
                error = "Could not load collections."
            }
        }
    }

    private func loadContinueWatching() async {
        continueWatching = await jellyfinService.resumeItems()
    }
}
