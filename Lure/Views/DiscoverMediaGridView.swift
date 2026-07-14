import SwiftUI

enum ThreeColumnMediaGrid {
    #if os(tvOS)
    // tvOS: 6 columns of shelf-sized posters. The container already sits inside
    // the ~90pt safe area, so no extra horizontal padding is added.
    static let horizontalPadding: CGFloat = 0
    static let columnSpacing: CGFloat = 40
    static let rowSpacing: CGFloat = 48
    static let columnCount = 6
    #else
    static let horizontalPadding: CGFloat = 16
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 20
    static let columnCount = 3
    #endif

    static let columns = Array(
        repeating: GridItem(.flexible(), spacing: columnSpacing, alignment: .top),
        count: columnCount
    )

    static func posterWidth(for containerWidth: CGFloat) -> CGFloat {
        max(
            92,
            floor(
                (containerWidth - horizontalPadding * 2 - columnSpacing * CGFloat(columnCount - 1))
                    / CGFloat(columnCount)
            )
        )
    }
}

struct DiscoverMediaGridView: View {
    let title: String
    let initialItems: [SeerrMediaItem]
    var apiClient: SeerrAPIClient? = nil
    var transitionNamespace: Namespace.ID? = nil
    var loadPage: (@Sendable (Int) async throws -> [SeerrMediaItem])? = nil

    @State private var additionalItems: [SeerrMediaItem] = []
    @State private var currentPage = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var loadError: Error?
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    private var allItems: [SeerrMediaItem] {
        initialItems + additionalItems
    }

    var body: some View {
        GeometryReader { proxy in
            let posterWidth = ThreeColumnMediaGrid.posterWidth(for: proxy.size.width)

            ScrollView {
                LazyVGrid(columns: ThreeColumnMediaGrid.columns, spacing: ThreeColumnMediaGrid.rowSpacing) {
                    ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                        let destination = MediaDestination(
                            mediaType: item.mediaType,
                            tmdbId: item.tmdbId,
                            title: item.title,
                            posterURL: item.posterURL,
                            sourceID: navigationSourceID(for: item, index: index)
                        )

                        gridLink(for: item, destination: destination, posterWidth: posterWidth)
                    }

                    if hasMore {
                        if loadError != nil {
                            VStack(spacing: 8) {
                                Text("Failed to load more items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("Retry") {
                                    Task {
                                        loadError = nil
                                        await loadNextPage()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(ThreeColumnMediaGrid.columnCount)
                            .padding(.vertical, 8)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(ThreeColumnMediaGrid.columnCount)
                                .task { await loadNextPage() }
                        }
                    }
                }
                .padding(.horizontal, ThreeColumnMediaGrid.horizontalPadding)
                .padding(.vertical, 12)
            }
#if os(macOS)
            .scrollEdgeEffectStyle(.soft, for: .all)
#endif
#if os(tvOS)
            // Focused cards scale up; don't clip them at the scroll edges.
            .scrollClipDisabled()
#endif
        }
        .lureNavigationTitle(title)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task {
            hasMore = loadPage != nil && !initialItems.isEmpty
        }
    }

    private func loadNextPage() async {
        guard !isLoadingMore, hasMore, let loadPage else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = currentPage + 1
        do {
            let newItems = try await loadPage(nextPage)
            loadError = nil
            if newItems.isEmpty {
                hasMore = false
            } else {
                additionalItems.append(contentsOf: newItems)
                currentPage = nextPage
            }
        } catch {
            loadError = error
        }
    }

    private func navigationSourceID(for item: SeerrMediaItem, index: Int) -> String {
        "\(title)-grid-\(index)-\(item.id)"
    }

    @ViewBuilder
    private func gridLink(for item: SeerrMediaItem, destination: MediaDestination, posterWidth: CGFloat) -> some View {
        let link = NavigationLink(value: destination) {
            if let transitionNamespace {
                TitleCardView(
                    item: item,
                    posterWidth: posterWidth,
                    posterHeight: posterWidth * 1.5
                )
                .matchedTransitionSource(id: destination, in: transitionNamespace)
            } else {
                TitleCardView(
                    item: item,
                    posterWidth: posterWidth,
                    posterHeight: posterWidth * 1.5
                )
            }
        }
        #if os(tvOS)
        .buttonStyle(TVPosterFocusButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif

        if let apiClient, item.hasRequestContextActions {
            link.contextMenu {
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
        } else {
            link
        }
    }
}
