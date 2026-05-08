import Foundation
import Observation

@Observable
final class DiscoverViewModel {
    private(set) var trending: [SeerrMediaItem] = []
    private(set) var popularMovies: [SeerrMediaItem] = []
    private(set) var popularTV: [SeerrMediaItem] = []
    private(set) var upcomingMovies: [SeerrMediaItem] = []
    private(set) var collections: [SeerrCollection] = []
    private(set) var isLoading: Bool = false
    private(set) var error: String?

    private let apiClient: SeerrAPIClient

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    func loadInitialData() async {
        isLoading = true
        error = nil

        async let trendingLoad = loadTrending()
        async let moviesLoad = loadPopularMovies()
        async let tvLoad = loadPopularTV()
        async let upcomingLoad = loadUpcomingMovies()
        async let collectionsLoad = loadCollections()

        _ = await (trendingLoad, moviesLoad, tvLoad, upcomingLoad, collectionsLoad)
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
}
