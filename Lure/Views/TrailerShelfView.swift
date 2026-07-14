import SwiftUI
#if os(tvOS)
import UIKit
#endif

struct TrailerShelfView: View {
    let localTrailers: [JellyfinLocalTrailer]
    let youtubeVideos: [SeerrRelatedVideo]
    let fallbackArtworkURL: URL?

    private var items: [TrailerShelfItem] {
        TrailerShelfItem.preferred(
            localTrailers: localTrailers,
            youtubeVideos: youtubeVideos,
            fallbackArtworkURL: fallbackArtworkURL
        )
    }

    #if os(tvOS)
    private let horizontalBleed: CGFloat = 0
    private let cardSpacing: CGFloat = 32
    #else
    private let horizontalBleed: CGFloat = 16
    private let cardSpacing: CGFloat = 14
    #endif

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trailers")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: cardSpacing) {
                        ForEach(items) { item in
                            TrailerCard(item: item)
                        }
                    }
                    .padding(.horizontal, horizontalBleed)
                    #if os(tvOS)
                    .padding(.vertical, 24)
                    #endif
                }
                #if os(tvOS)
                .scrollClipDisabled()
                #else
                .padding(.horizontal, -horizontalBleed)
                #endif
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TrailerCard: View {
    let item: TrailerShelfItem

    @Environment(PlayerCoordinator.self) private var playerCoordinator

    #if os(tvOS)
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    private static let cardWidth: CGFloat = 360
    private static let cardHeight: CGFloat = 202
    private static let cornerRadius: CGFloat = 20
    #else
    private static let cardWidth: CGFloat = 214
    private static let cardHeight: CGFloat = 200
    private static let cornerRadius: CGFloat = 18
    #endif

    var body: some View {
        Button {
            playTrailer()
        } label: {
            cardVisual
        }
        #if os(tvOS)
        .buttonStyle(TVPosterFocusButtonStyle(scale: 1.06))
        #else
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel(item.title)
        #if os(tvOS)
        .accessibilityHint(accessibilityHint)
        #else
        .accessibilityHint(accessibilityHint)
        #endif
    }

    private func playTrailer() {
        switch item.destination {
        case .jellyfin(let itemId):
            playerCoordinator.present(
                itemId: itemId,
                title: item.title,
                mediaType: "trailer"
            )

        case .youtube(let videoId):
        #if os(tvOS)
        // tvOS has no browser (and no WKWebView), so youtube.com links go
        // nowhere. Deep-link straight into the YouTube app instead.
        guard let appURL = URL(string: "youtube://watch?v=\(videoId)") else { return }
        UIApplication.shared.open(appURL, options: [:]) { success in
            guard !success else { return }
            Task { @MainActor in
                notificationCenter.show(LureBannerItem(
                    title: "YouTube App Needed",
                    message: "Trailers play in the YouTube app. Install it from the App Store to watch this one.",
                    style: .info
                ))
            }
        }
        #else
        if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            openExternalURL(url)
        }
        #endif
        }
    }

    private var cardVisual: some View {
        ZStack(alignment: .bottomLeading) {
            CachedRemoteImage(url: item.thumbnailURL, contentMode: .fill) {
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

            VStack(alignment: .leading, spacing: 6) {
                Spacer(minLength: 0)

                Text("TRAILER")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)

                Text(trailerTitle)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)

                Label(item.sourceLabel, systemImage: item.sourceIcon)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.84))
            }
            .padding(16)
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
                .font(.system(size: 34, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.78))
        }
    }

    private var trailerTitle: String {
        item.title
    }

    private var accessibilityHint: String {
        switch item.destination {
        case .jellyfin:
            "Plays the trailer in Lure."
        case .youtube:
            #if os(tvOS)
            "Plays the trailer in the YouTube app."
            #else
            "Opens the trailer on YouTube."
            #endif
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Trailer Shelf — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    TrailerShelfView(
        localTrailers: [
            JellyfinLocalTrailer(
                id: "preview-trailer",
                title: "Official Trailer",
                thumbnailURL: nil
            )
        ],
        youtubeVideos: [],
        fallbackArtworkURL: nil
    )
    .padding()
    .environment(PreviewSupport.playerCoordinator)
    .environment(PreviewSupport.notificationCenter)
}
#endif
