import SwiftUI

struct SearchGenreResultsView: View {
    let destination: SearchGenreDestination
    let apiClient: SeerrAPIClient

    @State private var vm: SearchGenreResultsViewModel

    init(destination: SearchGenreDestination, apiClient: SeerrAPIClient) {
        self.destination = destination
        self.apiClient = apiClient
        self._vm = State(initialValue: SearchGenreResultsViewModel(destination: destination, apiClient: apiClient))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.results.isEmpty {
                ProgressView("Loading \(vm.destination.title)...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.results.isEmpty {
                ContentUnavailableView(
                    vm.destination.title,
                    systemImage: vm.destination.mediaType == "movie" ? "film" : "tv",
                    description: Text("No \(vm.destination.mediaTypeLabel.lowercased()) found for this genre.")
                )
            } else {
                DiscoverMediaGridView(title: destination.title, initialItems: vm.results, apiClient: apiClient) { page in
                    try await vm.loadPage(page)
                }
            }
        }
        .lureNavigationTitle(destination.title)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: destination) { await vm.load() }
    }
}

private extension SearchGenreDestination {
    var mediaTypeLabel: String {
        mediaType == "movie" ? "Movies" : "TV shows"
    }
}

#if DEBUG && os(iOS)
#Preview("Genre Results — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        SearchGenreResultsView(
            destination: SearchGenreDestination(
                genre: PreviewSupport.sampleGenreTiles[7]
            ),
            apiClient: PreviewSupport.apiClient
        )
    }
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif
