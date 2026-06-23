import Foundation
import Observation

@Observable
final class SearchViewModel {
    var query: String = ""
    private(set) var results: [SeerrMediaItem] = []
    private(set) var browseGenres: [SearchGenreTile] = []
    private(set) var isSearching: Bool = false
    private(set) var isLoadingBrowseGenres: Bool = false
    private(set) var hasSearched: Bool = false
    private(set) var currentPage: Int = 1
    private(set) var totalPages: Int = 1
    private(set) var error: String?

    private let apiClient: SeerrAPIClient
    private var searchTask: Task<Void, Never>?
    private var hasLoadedBrowseGenres = false

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    static func preloadBrowseGenres(using apiClient: SeerrAPIClient) async {
        guard await SearchBrowseGenresCache.shared.genres() == nil else { return }
        let viewModel = SearchViewModel(apiClient: apiClient)
        await viewModel.loadBrowseGenresIfNeeded()
    }

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchTask?.cancel()
            isSearching = false
            results = []
            hasSearched = false
            return
        }

        searchTask?.cancel()
        isSearching = true
        hasSearched = true
        error = nil
        currentPage = 1

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300)) // debounce
                guard !Task.isCancelled else { return }
                let response = try await apiClient.search(query: trimmed, page: 1)
                guard !Task.isCancelled else { return }
                results = response.results.map { $0.toMediaItem() }
                totalPages = response.totalPages
                currentPage = 1
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }

    func loadBrowseGenresIfNeeded() async {
        guard !hasLoadedBrowseGenres, !isLoadingBrowseGenres else { return }
        if let cachedGenres = await SearchBrowseGenresCache.shared.genres() {
            browseGenres = cachedGenres
            hasLoadedBrowseGenres = true
            return
        }

        isLoadingBrowseGenres = true
        defer { isLoadingBrowseGenres = false }

        do {
            async let movieGenresLoad = apiClient.getMovieGenres()
            async let tvGenresLoad = apiClient.getTVGenres()
            async let popularMoviesLoad = apiClient.getDiscoverMovies(page: 1)
            async let popularTVLoad = apiClient.getDiscoverTV(page: 1)
            async let popularMoviesPageTwoLoad = apiClient.getDiscoverMovies(page: 2)
            async let popularTVPageTwoLoad = apiClient.getDiscoverTV(page: 2)

            let (movieGenres, tvGenres, popularMovies, popularTV, popularMoviesPageTwo, popularTVPageTwo) = try await (
                movieGenresLoad,
                tvGenresLoad,
                popularMoviesLoad,
                popularTVLoad,
                popularMoviesPageTwoLoad,
                popularTVPageTwoLoad
            )

            var usedArtworkURLs = Set<String>()
            let movieTiles = makeGenreTiles(
                genres: movieGenres,
                results: (popularMovies.results + popularMoviesPageTwo.results).compactMap(movieSummary(from:)),
                mediaType: "movie",
                limit: 6,
                usedArtworkURLs: &usedArtworkURLs
            )
            let tvTiles = makeGenreTiles(
                genres: tvGenres,
                results: (popularTV.results + popularTVPageTwo.results).compactMap(tvSummary(from:)),
                mediaType: "tv",
                limit: 6,
                usedArtworkURLs: &usedArtworkURLs
            )

            browseGenres = try await fillMissingGenreArtwork(
                for: (movieTiles + tvTiles).sorted {
                    if $0.mediaType == $1.mediaType {
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    return $0.mediaType < $1.mediaType
                }
            )
            await SearchBrowseGenresCache.shared.store(browseGenres)
            hasLoadedBrowseGenres = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard currentPage < totalPages else { return }
        let nextPage = currentPage + 1
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            let response = try await apiClient.search(query: trimmed, page: nextPage)
            let newItems = response.results.map { $0.toMediaItem() }
            let existingIDs = Set(results.map(\.id))
            let unique = newItems.filter { !existingIDs.contains($0.id) }
            results.append(contentsOf: unique)
            currentPage = nextPage
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clear() {
        query = ""
        results = []
        hasSearched = false
        currentPage = 1
    }

    private func makeGenreTiles(
        genres: [SeerrGenre],
        results: [GenreArtworkSource],
        mediaType: String,
        limit: Int,
        usedArtworkURLs: inout Set<String>
    ) -> [SearchGenreTile] {
        genres.compactMap { genre in
            guard let genreID = genre.id, let name = genre.name, !name.isEmpty else { return nil }
            let artworkURL = pickArtworkURL(
                for: genreID,
                name: name,
                from: results,
                usedArtworkURLs: &usedArtworkURLs
            )
            return SearchGenreTile(
                genreID: genreID,
                mediaType: mediaType,
                name: name,
                artworkURL: artworkURL
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    private func movieSummary(from result: SeerrMixedResult) -> GenreArtworkSource? {
        guard result.mediaType == "movie" else { return nil }
        return GenreArtworkSource(
            genreIDs: result.genreIds ?? [],
            imageURL: ImageURL.backdrop(result.backdropPath) ?? ImageURL.poster(result.posterPath, size: .large)
        )
    }

    private func tvSummary(from result: SeerrMixedResult) -> GenreArtworkSource? {
        guard result.mediaType == "tv" else { return nil }
        return GenreArtworkSource(
            genreIDs: result.genreIds ?? [],
            imageURL: ImageURL.backdrop(result.backdropPath) ?? ImageURL.poster(result.posterPath, size: .large)
        )
    }

    private func pickArtworkURL(
        for genreID: Int,
        name: String,
        from results: [GenreArtworkSource],
        usedArtworkURLs: inout Set<String>
    ) -> URL? {
        let matches = results.filter { $0.genreIDs.contains(genreID) && $0.imageURL != nil }
        guard !matches.isEmpty else { return nil }

        let seed = stableArtworkSeed(for: genreID, name: name)
        let sortedMatches = matches.sorted { lhs, rhs in
            (lhs.imageURL?.absoluteString ?? "") < (rhs.imageURL?.absoluteString ?? "")
        }

        for offset in 0..<sortedMatches.count {
            let index = (seed + offset) % sortedMatches.count
            guard let artworkURL = sortedMatches[index].imageURL else { continue }
            let key = artworkURL.absoluteString
            if usedArtworkURLs.insert(key).inserted {
                return artworkURL
            }
        }

        return nil
    }

    private func stableArtworkSeed(for genreID: Int, name: String) -> Int {
        name.unicodeScalars.reduce(genreID * 31) { partialResult, scalar in
            partialResult &+ Int(scalar.value)
        }
    }

    private func fillMissingGenreArtwork(for tiles: [SearchGenreTile]) async throws -> [SearchGenreTile] {
        let missingTiles = tiles.filter { $0.artworkURL == nil }
        guard !missingTiles.isEmpty else { return tiles }

        let apiClient = self.apiClient
        var recoveredArtworkByID: [String: URL] = [:]

        await withTaskGroup(of: (String, URL?).self) { group in
            for tile in missingTiles {
                group.addTask {
                    do {
                        let response: SeerrDiscoverResponse
                        if tile.mediaType == "movie" {
                            response = try await apiClient.getDiscoverMovies(page: 1, genre: tile.genreID)
                            let artworkURL = response.results
                                .compactMap { $0.mediaType == "movie" ? self.movieSummary(from: $0) : nil }
                                .compactMap(\.imageURL)
                                .first
                            return (tile.id, artworkURL)
                        } else {
                            response = try await apiClient.getDiscoverTV(page: 1, genre: tile.genreID)
                            let artworkURL = response.results
                                .compactMap { $0.mediaType == "tv" ? self.tvSummary(from: $0) : nil }
                                .compactMap(\.imageURL)
                                .first
                            return (tile.id, artworkURL)
                        }
                    } catch {
                        return (tile.id, nil)
                    }
                }
            }

            for await (tileID, artworkURL) in group {
                if let artworkURL {
                    recoveredArtworkByID[tileID] = artworkURL
                }
            }
        }

        return tiles.map { tile in
            guard tile.artworkURL == nil, let recoveredArtwork = recoveredArtworkByID[tile.id] else { return tile }
            return SearchGenreTile(
                genreID: tile.genreID,
                mediaType: tile.mediaType,
                name: tile.name,
                artworkURL: recoveredArtwork
            )
        }
    }
}

struct SearchGenreTile: Identifiable, Hashable, Sendable {
    let genreID: Int
    let mediaType: String
    let name: String
    let artworkURL: URL?

    var id: String { "\(mediaType)-\(genreID)" }
}

private struct GenreArtworkSource {
    let genreIDs: [Int]
    let imageURL: URL?
}
