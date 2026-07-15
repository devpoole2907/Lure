import SwiftUI

struct SearchView: View {
    let apiClient: SeerrAPIClient

    @State private var vm: SearchViewModel
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedFilter: SearchMediaFilter = .all
    @State private var showClearConfirmation = false
    @State private var scope: SearchScope = .discover
    @State private var libraryItems: [LibraryItem] = []
    @State private var libraryItemsLoaded = false
    @State private var libraryLoadTask: Task<Void, Never>?
    @Namespace private var genreTransitionNamespace
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator
    @Environment(LureRouter.self) private var router

    @State private var jellyfinResults: [JellyfinItem] = []
    @State private var jellyfinSearchTask: Task<Void, Never>?
    @State private var isJellyfinSearching = false
    @FocusState private var isMacSearchFocused: Bool
    @FocusState private var isSearchFieldFocused: Bool

    @AppStorage("lure.search.recents") private var recentsStorage: String = "[]"

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
        self._vm = State(initialValue: SearchViewModel(apiClient: apiClient))
    }

    var body: some View {
        #if os(macOS)
        searchLifecycle(searchNavigation)
        #elseif os(tvOS)
        searchLifecycle(
            searchNavigation
                .safeAreaPadding(.top, 36)
                .searchable(
                    text: $searchText,
                    prompt: scope == .library ? "Your library" : "Movies, TV shows..."
                )
        )
        #else
        searchLifecycle(
            searchNavigation
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    placement: .automatic,
                    prompt: scope == .library ? "Your library" : "Movies, TV shows..."
                )
                .searchFocused($isSearchFieldFocused)
        )
        #endif
    }

    private var searchNavigation: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.searchPath) {
            Group {
                #if os(macOS)
                VStack(spacing: 0) {
                    macSearchHeader
                    content
                }
                #else
                VStack(spacing: 0) {
                    if isSearchPresented && searchText.isEmpty {
                        Picker("Scope", selection: $scope) {
                            Text("Discover").tag(SearchScope.discover)
                            Text("Library").tag(SearchScope.library)
                        }
                        .pickerStyle(.segmented)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .padding(.horizontal, 48)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    content
                }
                #endif
            }
            #if os(tvOS)
            .navigationTitle("")
            #else
            .navigationTitle("Search")
            #endif
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearchPresented)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchText.isEmpty)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: scope)
            .navigationDestination(for: MediaDestination.self) { dest in
                switch dest.mediaType {
                case "movie":
                    MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                case "tv":
                    TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                case "person":
                    EmptyView()
                default:
                    EmptyView()
                }
            }
            .navigationDestination(for: SearchGenreDestination.self) { destination in
                SearchGenreResultsView(destination: destination, apiClient: apiClient)
#if os(iOS) || os(visionOS)
                    .navigationTransition(.zoom(sourceID: destination, in: genreTransitionNamespace))
#endif
                    .id(destination)
            }
        }
    }

    private func searchLifecycle<Content: View>(_ view: Content) -> some View {
        view
        .onSubmit(of: .search) {
            recordRecent(searchText)
        }
        .onChange(of: scope) { _, newScope in
            #if os(iOS) || os(visionOS)
            // Tapping the scope picker resigns the search field's focus,
            // and on iPadOS's Tab(role: .search) presentation an empty,
            // unfocused field gets auto-collapsed back to the tab icon
            // instead of just losing the keyboard. Reassert presentation
            // and focus so switching scope doesn't kick the user out of
            // search entirely.
            isSearchPresented = true
            isSearchFieldFocused = true
            #endif
            if newScope == .library {
                if !jellyfinService.hasCredentials,
                   !libraryItemsLoaded,
                   libraryLoadTask == nil {
                    libraryLoadTask = Task {
                        await loadLibraryItems()
                        libraryLoadTask = nil
                    }
                }
                triggerJellyfinSearch(for: searchText)
            } else {
                libraryLoadTask?.cancel()
                libraryLoadTask = nil
                jellyfinSearchTask?.cancel()
                jellyfinSearchTask = nil
            }
        }
        .onChange(of: searchText) { _, newValue in
            if scope == .discover {
                vm.query = newValue
                Task { await vm.search() }
            } else if scope == .library {
                triggerJellyfinSearch(for: newValue)
            }
        }
        .task {
            await vm.loadBrowseGenresIfNeeded()
        }
    }

    #if os(macOS)
    private var macSearchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body)
                .foregroundStyle(.secondary)

            TextField("Shows, Movies and More", text: $searchText)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .focused($isMacSearchFocused)
                .onSubmit {
                    recordRecent(searchText)
                }

            if !searchText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    isMacSearchFocused ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12),
                    lineWidth: isMacSearchFocused ? 2 : 1
                )
        }
        .padding(.top, 12)
        .padding(.bottom, searchText.isEmpty ? 20 : 22)
        .frame(maxWidth: .infinity)
    }
    #endif

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if isSearchPresented && searchText.isEmpty {
            recentSearchesContent
        } else if searchText.isEmpty {
            browseGenresContent
        } else if scope == .library {
            librarySearchResultsContent
        } else {
            searchResultsContent
        }
    }

    // MARK: - Library Search

    private var filteredLibraryItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return libraryItems.filter {
            $0.title.lowercased().contains(query)
        }
    }

    @ViewBuilder
    private var librarySearchResultsContent: some View {
        if jellyfinService.hasCredentials {
            jellyfinSearchResultsContent
        } else {
            seerrLibrarySearchResultsContent
        }
    }

    @ViewBuilder
    private var seerrLibrarySearchResultsContent: some View {
        if !libraryItemsLoaded {
            ProgressView("Loading library...")
        } else if filteredLibraryItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(filteredLibraryItems) { item in
                    NavigationLink(value: MediaDestination(
                        mediaType: item.mediaType,
                        tmdbId: item.tmdbId,
                        title: item.title,
                        posterURL: item.posterURL
                    )) {
                        MediaListRow(item: item)
                    }
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
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var jellyfinSearchResultsContent: some View {
        if isJellyfinSearching && jellyfinResults.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if jellyfinResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List {
                ForEach(jellyfinResults, id: \.id) { item in
                    jellyfinResultRow(item)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func jellyfinResultRow(_ item: JellyfinItem) -> some View {
        if let libraryItem = libraryItem(for: item) {
            NavigationLink(value: MediaDestination(
                mediaType: libraryItem.mediaType,
                tmdbId: libraryItem.tmdbId,
                title: libraryItem.title,
                posterURL: libraryItem.posterURL
            )) {
                MediaListRow(item: libraryItem)
            }
            .contextMenu {
                LibraryItemRequestContextMenu(
                    item: libraryItem,
                    apiClient: apiClient,
                    notificationCenter: notificationCenter,
                    requestsCoordinator: requestsCoordinator
                )
            }
        } else {
            // Episodes and items without a TMDB provider ID can't be routed
            // through MediaListRow/MediaDestination; keep the plain label.
            jellyfinResultLabel(item)
        }
    }

    /// Convert a Jellyfin search result into the same LibraryItem the Seerr
    /// library path renders, so both scopes share MediaListRow with a poster.
    /// Mirrors LibraryViewModel.loadFromJellyfin().
    private func libraryItem(for item: JellyfinItem) -> LibraryItem? {
        guard let tmdbId = item.tmdbId, let name = item.name, let type = item.type else { return nil }
        let mediaType: String
        switch type.lowercased() {
        case "series": mediaType = "tv"
        case "movie": mediaType = "movie"
        default: return nil
        }
        return LibraryItem(
            mediaType: mediaType,
            tmdbId: tmdbId,
            title: name,
            year: item.productionYear.map(String.init),
            voteAverage: item.communityRating,
            posterURL: item.id.flatMap { jellyfinService.client?.primaryImageURL(itemId: $0) },
            isAvailable: true,
            addedAt: nil
        )
    }

    private func jellyfinResultLabel(_ item: JellyfinItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name ?? "Untitled")
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(item.type?.lowercased() == "series" ? "TV Show" : "Movie")
                if let year = item.productionYear {
                    Text("·")
                    Text(String(year))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func triggerJellyfinSearch(for query: String) {
        guard scope == .library, jellyfinService.hasCredentials else { return }
        jellyfinSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            jellyfinResults = []
            isJellyfinSearching = false
            return
        }
        isJellyfinSearching = true
        jellyfinSearchTask = Task { [jellyfinService] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let client = jellyfinService.client else { return }
            let results = (try? await client.searchItems(term: trimmed)) ?? []
            guard !Task.isCancelled else { return }
            jellyfinResults = results
            isJellyfinSearching = false
        }
    }

    private func loadLibraryItems() async {
        guard libraryLoadTask != nil else { return }
        do {
            var allEntries: [SeerrMediaEntry] = []
            let pageSize = 250

            for filter in ["available", "partial"] {
                var skip = 0
                while true {
                    let response = try await apiClient.getMedia(filter: filter, take: pageSize, skip: skip)
                    allEntries.append(contentsOf: response.results)
                    if response.results.count < pageSize { break }
                    skip += pageSize
                }
            }

            libraryItems = allEntries.compactMap { $0.toLibraryItem() }
            libraryItemsLoaded = true
        } catch {
            // Don't set libraryItemsLoaded on failure
            print("Failed to load library items: \(error.localizedDescription)")
        }
    }

    // MARK: - Recent Searches

    @ViewBuilder
    private var recentSearchesContent: some View {
        let recents = loadRecents()
        if recents.isEmpty {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Find movies and TV shows to request.")
            }
        } else {
            List {
                Section {
                    ForEach(recents, id: \.self) { term in
                        Button {
                            searchText = term
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                Text(term)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeRecent(term)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                    }
                } header: {
                    HStack {
                        Text("Recently Searched")
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Clear", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .font(.subheadline)
                        .textCase(nil)
                    }
                }
            }
#if os(iOS) || os(visionOS)
            .listStyle(.insetGrouped)
#endif
            .alert("Clear Recent Searches?", isPresented: $showClearConfirmation) {
                Button("Clear All", role: .destructive) { clearRecents() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all recently searched terms.")
            }
        }
    }

    // MARK: - Browse Genres

    @ViewBuilder
    private var browseGenresContent: some View {
        if vm.isLoadingBrowseGenres && vm.browseGenres.isEmpty {
            VStack {
                Spacer()
                ProgressView("Loading genres...")
                Spacer()
            }
        } else if vm.browseGenres.isEmpty {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Find movies and TV shows to request.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(
                        columns: browseGridColumns,
                        spacing: browseGridSpacing
                    ) {
                        ForEach(vm.browseGenres) { genre in
                            let destination = SearchGenreDestination(genre: genre)
                            NavigationLink(value: destination) {
                                SearchGenreTileView(genre: genre)
                                    #if os(iOS) || os(visionOS)
                                    .matchedTransitionSource(id: destination, in: genreTransitionNamespace)
                                    #endif
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, browseGridHorizontalPadding)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
#if os(macOS)
            .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        }
    }

    private var browseGridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 150, maximum: 230), spacing: 22)]
        #elseif os(tvOS)
        // tvOS: 4 columns gives each tile ~420pt wide — large and focusable
        [
            GridItem(.flexible(), spacing: 36),
            GridItem(.flexible(), spacing: 36),
            GridItem(.flexible(), spacing: 36),
            GridItem(.flexible(), spacing: 36)
        ]
        #else
        // Adaptive rather than a fixed 2 columns so the tile count scales
        // with the window: iPhone widths still resolve to 2 columns, while
        // iPad (full screen, Split View, Stage Manager) gets more columns of
        // roughly iPhone-sized cards instead of two super-wide ones.
        [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 14)]
        #endif
    }

    private var browseGridSpacing: CGFloat {
        #if os(macOS)
        22
        #elseif os(tvOS)
        36
        #else
        14
        #endif
    }

    private var browseGridHorizontalPadding: CGFloat {
        #if os(macOS)
        44
        #elseif os(tvOS)
        90
        #else
        18
        #endif
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
        #if os(macOS)
        macSearchResultsContent
        #else
        VStack(spacing: 0) {
            filterPills(
                all: vm.results.count,
                movies: vm.results.filter { $0.mediaType == "movie" }.count,
                tv: vm.results.filter { $0.mediaType == "tv" }.count,
                people: vm.results.filter { $0.mediaType == "person" }.count
            )

            if vm.isSearching && vm.results.isEmpty {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            } else if vm.results.isEmpty && vm.hasSearched {
                ContentUnavailableView.search(text: searchText)
            } else if filteredResults.isEmpty && vm.hasSearched {
                ContentUnavailableView.search(text: searchText)
            } else if !filteredResults.isEmpty {
                List {
                    ForEach(filteredResults) { item in
                        NavigationLink(value: MediaDestination(mediaType: item.mediaType, tmdbId: item.tmdbId, title: item.title, posterURL: item.posterURL)) {
                            MediaListRow(item: item)
                        }
                        .contextMenu {
                            if item.hasRequestContextActions {
                                MediaRequestContextMenu(
                                    mediaType: item.mediaType,
                                    tmdbId: item.tmdbId,
                                    title: item.title,
                                    mediaInfo: item.mediaInfo,
                                    isKnownAvailable: item.mediaInfo?.isAvailable == true,
                                    apiClient: apiClient,
                                    notificationCenter: notificationCenter,
                                    requestsCoordinator: requestsCoordinator
                                )
                            }
                        }
                    }
                    if vm.currentPage < vm.totalPages && selectedFilter != .people {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await vm.loadMore() }
                    }
                }
                .listStyle(.plain)
            }
        }
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macSearchResultsContent: some View {
        if vm.isSearching && vm.results.isEmpty {
            Spacer()
            ProgressView("Searching...")
            Spacer()
        } else if vm.results.isEmpty && vm.hasSearched {
            ContentUnavailableView.search(text: searchText)
        } else if macVisibleResults.isEmpty && vm.hasSearched {
            ContentUnavailableView.search(text: searchText)
        } else if !macVisibleResults.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if !macTopResults.isEmpty {
                        macSearchTopResultsSection(macTopResults)
                    }

                    if !macMovieResults.isEmpty {
                        macSearchPosterSection("Movies", items: macMovieResults)
                    }

                    if !macTVResults.isEmpty {
                        macSearchPosterSection("TV Shows", items: macTVResults)
                    }

                    if vm.currentPage < vm.totalPages {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .task { await vm.loadMore() }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 54)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    private var macVisibleResults: [SeerrMediaItem] {
        vm.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
    }

    private var macTopResults: [SeerrMediaItem] {
        Array(macVisibleResults.prefix(12))
    }

    private var macMovieResults: [SeerrMediaItem] {
        macVisibleResults.filter { $0.mediaType == "movie" }
    }

    private var macTVResults: [SeerrMediaItem] {
        macVisibleResults.filter { $0.mediaType == "tv" }
    }

    private var macSearchHorizontalPadding: CGFloat { 44 }

    private func macSearchTopResultsSection(_ items: [SeerrMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top Results")
                .font(.title3.bold())
                .padding(.horizontal, macSearchHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(items) { item in
                        macSearchNavigationLink(for: item) {
                            MacSearchTopResultCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, macSearchHorizontalPadding)
            }
        }
    }

    private func macSearchPosterSection(_ title: String, items: [SeerrMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, macSearchHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(items) { item in
                        macSearchNavigationLink(for: item) {
                            MacSearchPosterResultCard(item: item)
                        }
                    }
                }
                .padding(.horizontal, macSearchHorizontalPadding)
            }
        }
    }

    private func macSearchNavigationLink<Content: View>(
        for item: SeerrMediaItem,
        @ViewBuilder label: () -> Content
    ) -> some View {
        NavigationLink(value: MediaDestination(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            posterURL: item.posterURL
        )) {
            label()
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.hasRequestContextActions {
                MediaRequestContextMenu(
                    mediaType: item.mediaType,
                    tmdbId: item.tmdbId,
                    title: item.title,
                    mediaInfo: item.mediaInfo,
                    isKnownAvailable: item.mediaInfo?.isAvailable == true,
                    apiClient: apiClient,
                    notificationCenter: notificationCenter,
                    requestsCoordinator: requestsCoordinator
                )
            }
        }
    }
    #endif

    private var filteredResults: [SeerrMediaItem] {
        switch selectedFilter {
        case .all:    return vm.results
        case .movies: return vm.results.filter { $0.mediaType == "movie" }
        case .tv:     return vm.results.filter { $0.mediaType == "tv" }
        case .people: return vm.results.filter { $0.mediaType == "person" }
        }
    }

    // MARK: - Filter Pills

    @ViewBuilder
    private func filterPills(all: Int, movies: Int, tv: Int, people: Int) -> some View {
        let pills: [(SearchMediaFilter, String, String, Int)] = [
            (.all,    "All",    "square.stack.3d.up", all),
            (.movies, "Movies", "film",               movies),
            (.tv,     "TV",     "tv",                 tv),
            (.people, "People", "person",             people)
        ]

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pills, id: \.0) { kind, title, icon, count in
                    filterPill(kind: kind, title: title, icon: icon, count: count)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .horizontalSoftEdges()
    }

    private func filterPill(kind: SearchMediaFilter, title: String, icon: String, count: Int) -> some View {
        let isSelected = selectedFilter == kind
        return Button {
            selectedFilter = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial))
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recents Persistence

    private func loadRecents() -> [String] {
        guard let data = recentsStorage.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    private func saveRecents(_ arr: [String]) {
        if let data = try? JSONEncoder().encode(arr),
           let str = String(data: data, encoding: .utf8) {
            recentsStorage = str
        }
    }

    private func recordRecent(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var arr = loadRecents()
        arr.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        arr.insert(trimmed, at: 0)
        if arr.count > 20 { arr = Array(arr.prefix(20)) }
        saveRecents(arr)
    }

    private func removeRecent(_ term: String) {
        var arr = loadRecents()
        arr.removeAll { $0 == term }
        saveRecents(arr)
    }

    private func clearRecents() {
        saveRecents([])
    }
}

struct SearchGenreDestination: Hashable {
    let genreID: Int
    let mediaType: String
    let title: String

    init(genre: SearchGenreTile) {
        genreID = genre.genreID
        mediaType = genre.mediaType
        title = genre.name
    }
}

private enum SearchMediaFilter: Hashable {
    case all, movies, tv, people
}

#if os(macOS)
private struct MacSearchTopResultCard: View {
    let item: SeerrMediaItem

    var body: some View {
        HStack(spacing: 14) {
            PosterImage(url: item.posterURL, width: 54, height: 78, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.macSearchSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 380, height: 96)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct MacSearchPosterResultCard: View {
    let item: SeerrMediaItem

    var body: some View {
        PosterImage(url: item.posterURL, width: 178, height: 267, cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .accessibilityLabel(item.title)
    }
}

private extension SeerrMediaItem {
    var macSearchSubtitle: String {
        [macSearchTypeLabel, year]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var macSearchTypeLabel: String? {
        switch mediaType {
        case "movie":
            "Movie"
        case "tv":
            "TV Show"
        default:
            nil
        }
    }
}
#endif

private struct SearchGenreTileView: View {
    let genre: SearchGenreTile
    private let cornerRadius = LureDesign.CornerRadius.card

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.regularMaterial)
            .overlay {
                GeometryReader { proxy in
                    artwork
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.06),
                                Color.black.opacity(0.26),
                                Color.black.opacity(0.92)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(alignment: .bottomLeading) {
                tileLabel
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.08))
            }
            .frame(maxWidth: .infinity)
            #if os(macOS)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            #elseif os(tvOS)
            .frame(height: 180)
            #else
            .frame(height: 112)
            #endif
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .compositingGroup()
    }

    private var tileLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(genre.name)
                .font(tileTitleFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 2)

            HStack(spacing: 4) {
                Image(systemName: genre.mediaTypeIcon)
                Text(genre.mediaTypeLabel)
            }
                .font(tileSubtitleFont)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.32), radius: 5, y: 1)
        }
        .padding(tilePadding)
    }

    private var tileTitleFont: Font {
        #if os(tvOS)
        .headline.weight(.semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }

    private var tileSubtitleFont: Font {
        #if os(tvOS)
        .subheadline.weight(.semibold)
        #else
        .caption2.weight(.semibold)
        #endif
    }

    private var tilePadding: CGFloat {
        #if os(tvOS)
        20
        #else
        14
        #endif
    }

    @ViewBuilder
    private var artwork: some View {
        if let artworkURL = genre.artworkURL {
            AsyncImage(
                url: artworkURL,
                transaction: Transaction(animation: .easeInOut(duration: 0.25))
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                case .failure, .empty:
                    fallbackArtwork
                @unknown default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: genre.gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}

private extension SearchGenreTile {
    var mediaTypeLabel: String {
        mediaType == "movie" ? "Movies" : "TV"
    }

    var mediaTypeIcon: String {
        mediaType == "movie" ? "film.fill" : "tv.fill"
    }

    var gradientColors: [Color] {
        let palettes: [[Color]] = mediaType == "movie"
            ? [
                [.orange, .red, .brown],
                [.pink, .red, .orange],
                [.blue, .indigo, .black],
                [.mint, .teal, .blue]
            ]
            : [
                [.cyan, .blue, .indigo],
                [.teal, .mint, .blue],
                [.purple, .indigo, .black],
                [.green, .teal, .indigo]
            ]
        return palettes[abs(genreID) % palettes.count]
    }
}

#if DEBUG && os(macOS)
#Preview("Mac Search Results") {
    MacSearchResultsPreviewSurface()
        .frame(width: 1280, height: 760)
}

private struct MacSearchResultsPreviewSurface: View {
    private let movies = [
        Self.movie(11, "Star Wars: A New Hope", "1977", "/6FfCtAuVAW8XJjZ7eWeLibRLWTw.jpg"),
        Self.movie(1891, "The Empire Strikes Back", "1980", "/nNAeTmF4CtdSgMDplXTDPOpYzsX.jpg"),
        Self.movie(1892, "Return of the Jedi", "1983", "/jQYlydvHm3kUix1f8prMucrplhm.jpg"),
        Self.movie(181808, "Star Wars: The Last Jedi", "2017", "/kOVEVeg59E0wsnXmF9nrh6OmWII.jpg"),
        Self.movie(140607, "Star Wars: The Force Awakens", "2015", "/wqnLdwVXoBjKibFRR5U3y0aDUhs.jpg"),
        Self.movie(1895, "Revenge of the Sith", "2005", "/xfSAoBEm9MNBjmlNcDYLvLSMlnq.jpg")
    ]

    private let shows = [
        Self.tv(202250, "Monarch: Legacy of Monsters", "2023", "/uwrQHMnXD2DA1rvaMZk4pavZ3CY.jpg"),
        Self.tv(93740, "Foundation", "2021", "/A1fXGFxDifQzj08OlaGTVcnXHyd.jpg"),
        Self.tv(114479, "WondLa", "2024", "/9x3kByu6fWKka48w9nMJFV1Pqku.jpg")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                previewSearchField

                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        previewTopResults
                        previewPosterSection("Movies", items: movies)
                        previewPosterSection("TV Shows", items: shows)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 54)
                }
                .scrollEdgeEffectStyle(.soft, for: .all)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var previewSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("star wars")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: 420)
        .frame(height: 40)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.12))
        }
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity)
    }

    private var previewTopResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top Results")
                .font(.title3.bold())
                .padding(.horizontal, 44)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 22) {
                    ForEach(Array((movies + shows).prefix(6)), id: \.id) { item in
                        MacSearchTopResultCard(item: item)
                    }
                }
                .padding(.horizontal, 44)
            }
        }
    }

    private func previewPosterSection(_ title: String, items: [SeerrMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 44)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 24) {
                    ForEach(items) { item in
                        MacSearchPosterResultCard(item: item)
                    }
                }
                .padding(.horizontal, 44)
            }
        }
    }

    private static func movie(_ id: Int, _ title: String, _ year: String, _ posterPath: String) -> SeerrMediaItem {
        .movie(SeerrMovieResult(
            id: id,
            mediaType: "movie",
            popularity: nil,
            posterPath: posterPath,
            backdropPath: nil,
            voteCount: nil,
            voteAverage: nil,
            genreIds: nil,
            overview: nil,
            originalLanguage: nil,
            title: title,
            originalTitle: title,
            releaseDate: "\(year)-01-01",
            adult: false,
            mediaInfo: nil
        ))
    }

    private static func tv(_ id: Int, _ title: String, _ year: String, _ posterPath: String) -> SeerrMediaItem {
        .tv(SeerrTvResult(
            id: id,
            mediaType: "tv",
            popularity: nil,
            posterPath: posterPath,
            backdropPath: nil,
            voteCount: nil,
            voteAverage: nil,
            genreIds: nil,
            overview: nil,
            originalLanguage: nil,
            name: title,
            originalName: title,
            originCountry: nil,
            firstAirDate: "\(year)-01-01",
            mediaInfo: nil
        ))
    }
}
#endif

