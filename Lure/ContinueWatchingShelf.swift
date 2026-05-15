import SwiftUI

struct ContinueWatchingShelf: View {
    let items: [JellyfinItem]
    let jellyfinClient: JellyfinAPIClient?
    let onPlay: (JellyfinItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Watching")
                .font(.title3.bold())
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items, id: \.id) { item in
                        Button { onPlay(item) } label: {
                            ContinueWatchingCard(item: item, jellyfinClient: jellyfinClient)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct ContinueWatchingCard: View {
    let item: JellyfinItem
    let jellyfinClient: JellyfinAPIClient?

    private static let cardWidth: CGFloat = 240
    private static let cardHeight: CGFloat = 135 // 16:9

    private var thumbURL: URL? {
        guard let client = jellyfinClient else { return nil }
        // Episodes: prefer series thumb for context, fall back to item primary
        if let seriesId = item.seriesId {
            return client.thumbImageURL(itemId: seriesId)
        }
        guard let id = item.id else { return nil }
        return client.thumbImageURL(itemId: id)
    }

    private var progress: Double {
        guard let ticks = item.userData?.playbackPositionTicks,
              let total = item.runTimeTicks, total > 0 else { return 0 }
        return min(1.0, Double(ticks) / Double(total))
    }

    private var displayTitle: String {
        item.seriesName ?? item.name ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                PosterImage(
                    url: thumbURL,
                    width: Self.cardWidth,
                    height: Self.cardHeight,
                    cornerRadius: 10
                )

                // Bottom gradient + progress
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                    if progress > 0 {
                        ProgressView(value: progress)
                            .tint(.red)
                            .scaleEffect(x: 1, y: 0.7)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                            .background(.black.opacity(0.6))
                    }
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            Text(displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: Self.cardWidth, alignment: .leading)

            if let ep = item.episodeLabel {
                Text(ep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.cardWidth, alignment: .leading)
            }
        }
        .frame(width: Self.cardWidth)
    }
}
