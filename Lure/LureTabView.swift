import SwiftUI

struct LureTabView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(LureRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
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
        }
        .tabViewStyle(.sidebarAdaptable)
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
