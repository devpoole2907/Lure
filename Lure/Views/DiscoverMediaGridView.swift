import SwiftUI

struct DiscoverMediaGridView: View {
    let title: String
    let initialItems: [SeerrMediaItem]
    var transitionNamespace: Namespace.ID? = nil
    var loadPage: (@Sendable (Int) async throws -> [SeerrMediaItem])? = nil

    @State private var additionalItems: [SeerrMediaItem] = []
    @State private var currentPage = 1
    @State private var hasMore = false
    @State private var isLoadingMore = false

    private var allItems: [SeerrMediaItem] {
        initialItems + additionalItems
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3)

    var body: some View {
        GeometryReader { proxy in
            let posterWidth = max(92, floor((proxy.size.width - 32 - 24) / 3))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(allItems) { item in
                        let destination = MediaDestination(
                            mediaType: item.mediaType,
                            tmdbId: item.tmdbId,
                            title: item.title,
                            posterURL: item.posterURL
                        )

                        NavigationLink(value: destination) {
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
                        .buttonStyle(.plain)
                    }

                    if hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(3)
                            .task { await loadNextPage() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(title)
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
            if newItems.isEmpty {
                hasMore = false
            } else {
                additionalItems.append(contentsOf: newItems)
                currentPage = nextPage
            }
        } catch {
            hasMore = false
        }
    }
}
