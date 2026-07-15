import SwiftUI

struct DiscoverView: View {
    let apiClient: SeerrAPIClient
    @State private var viewModel: DiscoverViewModel?
    @State private var heroActiveIndex = 0
    @State private var heroScrollTargetID: String?
    @State private var heroVerticalOffset: CGFloat = 0
    @State private var isHeroCarouselVisible = true
    @State private var heroActiveImageURL: URL?
    @Namespace private var navigationTransitionNamespace
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(PlayerCoordinator.self) private var playerCoordinator
    @Environment(LureRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.discoverPath) {
            Group {
                if let vm = viewModel {
                    discoverContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            #if os(tvOS)
            .navigationTitle("")
            #else
            .navigationTitle("Discover")
            #endif
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
            #if os(macOS) && DEBUG
            // Temporary nav probe (LURE_NAV_PROBE=1): tab-switch then push.
            .task {
                guard ProcessInfo.processInfo.environment["LURE_NAV_PROBE"] == "1" else { return }
                try? await Task.sleep(for: .seconds(5))
                router.selectedTab = .search
                try? await Task.sleep(for: .seconds(2))
                router.selectedTab = .discover
                try? await Task.sleep(for: .seconds(2))
                router.discoverPath.append(DiscoverSectionDestination.trending)
                print("LURE_NAV_PROBE: appended .trending, path count=\(router.discoverPath.count)")
            }
            #endif
            .onChange(of: router.pendingJellyfinItemId) { _, jellyfinId in
                guard let jellyfinId, !jellyfinId.isEmpty else { return }
                router.pendingJellyfinItemId = nil
                Task {
                    await navigateToJellyfinItem(jellyfinId: jellyfinId)
                }
            }
#if os(iOS) || os(visionOS)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarBackground(.hidden, for: .navigationBar)
#endif
        }
    }

    private func activeHeroBackdropURL(vm: DiscoverViewModel) -> URL? {
        let heroes = DiscoverHeroCarouselView.heroItems(from: vm.featuredItems)
        guard !heroes.isEmpty else { return nil }
        let index = min(max(heroActiveIndex, 0), heroes.count - 1)
        return DiscoverHeroCarouselView.ambientBackdropURL(for: heroes[index])
    }

    /// Same blur treatment as `artBackground(url:)` in MovieDetailView/
    /// TVDetailView, but loaded through AmbientBackdropImage: unlike
    /// AsyncImage it keeps the previous image up until the next one is
    /// decoded, so the background doesn't pulse to a placeholder every time
    /// the carousel advances.
    private func artBackground(url: URL?) -> some View {
        AmbientBackdropImage(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1.4)
            .blur(radius: 60)
            .saturation(1.6)
            .overlay(Color.black.opacity(0.55))
            .ignoresSafeArea()
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
                // The carousel must stay outside the LazyVStack: when the
                // lazy container reclaimed it off-screen, the recreated
                // ScrollView snapped to item 0 and clobbered the saved
                // scroll position before it could be restored. A plain
                // VStack keeps it alive (its 8 images are preloaded anyway)
                // so its position is frozen while scrolled away; the
                // sections below keep their laziness.
                VStack(alignment: .leading, spacing: 24) {
                    DiscoverHeroCarouselView(
                        items: vm.featuredItems,
                        activeIndex: $heroActiveIndex,
                        scrollTargetID: $heroScrollTargetID,
                        transitionNamespace: navigationTransitionNamespace,
                        verticalOffset: heroVerticalOffset,
                        isActive: router.discoverPath.isEmpty && isHeroCarouselVisible,
                        onActiveImageChange: { heroActiveImageURL = $0 }
                    )
                    .onScrollVisibilityChange(threshold: 0.05) { visible in
                        isHeroCarouselVisible = visible
                    }

                    LazyVStack(alignment: .leading, spacing: 24) {
                    // Gated on live credentials, not just cached items, so the
                    // shelf disappears immediately when Jellyfin is signed out.
                    if jellyfinService.hasCredentials, !vm.continueWatching.isEmpty {
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
                        headerValue: .trending,
                        extendsBeyondParentPadding: false
                    )
                    MediaSliderView(
                        title: "Popular Movies",
                        icon: "film",
                        items: vm.popularMovies,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .popularMovies,
                        extendsBeyondParentPadding: false
                    )
                    MediaSliderView(
                        title: "Popular TV",
                        icon: "tv",
                        items: vm.popularTV,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .popularTV,
                        extendsBeyondParentPadding: false
                    )
                    MediaSliderView(
                        title: "New Releases",
                        icon: "sparkles.tv",
                        items: vm.newReleases,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .newReleases,
                        extendsBeyondParentPadding: false
                    )
                    MediaSliderView(
                        title: "Upcoming",
                        icon: "calendar",
                        items: vm.upcomingMovies,
                        apiClient: apiClient,
                        transitionNamespace: navigationTransitionNamespace,
                        headerValue: .upcoming,
                        extendsBeyondParentPadding: false
                    )
                    if !vm.collections.isEmpty {
                        collectionSlider(vm.collections)
                    }
                    }
                }
                .padding(.bottom)
            }
            .ignoresSafeArea(edges: .top)
#if os(iOS)
            .scrollEdgeEffectStyle(.soft, for: .all)
#endif
#if os(macOS)
            .scrollEdgeEffectStyle(.soft, for: .all)
#endif
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y + $0.contentInsets.top
            } action: { _, newValue in
                heroVerticalOffset = max(-newValue, 0)
            }
            // Same ambient treatment as the detail views: the active hero
            // item's artwork, blurred behind the entire page, paired with a
            // forced dark scheme so the sections below read correctly on it.
            // The hero's masked bottom edge phases into this backdrop.
            .background { artBackground(url: heroActiveImageURL ?? activeHeroBackdropURL(vm: vm)) }
            .environment(\.colorScheme, .dark)
        }
    }

    /// Resolves a Jellyfin item ID (from a Top Shelf / deep-link URL) to a
    /// `MediaDestination` and pushes it onto the discover navigation stack.
    /// Falls back gracefully when the item cannot be resolved (no network,
    /// no credentials, missing TMDB id).
    private func navigateToJellyfinItem(jellyfinId: String) async {
        guard let client = jellyfinService.client else { return }
        do {
            let item = try await client.getItem(itemId: jellyfinId)
            let destination: MediaDestination?
            if let tmdbId = item.tmdbId {
                let mediaType: String
                switch item.type?.lowercased() {
                case "movie": mediaType = "movie"
                default: mediaType = "tv"
                }
                destination = MediaDestination(
                    mediaType: mediaType,
                    tmdbId: tmdbId,
                    title: item.name,
                    posterURL: client.primaryImageURL(itemId: jellyfinId)
                )
            } else if let seriesId = item.seriesId {
                // Episode without direct TMDB id — use series instead
                let series = try await client.getItem(itemId: seriesId)
                if let tmdbId = series.tmdbId {
                    destination = MediaDestination(
                        mediaType: "tv",
                        tmdbId: tmdbId,
                        title: series.name,
                        posterURL: client.primaryImageURL(itemId: seriesId)
                    )
                } else {
                    destination = nil
                }
            } else {
                destination = nil
            }
            if let destination {
                router.discoverPath.append(destination)
            }
        } catch {
            // Silently fail — the user is still on the Discover tab
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
        let visibleCollections = collections.filter { $0.id != nil }

        VStack(alignment: .leading, spacing: 12) {
            #if os(tvOS)
            // tvOS: plain, non-focusable header — a focusable NavigationLink header
            // renders as a giant white plate when focused; browse deep via Search.
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(.secondary)
                Text("Collections")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #else
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
            #endif

            ScrollView(.horizontal, showsIndicators: false) {
                #if os(tvOS)
                // Same card metrics/margins as the other poster shelves, with a
                // virtual wrap-around so the row loops seamlessly.
                let virtualCount = visibleCollections.count * 20
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(0..<virtualCount, id: \.self) { virtualIndex in
                        let collection = visibleCollections[virtualIndex % visibleCollections.count]
                        NavigationLink(value: collection) {
                            collectionCard(collection)
                        }
                        .buttonStyle(TVPosterFocusButtonStyle())
                    }
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 30)
                #else
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(visibleCollections, id: \.id) { collection in
                        NavigationLink(value: collection) {
                            collectionCard(collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                #endif
            }
            #if os(tvOS)
            // Full-bleed row: 90pt leading margin from the absolute screen edge,
            // trailing scrolls to the edge, no soft fade mask, no focus clipping.
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollClipDisabled()
            .ignoresSafeArea(edges: .horizontal)
            #else
            .horizontalSoftEdges()
            #endif
        }
    }

    private var collectionPosterWidth: CGFloat {
        #if os(tvOS)
        260
        #else
        140
        #endif
    }

    private var collectionPosterHeight: CGFloat {
        #if os(tvOS)
        390
        #else
        210
        #endif
    }

    private func collectionCard(_ collection: SeerrCollection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterImage(
                url: collection.posterURL,
                width: collectionPosterWidth,
                height: collectionPosterHeight,
                cornerRadius: collectionPosterWidth * 0.086
            )
            .posterFocusHighlight(cornerRadius: collectionPosterWidth * 0.086)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name ?? "Unknown Collection")
                    #if os(tvOS)
                    .font(.callout.weight(.medium))
                    #else
                    .font(.caption)
                    .fontWeight(.medium)
                    #endif
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                if let count = collection.parts?.count, count > 0 {
                    Text("\(count) \(count == 1 ? "movie" : "movies")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: collectionPosterWidth, alignment: .leading)
            .padding(.top, collectionCaptionTopPadding)
            .padding(.horizontal, 2)
        }
    }

    /// tvOS needs extra clearance so the focused poster's hover-effect
    /// scale-up doesn't overlap the caption.
    private var collectionCaptionTopPadding: CGFloat {
        #if os(tvOS)
        22
        #else
        6
        #endif
    }
}

/// Backing image for the ambient blurred page background. Holds onto the
/// previously decoded image while the next URL loads, so URL changes (the
/// carousel advancing) crossfade image-to-image instead of dipping through
/// a placeholder the way AsyncImage does.
private struct AmbientBackdropImage: View {
    let url: URL?

    #if canImport(UIKit)
    @State private var image: UIImage?
    #else
    @State private var image: NSImage?
    #endif

    var body: some View {
        Group {
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                #endif
            } else {
                Rectangle().fill(Color.indigo.opacity(0.4))
            }
        }
        .task(id: url) {
            guard let url,
                  let data = try? await LureImageCache.shared.imageData(for: url) else { return }
            let decoded = await Task.detached(priority: .userInitiated) {
                #if canImport(UIKit)
                UIImage(data: data)
                #else
                NSImage(data: data)
                #endif
            }.value
            guard let decoded, !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                image = decoded
            }
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Discover — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    DiscoverView(apiClient: PreviewSupport.apiClient)
        .environment(PreviewSupport.router(tab: .discover))
        .environment(PreviewSupport.jellyfinService)
        .environment(PreviewSupport.notificationCenter)
        .environment(PreviewSupport.playerCoordinator)
        .environment(PreviewSupport.requestsCoordinator)
}
#endif
