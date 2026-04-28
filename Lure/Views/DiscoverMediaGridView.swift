import SwiftUI

struct DiscoverMediaGridView: View {
    let title: String
    let items: [SeerrMediaItem]
    var transitionNamespace: Namespace.ID? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        GeometryReader { proxy in
            let posterWidth = max(92, floor((proxy.size.width - 32 - 24) / 3))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items) { item in
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
