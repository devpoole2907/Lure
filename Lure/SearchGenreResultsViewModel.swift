import Foundation
import Observation

@Observable
final class SearchGenreResultsViewModel {
    private(set) var results: [SeerrMediaItem] = []
    private(set) var isLoading: Bool = false
    private(set) var isLoadingMore: Bool = false
    private(set) var currentPage: Int = 1
    private(set) var totalPages: Int = 1
    var error: String?

    let destination: SearchGenreDestination

    private let apiClient: SeerrAPIClient

    init(destination: SearchGenreDestination, apiClient: SeerrAPIClient) {
        self.destination = destination
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        error = nil
        currentPage = 1

        do {
            let response = try await fetch(page: 1)
            let filtered = filterResults(response.results)
            results = filtered.map { $0.toMediaItem() }
            currentPage = 1
            totalPages = response.totalPages
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard currentPage < totalPages else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            var nextPage = currentPage + 1

            while nextPage <= totalPages {
                let response = try await fetch(page: nextPage)
                let filtered = filterResults(response.results)
                let newItems = filtered.map { $0.toMediaItem() }
                let existingIDs = Set(results.map(\.id))
                let uniqueItems = newItems.filter { !existingIDs.contains($0.id) }
                currentPage = nextPage

                if !uniqueItems.isEmpty {
                    results.append(contentsOf: uniqueItems)
                    break
                }

                nextPage += 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem item: SeerrMediaItem) async {
        guard let itemIndex = results.firstIndex(where: { $0.id == item.id }) else { return }
        let thresholdIndex = max(results.count - 4, 0)
        guard itemIndex >= thresholdIndex else { return }
        await loadMore()
    }

    func loadPage(_ page: Int) async throws -> [SeerrMediaItem] {
        guard page <= totalPages else { return [] }
        let response = try await fetch(page: page)
        return filterResults(response.results).map { $0.toMediaItem() }
    }

    private func fetch(page: Int) async throws -> SeerrDiscoverResponse {
        switch destination.mediaType {
        case "movie":
            return try await apiClient.getDiscoverMovies(page: page, genre: destination.genreID)
        case "tv":
            return try await apiClient.getDiscoverTV(page: page, genre: destination.genreID)
        default:
            return SeerrDiscoverResponse(page: 1, totalPages: 1, totalResults: 0, results: [])
        }
    }

    private func filterResults(_ results: [SeerrMixedResult]) -> [SeerrMixedResult] {
        results.filter { result in
            result.mediaType == destination.mediaType &&
            (result.genreIds ?? []).contains(destination.genreID)
        }
    }
}
