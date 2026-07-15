import SwiftUI

struct LibraryContentView: View {
    let viewModel: LibraryViewModel
    let apiClient: SeerrAPIClient

    @Environment(PlayerCoordinator.self) private var playerCoordinator
    @Environment(JellyfinService.self) private var jellyfinService

    var body: some View {
        if viewModel.isLoading && viewModel.items.isEmpty && viewModel.continueWatching.isEmpty {
            ProgressView("Loading Library…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.error, viewModel.items.isEmpty {
            ContentUnavailableView(
                "Library Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if viewModel.items.isEmpty && viewModel.continueWatching.isEmpty {
            ContentUnavailableView(
                "Nothing Available",
                systemImage: "film",
                description: Text("No media is currently available on your server.")
            )
        } else {
            libraryHome
        }
    }

    // MARK: - Library Home

    private var libraryHome: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                // Gated on live credentials, not just cached items, so the
                // shelf disappears immediately when Jellyfin is signed out.
                if jellyfinService.hasCredentials, !viewModel.continueWatching.isEmpty {
                    ContinueWatchingShelf(
                        items: viewModel.continueWatching,
                        jellyfinClient: viewModel.jellyfinClient,
                        onPlay: { playerCoordinator.presentResume($0) },
                        onMarkWatched: { try await viewModel.markWatched($0) }
                    )
                }

                LibraryShelfView(
                    category: .movies,
                    items: viewModel.movies,
                    apiClient: apiClient
                )

                LibraryShelfView(
                    category: .tvShows,
                    items: viewModel.tvShows,
                    apiClient: apiClient
                )

                LibraryShelfView(
                    category: .recentlyAdded,
                    items: Array(viewModel.recentlyAdded.prefix(20)),
                    apiClient: apiClient,
                    headerIsNavigable: false
                )
            }
            .padding(.vertical, 8)
        }
#if os(macOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
    }
}

// MARK: - Poster cell for the Recently Added grid

struct LibraryPosterCell: View {
    let item: LibraryItem

    /// tvOS needs extra clearance so the focused poster's hover-effect
    /// scale-up doesn't overlap the caption.
    private var captionSpacing: CGFloat {
        #if os(tvOS)
        22
        #else
        5
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: captionSpacing) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    GeometryReader { geo in
                        PosterImage(
                            url: item.posterURL,
                            width: geo.size.width,
                            height: geo.size.height,
                            cornerRadius: 8
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .posterFocusHighlight(cornerRadius: 8)

            Text(item.title)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Horizontal category shelf (Movies / TV Shows)

/// Discover-style horizontal poster shelf for a library category. The header
/// pushes the category's full grid (LibraryCategoryGridView) on iOS/macOS;
/// tvOS keeps a plain header — full-grid browsing there is still TBD.
struct LibraryShelfView: View {
    let category: LibraryCategory
    let items: [LibraryItem]
    let apiClient: SeerrAPIClient
    /// Recently Added passes false: its full content lives on the library
    /// home itself, so its header pushes nothing anywhere.
    var headerIsNavigable = true

    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    #if os(tvOS)
    private let cardWidth: CGFloat = 260
    private let cardSpacing: CGFloat = 40
    #else
    private let cardWidth: CGFloat = 140
    private let cardSpacing: CGFloat = 12
    #endif

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                #if os(tvOS)
                headerLabel(isNavigable: false)
                #else
                if headerIsNavigable {
                    NavigationLink(value: category) {
                        headerLabel(isNavigable: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    headerLabel(isNavigable: false)
                }
                #endif

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: cardSpacing) {
                        ForEach(items) { item in
                            NavigationLink(value: MediaDestination(
                                mediaType: item.mediaType,
                                tmdbId: item.tmdbId,
                                title: item.title,
                                posterURL: item.posterURL
                            )) {
                                LibraryPosterCell(item: item)
                                    .frame(width: cardWidth)
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
                    #if os(tvOS)
                    // Vertical headroom so the focus scale-up never clips.
                    .padding(.vertical, 30)
                    #endif
                }
                #if os(tvOS)
                .scrollClipDisabled()
                #endif
            }
        }
    }

    private func headerLabel(isNavigable: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: category.systemImage)
                .foregroundStyle(.secondary)
            Text(category.title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            if isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, ThreeColumnMediaGrid.horizontalPadding)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG && os(iOS)
#Preview("Library Content — Empty (iPad)", traits: .fixedLayout(width: 1024, height: 1366)) {
    let jellyfinService = PreviewSupport.jellyfinService
    let viewModel = LibraryViewModel(
        apiClient: PreviewSupport.apiClient,
        jellyfinService: jellyfinService
    )

    NavigationStack {
        LibraryContentView(
            viewModel: viewModel,
            apiClient: PreviewSupport.apiClient
        )
        .navigationTitle("Library")
    }
    .environment(PreviewSupport.playerCoordinator)
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif
