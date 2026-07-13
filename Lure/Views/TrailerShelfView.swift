import SwiftUI

struct TrailerShelfView: View {
    let videos: [SeerrRelatedVideo]

    private let horizontalBleed: CGFloat = 16

    var body: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Trailers", systemImage: "play.rectangle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(videos.enumerated()), id: \.offset) { _, video in
                            TrailerCard(video: video)
                        }
                    }
                    .padding(.horizontal, horizontalBleed)
                }
                .padding(.horizontal, -horizontalBleed)
                .horizontalSoftEdges()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TrailerCard: View {
    let video: SeerrRelatedVideo

    private static let cardWidth: CGFloat = 320
    private static let cardHeight: CGFloat = 300
    private static let cornerRadius: CGFloat = 24

    var body: some View {
        Button {
            if let url = video.youtubeURL {
                openExternalURL(url)
            }
        } label: {
            cardVisual
        }
        .buttonStyle(.plain)
        .disabled(video.youtubeURL == nil)
        .accessibilityLabel(video.name ?? "Trailer")
        .accessibilityHint("Opens the trailer on YouTube.")
    }

    private var cardVisual: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(url: video.youtubeThumbnailURL, contentMode: .fill) {
                trailerPlaceholder
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)

            Rectangle()
                .fill(.black.opacity(0.18))

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: .black.opacity(0.35), location: 0.48),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)

                Text("TRAILER")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)

                Text(trailerTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Label("YouTube", systemImage: "play.rectangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.top, 2)
            }
            .padding(22)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
        }
    }

    private var trailerPlaceholder: some View {
        ZStack {
            Rectangle()
                .fill(.linearGradient(
                    colors: [.black, .red.opacity(0.36), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 46, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var trailerTitle: String {
        let title = video.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return "Trailer" }
        return title
    }
}
