import SwiftUI

struct CollectionDetailView: View {
    let collection: SeerrCollection
    let apiClient: SeerrAPIClient

    @State private var fullCollection: SeerrCollection?
    @State private var isLoading = false
    @Namespace private var navigationTransitionNamespace
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    private var displayCollection: SeerrCollection { fullCollection ?? collection }

    var body: some View {
        Group {
            if isLoading && fullCollection == nil {
                loadingView
            } else {
                contentView
            }
        }
        .lureNavigationTitle(displayCollection.name ?? "Collection")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
#if os(iOS) || os(visionOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
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
        .task {
            guard fullCollection == nil else { return }
            // Only fetch full detail if parts are missing
            if collection.parts == nil, let id = collection.id {
                isLoading = true
                do {
                    fullCollection = try await apiClient.getCollectionDetail(collectionId: id)
                    isLoading = false
                } catch {
                    isLoading = false
                    // Handle error - collection remains incomplete
                }
            }
        }
        .background { artBackground }
    }

    private var loadingView: some View {
        VStack(spacing: 18) {
            PosterImage(url: collection.posterURL, width: 160, height: 240, cornerRadius: 16)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
            ProgressView("Loading...")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var artBackground: some View {
        AsyncImage(url: displayCollection.backdropURL ?? displayCollection.posterURL,
                   transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            default:
                Rectangle().fill(Color.indigo.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(1.4)
        .blur(radius: 60)
        .saturation(1.6)
        .overlay(Color.black.opacity(0.55))
        .ignoresSafeArea()
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                if let overview = displayCollection.overview, !overview.isEmpty {
                    overviewSection(overview)
                }
                if let parts = displayCollection.parts, !parts.isEmpty {
                    moviesSection(parts)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
#if os(macOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .environment(\.colorScheme, .dark)
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            PosterImage(url: displayCollection.posterURL, width: 160, height: 240, cornerRadius: 16)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

            VStack(spacing: 6) {
                Text(displayCollection.name ?? "Collection")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let count = displayCollection.parts?.count, count > 0 {
                    Text("\(count) \(count == 1 ? "movie" : "movies")")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About", systemImage: "text.alignleft")
                .font(.headline)
                .foregroundStyle(.white)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func moviesSection(_ parts: [SeerrMovieResult]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Movies", systemImage: "film.stack")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(parts) { movie in
                        let item = SeerrMediaItem.movie(movie)
                        let dest = MediaDestination(mediaType: "movie", tmdbId: movie.id, title: movie.displayTitle, posterURL: movie.posterURL)
                        NavigationLink(value: dest) {
                            TitleCardView(item: item)
#if os(iOS) || os(visionOS)
                                .matchedTransitionSource(id: dest, in: navigationTransitionNamespace)
#endif
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if item.hasRequestContextActions {
                                MediaRequestContextMenu(
                                    mediaType: "movie",
                                    tmdbId: movie.id,
                                    title: movie.displayTitle,
                                    mediaInfo: movie.mediaInfo,
                                    isKnownAvailable: movie.mediaInfo?.isAvailable == true,
                                    apiClient: apiClient,
                                    notificationCenter: notificationCenter,
                                    requestsCoordinator: requestsCoordinator
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .horizontalSoftEdges()
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension SeerrCollection: Hashable {
    static func == (lhs: SeerrCollection, rhs: SeerrCollection) -> Bool {
        if let lhsId = lhs.id, let rhsId = rhs.id {
            return lhsId == rhsId
        }
        return lhs.name == rhs.name &&
               lhs.overview == rhs.overview &&
               lhs.posterPath == rhs.posterPath &&
               lhs.backdropPath == rhs.backdropPath
    }
    func hash(into hasher: inout Hasher) {
        if let id = id {
            hasher.combine(id)
        } else {
            hasher.combine(name)
            hasher.combine(overview)
            hasher.combine(posterPath)
            hasher.combine(backdropPath)
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Collection Detail — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    let movies = PreviewSupport.sampleItems.compactMap { item -> SeerrMovieResult? in
        guard case .movie(let movie) = item else { return nil }
        return movie
    }
    let collection = SeerrCollection(
        id: 10,
        name: "Essential Cinema Collection",
        posterPath: nil,
        backdropPath: nil,
        overview: "A hand-picked collection of memorable films, gathered together for an easy movie night.",
        parts: movies
    )

    NavigationStack {
        CollectionDetailView(
            collection: collection,
            apiClient: PreviewSupport.apiClient
        )
    }
    .environment(PreviewSupport.jellyfinService)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif
