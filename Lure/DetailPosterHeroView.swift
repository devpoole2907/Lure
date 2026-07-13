import SwiftUI

/// Reports the global maxY of the hero's big title so the detail view can reveal
/// the navigation-bar title only once the hero title has scrolled up behind the bar.
struct HeroTitleBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct DetailPosterHeroView: View {
    let title: String
    let artworkURL: URL?
    let logoURL: URL?
    let mediaTypeLabel: String
    let year: String?
    let rating: Double?
    let badges: [DetailBadge]
    let genres: [String]
    let verticalOffset: CGFloat
    let primaryAction: DetailPosterHeroAction

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                heroImage
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .accessibilityHidden(true)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.20), location: 0.45),
                        .init(color: .black.opacity(0.65), location: 0.72),
                        .init(color: .black.opacity(0.92), location: 0.88),
                        .init(color: .black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                bottomContent
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }
        .frame(height: carouselHeight + verticalOffset)
        .offset(y: -verticalOffset)
    }

    private var heroImage: some View {
        CachedRemoteImage(url: artworkURL, contentMode: .fill) {
            ZStack {
                Rectangle()
                    .fill(.linearGradient(
                        colors: [.black, .indigo.opacity(0.45), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
    }

    private var bottomContent: some View {
        VStack(spacing: 10) {
            HeroTitleArtworkView(
                title: title,
                logoURL: logoURL,
                maxWidth: 430,
                maxLogoHeight: 142,
                reportTitleBottom: true
            )

            metadataRow

            Button(action: primaryAction.action) {
                Label(primaryAction.title, systemImage: primaryAction.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!primaryAction.isEnabled)
            .opacity(primaryAction.isEnabled ? 1 : 0.55)
            .padding(.top, 4)

            if !badges.isEmpty || !genres.isEmpty {
                VStack(spacing: 8) {
                    DetailBadgeSection(badges: badges)

                    if !genres.isEmpty {
                        DetailGenreChips(genres: genres)
                    }
                }
                .padding(.top, 2)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 520)
        .padding(.horizontal, 28)
        .padding(.bottom, 58)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(mediaTypeLabel)
            if let year {
                Text("·")
                Text(year)
            }
            if let rating, rating > 0 {
                Text("·")
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .combine)
    }

    private var carouselHeight: CGFloat {
        horizontalSizeClass == .compact ? 610 : 740
    }
}

#if DEBUG
#Preview("Detail Poster Hero") {
    DetailPosterHeroView(
        title: SeerrTVDetail.previewShow.displayTitle,
        artworkURL: nil,
        logoURL: nil,
        mediaTypeLabel: "TV Show",
        year: SeerrTVDetail.previewShow.year,
        rating: SeerrTVDetail.previewShow.voteAverage,
        badges: [],
        genres: [],
        verticalOffset: 0,
        primaryAction: DetailPosterHeroAction(title: "Play", systemImage: "play.fill") {}
    )
    .background(Color.black)
}
#endif
