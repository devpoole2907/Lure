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
            .navigationDestination(for: DiscoverSectionDestination.self) { destination in
                if let vm = viewModel {
                    switch destination {
                    case .trending:
                        DiscoverMediaGridView(
                            title: "Trending",
                            items: vm.trending,
                            transitionNamespace: navigationTransitionNamespace
                        )
                    case .popularMovies:
                        DiscoverMediaGridView(
                            title: "Popular Movies",
                            items: vm.popularMovies,
                            transitionNamespace: navigationTransitionNamespace
                        )
                    case .popularTV:
                        DiscoverMediaGridView(
                            title: "Popular TV",
                            items: vm.popularTV,
                            transitionNamespace: navigationTransitionNamespace
                        )
                    case .upcoming:
                        DiscoverMediaGridView(
                            title: "Upcoming",
                            items: vm.upcomingMovies,
                            transitionNamespace: navigationTransitionNamespace
                        )
                    case .collections:
                        CollectionsView(apiClient: apiClient)
                    }
                }
            }
            .navigationDestination(for: SeerrCollection.self) { collection in
                CollectionDetailView(collection: collection, apiClient: apiClient)
            }
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
                    MediaSliderView(
                        title: "Trending",
                        icon: "flame",
                        items: vm.trending,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .trending
                    )
                    MediaSliderView(
                        title: "Popular Movies",
                        icon: "film",
                        items: vm.popularMovies,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .popularMovies
                    )
                    MediaSliderView(
                        title: "Popular TV",
                        icon: "tv",
                        items: vm.popularTV,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .popularTV
                    )
                    MediaSliderView(
                        title: "Upcoming",
                        icon: "calendar",
                        items: vm.upcomingMovies,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .upcoming
                    )
                    if !vm.collections.isEmpty {
                        collectionSlider(vm.collections)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    @ViewBuilder
    private func collectionSlider(_ collections: [SeerrCollection]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: DiscoverSectionDestination.collections) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(.secondary)
                    Text("Collections")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(collections) { collection in
                        NavigationLink(value: collection) {
                            collectionCard(collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .horizontalSoftEdges()
        }
    }

    private func collectionCard(_ collection: SeerrCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterImage(url: collection.posterURL, width: 140, height: 210, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name ?? "Unknown Collection")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                if let count = collection.parts?.count, count > 0 {
                    Text("\(count) \(count == 1 ? "movie" : "movies")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, alignment: .leading)
            .padding(.top, 6)
            .padding(.horizontal, 2)
        }
    }
}
