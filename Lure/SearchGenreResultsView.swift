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
                List {
                    ForEach(vm.results) { item in
                        NavigationLink(value: MediaDestination(mediaType: item.mediaType, tmdbId: item.tmdbId, title: item.title, posterURL: item.posterURL)) {
                            MediaListRow(item: item)
                        }
                        .task {
                            await vm.loadMoreIfNeeded(currentItem: item)
                        }
                    }

                    if vm.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(destination.title)
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
