import SwiftUI

struct TVDetailPosterHeroView: View {
    let show: SeerrTVDetail
    let posterURL: URL?
    var verticalOffset: CGFloat = 0

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                heroImage
                    .frame(width: size.width, height: size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.3),
                        .black.opacity(0.86)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var heroImage: some View {
        CachedRemoteImage(url: posterURL, contentMode: .fill) {
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
            Text(show.displayTitle)
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.68)

            metadataRow

            Label("Details", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background(.white, in: Capsule())
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 520)
        .padding(.horizontal, 28)
        .padding(.bottom, 58)
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text("TV Show")
            if let year = show.year {
                Text("·")
                Text(year)
            }
            if let rating = show.voteAverage, rating > 0 {
                Text("·")
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var accessibilityLabel: String {
        var components = [show.displayTitle, "TV Show"]
        if let year = show.year {
            components.append(year)
        }
        return components.joined(separator: ", ")
    }

    private var carouselHeight: CGFloat {
        horizontalSizeClass == .compact ? 610 : 740
    }
}

#if DEBUG
#Preview("TV Poster Hero") {
    TVDetailPosterHeroView(
        show: .previewShow,
        posterURL: nil
    )
    .background(Color.black)
}
#endif
