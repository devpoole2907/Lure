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
    let runtime: String?
    let rating: Double?
    let overview: String?
    let badges: [DetailBadge]
    let genres: [String]
    let verticalOffset: CGFloat
    let primaryAction: DetailPosterHeroAction
    let secondaryAction: DetailPosterHeroAction?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isOverviewExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                heroVisualLayer
                    .frame(width: size.width, height: size.height)
                    .accessibilityHidden(true)

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

    private var heroVisualLayer: some View {
        ZStack {
            heroImage
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.20), location: 0.45),
                    .init(color: .black.opacity(0.65), location: 0.72),
                    .init(color: .black.opacity(0.88), location: 0.88),
                    .init(color: .black.opacity(0.72), location: 0.96),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.84),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

            actionRow
                .padding(.top, 4)

            overviewSection

            footerMetadata
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 540)
        .padding(.horizontal, 28)
        .padding(.bottom, 48)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            Button(action: primaryAction.action) {
                Label(primaryAction.title, systemImage: primaryAction.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 24)
                    .frame(height: 44)
                    .frame(minWidth: 164)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!primaryAction.isEnabled)
            .opacity(primaryAction.isEnabled ? 1 : 0.55)

            if let secondaryAction {
                Button(action: secondaryAction.action) {
                    Image(systemName: secondaryAction.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!secondaryAction.isEnabled)
                .opacity(secondaryAction.isEnabled ? 1 : 0.45)
                .accessibilityLabel(secondaryAction.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var overviewSection: some View {
        if let overviewText {
            VStack(alignment: .leading, spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Text(overviewText)
                        .font(.subheadline)
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(isOverviewExpanded || !shouldShowOverviewToggle ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, !isOverviewExpanded && shouldShowOverviewToggle ? 78 : 0)

                    if !isOverviewExpanded && shouldShowOverviewToggle {
                        overviewToggleButton("MORE")
                    }
                }

                if isOverviewExpanded && shouldShowOverviewToggle {
                    overviewToggleButton("LESS")
                }
            }
            .padding(.top, 10)
        }
    }

    private func overviewToggleButton(_ title: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOverviewExpanded.toggle()
            }
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footerMetadata: some View {
        if !footerItems.isEmpty {
            Text(footerItems.joined(separator: " · "))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 8) {
            Text(mediaTypeLabel)
            if let year {
                Text("·")
                Text(year)
            }
            if let runtime {
                Text("·")
                Text(runtime)
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

    private var overviewText: String? {
        guard let overview else { return nil }
        let text = overview.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var shouldShowOverviewToggle: Bool {
        (overviewText?.count ?? 0) > 140
    }

    private var footerItems: [String] {
        let rawItems = badges.map(\.label) + genres
        var seen = Set<String>()
        return rawItems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { item in
                let key = item.lowercased()
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .prefix(10)
            .map(\.self)
    }

    private var carouselHeight: CGFloat {
        horizontalSizeClass == .compact ? 660 : 780
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
        runtime: nil,
        rating: SeerrTVDetail.previewShow.voteAverage,
        overview: SeerrTVDetail.previewShow.overview,
        badges: [],
        genres: SeerrTVDetail.previewShow.genres?.compactMap(\.name) ?? [],
        verticalOffset: 0,
        primaryAction: DetailPosterHeroAction(title: "Play First Episode", systemImage: "play.fill") {},
        secondaryAction: DetailPosterHeroAction(title: "Add to Favorites", systemImage: "plus") {}
    )
    .background(Color.black)
}
#endif
