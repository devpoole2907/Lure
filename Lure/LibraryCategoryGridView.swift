import SwiftUI

/// The Apple-TV-app-style library categories surfaced as sidebar entries on
/// macOS. The grid view below is platform-agnostic so these categories can
/// replace the existing Library layout on other platforms later.
enum LibraryCategory: String, CaseIterable {
    case recentlyAdded
    case movies
    case tvShows

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .movies: "Movies"
        case .tvShows: "TV Shows"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: "clock"
        case .movies: "film"
        case .tvShows: "tv"
        }
    }

    @MainActor
    func items(from viewModel: LibraryViewModel) -> [LibraryItem] {
        switch self {
        case .recentlyAdded:
            // recentlyAdded is the whole library sorted by add date — cap it
            // so this reads as "what's new" rather than everything you own.
            Array(viewModel.recentlyAdded.prefix(60))
        case .movies:
            viewModel.movies
        case .tvShows:
            viewModel.tvShows
        }
    }

}

/// Sort field applied on top of a category's default ordering; nil means the
/// category's natural order (title for Movies/TV, date added for Recently
/// Added).
enum LibrarySortField: Hashable {
    case title
    case year
}

enum LibrarySortDirection: Hashable {
    case ascending
    case descending
}

/// Poster grid for a single library category. Content-only — the host
/// provides the NavigationStack and MediaDestination handling, so it can sit
/// inside any tab's stack on any platform.
struct LibraryCategoryGridView: View {
    let title: String
    let items: [LibraryItem]
    let apiClient: SeerrAPIClient
    var isLoading: Bool = false

    @State private var searchText = ""
    @State private var sortField: LibrarySortField?
    @State private var sortDirection: LibrarySortDirection = .ascending
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    private var displayedItems: [LibraryItem] {
        var result = items
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(query) }
        }
        guard let sortField else { return result }
        let ascending = sortDirection == .ascending
        switch sortField {
        case .title:
            result.sort {
                ascending
                    ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
            }
        case .year:
            // Unknown years sink to the end regardless of direction; ties
            // fall back to title order.
            result.sort { lhs, rhs in
                switch (yearValue(lhs), yearValue(rhs)) {
                case let (l?, r?) where l != r:
                    return ascending ? l < r : l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.title < rhs.title
                }
            }
        }
        return result
    }

    private func yearValue(_ item: LibraryItem) -> Int? {
        item.year.flatMap { Int($0.prefix(4)) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView {
                        Label(title, systemImage: "rectangle.stack")
                    } description: {
                        Text("Nothing in your library here yet.")
                    }
                }
            } else if displayedItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: ThreeColumnMediaGrid.columns(for: proxy.size.width),
                            spacing: ThreeColumnMediaGrid.rowSpacing
                        ) {
                            ForEach(displayedItems) { item in
                                NavigationLink(value: MediaDestination(
                                    mediaType: item.mediaType,
                                    tmdbId: item.tmdbId,
                                    title: item.title,
                                    posterURL: item.posterURL
                                )) {
                                    LibraryPosterCell(item: item)
                                }
                                #if os(tvOS)
                                .buttonStyle(TVPosterFocusButtonStyle())
                                #else
                                .buttonStyle(.plain)
                                #endif
                                .contextMenu {
                                    LibraryItemRequestContextMenu(
                                        item: item,
                                        apiClient: apiClient,
                                        notificationCenter: notificationCenter,
                                        requestsCoordinator: requestsCoordinator
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, ThreeColumnMediaGrid.horizontalPadding)
                        .padding(.vertical, 12)
                    }
                    #if os(macOS)
                    .scrollEdgeEffectStyle(.soft, for: .all)
                    #endif
                }
            }
        }
        .lureNavigationTitle(title)
        #if !os(tvOS)
        // iOS 26 brought navigationSubtitle over from macOS; it renders the
        // live (search-filtered) count under the large title.
        .navigationSubtitle("\(displayedItems.count) items")
        #endif
        .searchable(text: $searchText, prompt: "Search \(title)")
        .toolbar {
            ToolbarItem {
                Menu {
                    // A labeled Picker inside a menu already renders as its
                    // own submenu on macOS — wrapping it in Menu("Sort")
                    // produced a Sort → Sort double-nesting.
                    Picker("Sort", selection: $sortField) {
                        Text("Title").tag(LibrarySortField?.some(.title))
                        Text("Year").tag(LibrarySortField?.some(.year))
                    }
                    Picker("By", selection: $sortDirection) {
                        Text("Ascending").tag(LibrarySortDirection.ascending)
                        Text("Descending").tag(LibrarySortDirection.descending)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
}

#if os(macOS)
/// One sidebar Library entry: its own NavigationStack (router-owned path per
/// category, so pushed detail views don't bleed across entries) around the
/// shared grid, with the same MediaDestination handling as LibraryView.
struct MacLibraryCategoryView: View {
    let category: LibraryCategory
    let apiClient: SeerrAPIClient
    let viewModel: LibraryViewModel?

    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(LureRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: path($router)) {
            Group {
                if let viewModel {
                    LibraryCategoryGridView(
                        title: category.title,
                        items: category.items(from: viewModel),
                        apiClient: apiClient,
                        isLoading: viewModel.isLoading
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: MediaDestination.self) { destination in
                switch destination.mediaType {
                case "movie":
                    MovieDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        jellyfinService: jellyfinService,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                case "tv":
                    TVDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        jellyfinService: jellyfinService,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                default:
                    Text("Unsupported media type: \(destination.mediaType)")
                }
            }
            .refreshable {
                await viewModel?.refresh()
            }
        }
    }

    private func path(_ router: Bindable<LureRouter>) -> Binding<NavigationPath> {
        switch category {
        case .recentlyAdded: router.libraryRecentlyAddedPath
        case .movies: router.libraryMoviesPath
        case .tvShows: router.libraryTVShowsPath
        }
    }
}
#endif
