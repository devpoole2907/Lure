import SwiftUI

struct SearchView: View {
    let apiClient: SeerrAPIClient

    @State private var vm: SearchViewModel
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var selectedFilter: SearchMediaFilter = .all
    @State private var showClearConfirmation = false
    @Namespace private var genreTransitionNamespace

    @AppStorage("lure.search.recents") private var recentsStorage: String = "[]"

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
        self._vm = State(initialValue: SearchViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSearchPresented)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searchText.isEmpty)
                .navigationDestination(for: MediaDestination.self) { dest in
                    if dest.mediaType == "movie" {
                        MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                    } else {
                        TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                    }
                }
                .navigationDestination(for: SearchGenreDestination.self) { destination in
                    SearchGenreResultsView(destination: destination, apiClient: apiClient)
                        .navigationTransition(.zoom(sourceID: destination, in: genreTransitionNamespace))
                        .id(destination)
                }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .automatic,
            prompt: "Movies, TV shows..."
        )
        .onSubmit(of: .search) {
            recordRecent(searchText)
        }
        .onChange(of: searchText) { _, newValue in
            vm.query = newValue
            Task { await vm.search() }
        }
        .task {
            await vm.loadBrowseGenresIfNeeded()
        }
    }

    // MARK: - Content routing

    @ViewBuilder
    private var content: some View {
        if isSearchPresented && searchText.isEmpty {
            recentSearchesContent
        } else if searchText.isEmpty {
            browseGenresContent
        } else {
            searchResultsContent
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeRecent(term)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
            .listStyle(.insetGrouped)
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
                        columns: [
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14),
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(vm.browseGenres) { genre in
                            let destination = SearchGenreDestination(genre: genre)
                            NavigationLink(value: destination) {
                                SearchGenreTileView(genre: genre)
                                    .matchedTransitionSource(id: destination, in: genreTransitionNamespace)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private var searchResultsContent: some View {
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
            } else if !vm.results.isEmpty {
                List {
                    ForEach(filteredResults) { item in
                        NavigationLink(value: MediaDestination(mediaType: item.mediaType, tmdbId: item.tmdbId, title: item.title, posterURL: item.posterURL)) {
                            SearchResultRow(item: item)
                        }
                    }
                    if vm.currentPage < vm.totalPages {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await vm.loadMore() }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

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

struct SearchResultRow: View {
    let item: SeerrMediaItem

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: item.posterURL, width: 50, height: 75, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(searchDisplayType(for: item.mediaType))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())

                    if let year = item.year {
                        Text(year)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                StatusBadge(mediaInfo: item.mediaInfo)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func searchDisplayType(for mediaType: String) -> String {
        mediaType == "tv" ? "TV" : mediaType.capitalized
    }
}

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
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .compositingGroup()
    }

    private var tileLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(genre.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.38), radius: 6, y: 2)

            Label(genre.mediaTypeLabel, systemImage: genre.mediaTypeIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.32), radius: 5, y: 1)
        }
        .padding(14)
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
