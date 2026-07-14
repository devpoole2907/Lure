import SwiftUI
#if os(tvOS)
import UIKit
#endif

struct TrailerShelfView: View {
    let videos: [SeerrRelatedVideo]

    #if os(tvOS)
    private let horizontalBleed: CGFloat = 0
    private let cardSpacing: CGFloat = 32
    #else
    private let horizontalBleed: CGFloat = 16
    private let cardSpacing: CGFloat = 14
    #endif

    var body: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trailers")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: cardSpacing) {
                        ForEach(Array(videos.enumerated()), id: \.offset) { _, video in
                            TrailerCard(video: video)
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
    let video: SeerrRelatedVideo

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
        .disabled(video.youtubeURL == nil)
        .accessibilityLabel(video.name ?? "Trailer")
        #if os(tvOS)
        .accessibilityHint("Plays the trailer in the YouTube app.")
        #else
        .accessibilityHint("Opens the trailer on YouTube.")
        #endif
    }

    private func playTrailer() {
        #if os(tvOS)
        // tvOS has no browser (and no WKWebView), so youtube.com links go
        // nowhere. Deep-link straight into the YouTube app instead.
        guard let key = video.key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let appURL = URL(string: "youtube://watch?v=\(key)") else { return }
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
        if let url = video.youtubeURL {
            openExternalURL(url)
        }
        #endif
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

                Label("YouTube", systemImage: "play.rectangle.fill")
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
        let title = video.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return "Trailer" }
        return title
    }
}