enum SearchScope: Hashable {
    case discover
    case library
}

#if DEBUG && !os(macOS)
// Note: the macOS variant already has its own #Preview above.
#Preview("Search — Browse Genres (tvOS/iOS)") {
    let jellyfinService = PreviewSupport.jellyfinService
    NavigationStack {
        SearchView(apiClient: PreviewSupport.apiClient)
    }
    .environment(jellyfinService)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif

#if DEBUG && os(tvOS)
/// Standalone tvOS preview that shows the genre grid with sample data
/// without requiring a network call.
#Preview("Search — Genre Grid (tvOS, static)") {
    NavigationStack {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 36),
                    GridItem(.flexible(), spacing: 36),
                    GridItem(.flexible(), spacing: 36),
                    GridItem(.flexible(), spacing: 36)
                ],
                spacing: 36
            ) {
                ForEach(PreviewSupport.sampleGenreTiles) { genre in
                    SearchGenreTileView(genre: genre)
                        .frame(height: 180)
                }
            }
            .padding(.horizontal, 90)
            .padding(.top, 60)
            .padding(.bottom, 60)
        }
        .lureNavigationTitle("Browse")
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
#endif

#if DEBUG && os(iOS)
#Preview("Search — Browse Genres (iPad)", traits: .fixedLayout(width: 1024, height: 1366)) {
    SearchView(apiClient: PreviewSupport.apiClient)
        .environment(PreviewSupport.jellyfinService)
        .environment(PreviewSupport.notificationCenter)
        .environment(PreviewSupport.requestsCoordinator)
}
#endif
