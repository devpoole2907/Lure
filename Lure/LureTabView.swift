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
                DiscoverView(apiClient: apiClient)
            }

            Tab(value: LureTab.search, role: .search) {
                SearchView(apiClient: apiClient)
            }

            Tab("Library", systemImage: "checkmark.circle", value: LureTab.library) {
                LibraryView(apiClient: apiClient)
            }

            Tab("Requests", systemImage: "arrow.down.circle", value: LureTab.requests) {
                RequestListView(apiClient: apiClient, currentUser: currentUser)
            }

            Tab("More", systemImage: "ellipsis", value: LureTab.more) {
                MoreView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            await SearchViewModel.preloadBrowseGenres(using: apiClient)
        }
    }
}
