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

    /// macOS windows resize, so the column count scales with the container
    /// (targeting ~190pt posters) instead of pinning to 3 giant columns.
    /// iOS keeps 3 and tvOS keeps 6 — their widths are effectively fixed.
    static func columnCount(for containerWidth: CGFloat) -> Int {
        #if os(macOS)
        let usable = containerWidth - horizontalPadding * 2
        guard usable > 0 else { return columnCount }
        return max(3, Int((usable + columnSpacing) / (190 + columnSpacing)))
        #else
        return columnCount
        #endif
    }

    static func columns(for containerWidth: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing, alignment: .top),
            count: columnCount(for: containerWidth)
        )
    }

    static func posterWidth(for containerWidth: CGFloat) -> CGFloat {
        let count = columnCount(for: containerWidth)
        return max(
            92,
            floor(
                (containerWidth - horizontalPadding * 2 - columnSpacing * CGFloat(count - 1))
                    / CGFloat(count)
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
            let columnCount = ThreeColumnMediaGrid.columnCount(for: proxy.size.width)

            ScrollView {
                LazyVGrid(columns: ThreeColumnMediaGrid.columns(for: proxy.size.width), spacing: ThreeColumnMediaGrid.rowSpacing) {
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
                            .gridCellColumns(columnCount)
                            .padding(.vertical, 8)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(columnCount)
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
            #if os(macOS) && DEBUG
            if ProcessInfo.processInfo.environment["LURE_NAV_PROBE"] == "1" {
                print("LURE_NAV_PROBE: grid '\(title)' appeared")
            }
            #endif
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

#if DEBUG && os(iOS)
#Preview("Discover Media Grid — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        DiscoverMediaGridView(
            title: "Trending",
            initialItems: PreviewSupport.sampleItems,
            apiClient: PreviewSupport.apiClient
        )
        .navigationTitle("Trending")
    }
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif
