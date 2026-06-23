import SwiftUI

struct DiscoverView: View {
    let apiClient: SeerrAPIClient
    @State private var viewModel: DiscoverViewModel?
    @State private var navigationPath = NavigationPath()
    @State private var heroActiveIndex = 0
    @State private var heroScrollTargetID: String?
    @State private var heroVerticalOffset: CGFloat = 0
    @Namespace private var navigationTransitionNamespace
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(PlayerCoordinator.self) private var playerCoordinator

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                            initialItems: vm.trending,
                            apiClient: apiClient,
                            transitionNamespace: navigationTransitionNamespace
                        ) { page in
                            let response = try await apiClient.getDiscoverTrending(page: page)
                            return response.results.map { $0.toMediaItem() }
                        }
                    case .popularMovies:
                        DiscoverMediaGridView(
                            title: "Popular Movies",
                            initialItems: vm.popularMovies,
                            apiClient: apiClient,
                            transitionNamespace: navigationTransitionNamespace
                        ) { page in
                            let response = try await apiClient.getDiscoverMovies(page: page, sortBy: "popularity.desc")
                            return response.results.map { $0.toMediaItem() }
                        }
                    case .popularTV:
                        DiscoverMediaGridView(
                            title: "Popular TV",
                            initialItems: vm.popularTV,
                            apiClient: apiClient,
                            transitionNamespace: navigationTransitionNamespace
                        ) { page in
                            let response = try await apiClient.getDiscoverTV(page: page, sortBy: "popularity.desc")
                            return response.results.map { $0.toMediaItem() }
                        }
                    case .newReleases:
                        DiscoverMediaGridView(
                            title: "New Releases",
                            initialItems: vm.newReleases,
                            apiClient: apiClient,
                            transitionNamespace: navigationTransitionNamespace
                        ) { page in
                            let response = try await apiClient.getDiscoverMoviesNewReleases(page: page)
                            return response.results.map { $0.toMediaItem() }
                        }
                    case .upcoming:
                        DiscoverMediaGridView(
                            title: "Upcoming",
                            initialItems: vm.upcomingMovies,
                            apiClient: apiClient,
                            transitionNamespace: navigationTransitionNamespace
                        ) { page in
                            let response = try await apiClient.getDiscoverMoviesUpcoming(page: page)
                            return response.results.map { $0.toMediaItem() }
                        }
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
                    MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
#if os(iOS) || os(visionOS)
                        .navigationTransition(.zoom(sourceID: dest, in: navigationTransitionNamespace))
#endif
                } else {
                    TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
#if os(iOS) || os(visionOS)
                        .navigationTransition(.zoom(sourceID: dest, in: navigationTransitionNamespace))
#endif
                }
            }
            .refreshable { await viewModel?.refresh() }
            .task {
                if viewModel == nil {
                    let vm = DiscoverViewModel(apiClient: apiClient, jellyfinService: jellyfinService)
                    viewModel = vm
                    await vm.loadInitialData()
                }
            }
#if os(iOS) || os(visionOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarBackground(.hidden, for: .navigationBar)
#endif
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
                    DiscoverHeroCarouselView(
                        items: vm.featuredItems,
                        activeIndex: $heroActiveIndex,
                        scrollTargetID: $heroScrollTargetID,
                        transitionNamespace: navigationTransitionNamespace,
                        verticalOffset: heroVerticalOffset,
                        isActive: navigationPath.isEmpty
                    )
                    if !vm.continueWatching.isEmpty {
                        ContinueWatchingShelf(
                            items: vm.continueWatching,
                            jellyfinClient: vm.jellyfinClient,
                            onPlay: playResumeItem,
                            onMarkWatched: markResumeItemWatched
                        )
                    }
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
                        title: "New Releases",
                        icon: "sparkles.tv",
                        items: vm.newReleases,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .newReleases
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
                .padding(.bottom)
            }
#if os(iOS)
            .scrollEdgeEffectStyle(.soft, for: .all)
#endif
            .ignoresSafeArea(edges: .top)
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, newValue in
                heroVerticalOffset = max(-newValue, 0)
            }
        }
    }

    private func playResumeItem(_ item: JellyfinItem) {
        playerCoordinator.presentResume(item)
    }

    private func markResumeItemWatched(_ item: JellyfinItem) async throws {
        try await viewModel?.markWatched(item)
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
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(collections.filter { $0.id != nil }, id: \.id) { collection in
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
