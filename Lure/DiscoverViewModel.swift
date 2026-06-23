import Foundation
import Observation

@MainActor
@Observable
final class DiscoverViewModel {
    private(set) var featuredItems: [SeerrMediaItem] = []
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

    func loadInitialData(preserveResumeItemsOnEmpty: Bool = false) async {
        isLoading = true
        error = nil

        async let trendingLoad = loadTrending()
        async let moviesLoad = loadPopularMovies()
        async let tvLoad = loadPopularTV()
        async let newReleasesLoad = loadNewReleases()
        async let upcomingLoad = loadUpcomingMovies()
        async let collectionsLoad = loadCollections()
        async let continueWatchingLoad = loadContinueWatching(preserveExistingOnEmpty: preserveResumeItemsOnEmpty)

        _ = await (trendingLoad, moviesLoad, tvLoad, newReleasesLoad, upcomingLoad, collectionsLoad, continueWatchingLoad)
        isLoading = false
    }

    func refresh() async {
        await loadInitialData(preserveResumeItemsOnEmpty: true)
    }

    func markWatched(_ item: JellyfinItem) async throws {
        try await jellyfinService.markWatched(item)
        if let itemID = item.id {
            continueWatching.removeAll { $0.id == itemID }
        }
    }

    private func loadTrending() async {
        do {
            let response = try await apiClient.getDiscoverTrending()
            let items = response.results.map { $0.toMediaItem() }
            trending = items
            featuredItems = await filteredFeaturedItems(from: items)
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

    private func loadContinueWatching(preserveExistingOnEmpty: Bool) async {
        let items = await jellyfinService.resumeItems()
        if !items.isEmpty || !preserveExistingOnEmpty {
            continueWatching = items
        }
    }

    private func filteredFeaturedItems(from items: [SeerrMediaItem]) async -> [SeerrMediaItem] {
        let movieIDs = items.compactMap { item -> Int? in
            if case .movie(let movie) = item {
                return movie.id
            }
            return nil
        }
        let homeReleasedMovieIDs = await homeReleasedMovieIDs(for: movieIDs)

        return items.filter { item in
            switch item {
            case .movie(let movie):
                homeReleasedMovieIDs.contains(movie.id)
            case .tv:
                true
            case .person:
                false
            }
        }
    }

    private func homeReleasedMovieIDs(for movieIDs: [Int]) async -> Set<Int> {
        let uniqueIDs = Array(Set(movieIDs))
        let apiClient = self.apiClient

        return await withTaskGroup(of: Int?.self) { group in
            for movieID in uniqueIDs {
                group.addTask {
                    do {
                        let detail = try await apiClient.getMovieDetail(tmdbId: movieID)
                        return detail.hasHomeViewingRelease ? movieID : nil
                    } catch {
                        return nil
                    }
                }
            }

            var releasedIDs = Set<Int>()
            for await movieID in group {
                if let movieID {
                    releasedIDs.insert(movieID)
                }
            }
            return releasedIDs
        }
    }
}

private extension SeerrMovieDetail {
    var hasHomeViewingRelease: Bool {
        if mediaInfo?.isAvailable == true {
            return true
        }

        let homeReleaseTypes: Set<Int> = [4, 5, 6]
        let now = Date()
        return releases?.preferredReleaseDates.contains { releaseDate in
            guard let type = releaseDate.type,
                  homeReleaseTypes.contains(type),
                  let date = releaseDate.parsedDate else {
                return false
            }
            return date <= now
        } == true
    }
}
