import SwiftUI

struct LibraryContentView: View {
    let viewModel: LibraryViewModel
    let apiClient: SeerrAPIClient

    @Environment(PlayerCoordinator.self) private var playerCoordinator
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

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
                categoryNavLinks

                if !viewModel.continueWatching.isEmpty {
                    ContinueWatchingShelf(
                        items: viewModel.continueWatching,
                        jellyfinClient: viewModel.jellyfinClient,
                        onPlay: { playerCoordinator.presentResume($0) },
                        onMarkWatched: { try await viewModel.markWatched($0) }
                    )
                }

                if !viewModel.recentlyAdded.isEmpty {
                    recentlyAddedSection
                }
            }
            .padding(.vertical, 8)
        }
#if os(macOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
    }

    // MARK: - Category Nav Links

    private var categoryNavLinks: some View {
        VStack(spacing: 0) {
            NavigationLink {
                MediaCategoryView(title: "Movies", items: viewModel.movies, apiClient: apiClient)
            } label: {
                navRowLabel(icon: "film", label: "Movies", color: .pink, count: viewModel.movies.count)
            }

            Divider().padding(.leading, 58)

            NavigationLink {
                MediaCategoryView(title: "TV Shows", items: viewModel.tvShows, apiClient: apiClient)
            } label: {
                navRowLabel(icon: "tv", label: "TV Shows", color: .blue, count: viewModel.tvShows.count)
            }
        }
        .background(Color.secondaryGroupedBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func navRowLabel(icon: String, label: String, color: Color, count: Int) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))

            Text(label)
                .foregroundStyle(.primary)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .contentShape(Rectangle())
    }

    // MARK: - Recently Added

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                MediaCategoryView(
                    title: "Recently Added",
                    items: viewModel.recentlyAdded,
                    apiClient: apiClient,
                    initialSortOrder: .added
                )
            } label: {
                HStack(spacing: 6) {
                    Text("Recently Added")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            let recentItems = Array(viewModel.recentlyAdded.prefix(12))
            LazyVGrid(
                columns: ThreeColumnMediaGrid.columns,
                spacing: ThreeColumnMediaGrid.rowSpacing
            ) {
                ForEach(recentItems) { item in
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
        }
    }
}

// MARK: - Poster cell for the Recently Added grid

struct LibraryPosterCell: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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

            Text(item.title)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
    }
}
