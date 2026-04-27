import SwiftUI

struct DiscoverView: View {
    let apiClient: SeerrAPIClient
    @State private var viewModel: DiscoverViewModel?
    @Namespace private var navigationTransitionNamespace

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    discoverContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Discover")
            .navigationDestination(for: MediaDestination.self) { dest in
                if dest.mediaType == "movie" {
                    MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                        .navigationTransition(.zoom(sourceID: dest, in: navigationTransitionNamespace))
                } else {
                    TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                        .navigationTransition(.zoom(sourceID: dest, in: navigationTransitionNamespace))
                }
            }
            .refreshable { await viewModel?.refresh() }
            .task {
                if viewModel == nil {
                    let vm = DiscoverViewModel(apiClient: apiClient)
                    viewModel = vm
                    await vm.loadInitialData()
                }
            }
            .toolbarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private func discoverContent(vm: DiscoverViewModel) -> some View {
        if vm.isLoading && vm.trending.isEmpty {
            VStack {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    MediaSliderView(title: "Trending", icon: "flame", items: vm.trending, apiClient: apiClient, transitionNamespace: navigationTransitionNamespace)
                    MediaSliderView(title: "Popular Movies", icon: "film", items: vm.popularMovies, apiClient: apiClient, transitionNamespace: navigationTransitionNamespace)
                    MediaSliderView(title: "Popular TV", icon: "tv", items: vm.popularTV, apiClient: apiClient, transitionNamespace: navigationTransitionNamespace)
                    MediaSliderView(title: "Upcoming", icon: "calendar", items: vm.upcomingMovies, apiClient: apiClient, transitionNamespace: navigationTransitionNamespace)
                }
                .padding(.vertical)
            }
        }
    }
}
