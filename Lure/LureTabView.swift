import SwiftUI

struct LureTabView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @State private var selectedTab: LureTab = .discover

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Discover", systemImage: "film", value: LureTab.discover) {
                DiscoverView(apiClient: apiClient)
            }

            Tab(value: LureTab.search, role: .search) {
                SearchView(apiClient: apiClient)
            }

            Tab("Requests", systemImage: "arrow.down.circle", value: LureTab.requests) {
                RequestListView(apiClient: apiClient, currentUser: currentUser)
            }

            Tab("Profile", systemImage: "person.crop.circle", value: LureTab.profile) {
                UserProfileView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .task {
            await SearchViewModel.preloadBrowseGenres(using: apiClient)
        }
    }
}

private enum LureTab: Hashable {
    case discover, search, requests, profile
}
