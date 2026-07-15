import SwiftUI
#if os(macOS) || (DEBUG && os(iOS))
import SwiftData
#endif

struct LureTabView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(LureRouter.self) private var router
    #if os(macOS)
    // Shared across the sidebar's Library section entries so Recently
    // Added/Movies/TV Shows don't each refetch the whole library.
    @State private var libraryViewModel: LibraryViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(JellyfinService.self) private var jellyfinService
    #endif

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            #if os(macOS)
            Tab("Search", systemImage: "magnifyingglass", value: LureTab.search) {
                SearchView(apiClient: apiClient)
            }

            Tab("Discover", systemImage: "house", value: LureTab.discover) {
                DiscoverView(apiClient: apiClient)
            }

            Tab("Requests", systemImage: "arrow.down.circle", value: LureTab.requests) {
                RequestListView(apiClient: apiClient, currentUser: currentUser)
            }

            TabSection("Library") {
                Tab(LibraryCategory.recentlyAdded.title, systemImage: LibraryCategory.recentlyAdded.systemImage, value: LureTab.libraryRecentlyAdded) {
                    MacLibraryCategoryView(category: .recentlyAdded, apiClient: apiClient, viewModel: libraryViewModel)
                }

                Tab(LibraryCategory.movies.title, systemImage: LibraryCategory.movies.systemImage, value: LureTab.libraryMovies) {
                    MacLibraryCategoryView(category: .movies, apiClient: apiClient, viewModel: libraryViewModel)
                }

                Tab(LibraryCategory.tvShows.title, systemImage: LibraryCategory.tvShows.systemImage, value: LureTab.libraryTVShows) {
                    MacLibraryCategoryView(category: .tvShows, apiClient: apiClient, viewModel: libraryViewModel)
                }
            }
            #else
            Tab("Discover", systemImage: "film", value: LureTab.discover) {
                activeOnly(.discover, selection: router.selectedTab) {
                    DiscoverView(apiClient: apiClient)
                }
            }

            Tab(value: LureTab.search, role: .search) {
                activeOnly(.search, selection: router.selectedTab) {
                    SearchView(apiClient: apiClient)
                }
            }

            Tab("Library", systemImage: "checkmark.circle", value: LureTab.library) {
                activeOnly(.library, selection: router.selectedTab) {
                    LibraryView(apiClient: apiClient)
                }
            }

            Tab("Requests", systemImage: "arrow.down.circle", value: LureTab.requests) {
                activeOnly(.requests, selection: router.selectedTab) {
                    RequestListView(apiClient: apiClient, currentUser: currentUser)
                }
            }

            Tab("More", systemImage: "ellipsis", value: LureTab.more) {
                activeOnly(.more, selection: router.selectedTab) {
                    MoreView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
                }
            }
            #endif
        }
        #if os(macOS)
        // .sidebarAdaptable is what opts a TabView into the tab-bar/sidebar
        // dual mode (and its toggle button); only macOS wants that here, to
        // pair with the sidebar bottom bar below. iPadOS keeps the default
        // style so its floating tab bar has no way to become a sidebar.
        .tabViewStyle(.sidebarAdaptable)
        .tabViewSidebarBottomBar {
            MacSidebarProfileButton(currentUser: currentUser) {
                router.isProfilePresented = true
            }
        }
        .sheet(isPresented: $router.isProfilePresented) {
            UserProfileSheet(
                apiClient: apiClient,
                currentUser: currentUser,
                onLogout: onLogout
            )
        }
        #endif
        .task {
            await SearchViewModel.preloadBrowseGenres(using: apiClient)
        }
        #if os(macOS)
        .task {
            guard libraryViewModel == nil else { return }
            let viewModel = LibraryViewModel(
                apiClient: apiClient,
                jellyfinService: jellyfinService,
                modelContext: modelContext
            )
            libraryViewModel = viewModel
            await viewModel.load()
        }
        #endif
    }

    @ViewBuilder
    private func activeOnly<Content: View>(
        _ tab: LureTab,
        selection: LureTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        #if os(tvOS)
        if tab == selection {
            content()
        } else {
            Color.clear
        }
        #else
        content()
        #endif
    }
}

#if DEBUG
#Preview("Tab View — Discover") {
    let router = PreviewSupport.router(tab: .discover)
    let jellyfinService = PreviewSupport.jellyfinService
    LureTabView(
        apiClient: PreviewSupport.apiClient,
        currentUser: PreviewSupport.regularUser,
        onLogout: {}
    )
    .environment(router)
    .environment(jellyfinService)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.playerCoordinator)
    .environment(PreviewSupport.requestsCoordinator)
}

#Preview("Tab View — Search") {
    let router = PreviewSupport.router(tab: .search)
    let jellyfinService = PreviewSupport.jellyfinService
    LureTabView(
        apiClient: PreviewSupport.apiClient,
        currentUser: PreviewSupport.regularUser,
        onLogout: {}
    )
    .environment(router)
    .environment(jellyfinService)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.playerCoordinator)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif

#if DEBUG && os(iOS)
#Preview("Tab View — Discover (iPad)", traits: .fixedLayout(width: 1024, height: 1366)) {
    let router = PreviewSupport.router(tab: .discover)
    let jellyfinService = PreviewSupport.jellyfinService

    LureTabView(
        apiClient: PreviewSupport.apiClient,
        currentUser: PreviewSupport.regularUser,
        onLogout: {}
    )
    .environment(router)
    .environment(jellyfinService)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.playerCoordinator)
    .environment(PreviewSupport.requestsCoordinator)
    .modelContainer(OnboardingPreviewSupport.modelContainer)
}
#endif
