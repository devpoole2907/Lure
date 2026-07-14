import SwiftUI
#if DEBUG && os(iOS)
import SwiftData
#endif

struct LureTabView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(LureRouter.self) private var router

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

            Tab("Library", systemImage: "checkmark.circle", value: LureTab.library) {
                LibraryView(apiClient: apiClient)
            }

            Tab("Requests", systemImage: "arrow.down.circle", value: LureTab.requests) {
                RequestListView(apiClient: apiClient, currentUser: currentUser)
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
        .tabViewStyle(.sidebarAdaptable)
        #if os(macOS)
        .tabViewSidebarBottomBar {
            MacSidebarProfileButton(currentUser: currentUser) {
                router.isProfilePresented = true
            }
        }
        .sheet(isPresented: $router.isProfilePresented) {
            MacUserProfileSheet(
                apiClient: apiClient,
                currentUser: currentUser,
                onLogout: onLogout
            )
        }
        #endif
        .task {
            await SearchViewModel.preloadBrowseGenres(using: apiClient)
        }
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
