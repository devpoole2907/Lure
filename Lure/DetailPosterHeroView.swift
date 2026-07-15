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
    let ratingItems: [DetailHeroRatingItem]
    let verticalOffset: CGFloat
    let primaryAction: DetailPosterHeroAction
    let secondaryAction: DetailPosterHeroAction?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isOverviewExpanded = false
    @State private var containerWidth: CGFloat = 0
    #if os(tvOS)
    @FocusState private var isPrimaryActionFocused: Bool
    #endif

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
        #if os(tvOS)
        .ignoresSafeArea(edges: .horizontal)
        .onAppear {
            isPrimaryActionFocused = true
        }
        #endif
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, width in
            containerWidth = width
        }
    }

    private var heroImage: some View {
        // tvOS: progressive two-stage load — the sized variant appears
        // immediately (usually cached), then TMDB `original` (up to 4K)
        // crossfades in once decoded.
        #if os(tvOS)
        ProgressiveRemoteImage(
            url: artworkURL,
            highResURL: ImageURL.originalTMDBImageURL(artworkURL),
            contentMode: .fill
        ) {
            heroImagePlaceholder
        }
        #else
        CachedRemoteImage(url: artworkURL, contentMode: .fill) {
            heroImagePlaceholder
        }
        #endif
    }

    private var heroImagePlaceholder: some View {
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
        VStack(alignment: heroContentAlignment, spacing: 10) {
            HeroTitleArtworkView(
                title: title,
                logoURL: logoURL,
                maxWidth: heroTitleMaxWidth,
                maxLogoHeight: heroLogoMaxHeight,
                horizontalAlignment: heroContentAlignment,
                reportTitleBottom: true
            )

            metadataRow

            actionRow
                .padding(.top, 4)

            overviewSection

            footerMetadata

            ratingsRow
        }
        .foregroundStyle(.white)
        .frame(maxWidth: heroContentMaxWidth, alignment: heroFrameAlignment)
        .padding(.horizontal, heroHorizontalPadding)
        .padding(.bottom, heroBottomPadding)
        .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
    }

    private var actionRow: some View {
        HStack(spacing: heroActionSpacing) {
            #if os(tvOS)
            // tvOS: style the button with a custom focus-scale effect so the
            // already-drawn white capsule doesn't get wrapped in a second card plate.
            Button(action: primaryAction.action) {
                TVHeroCapsuleLabel(title: primaryAction.title, systemImage: primaryAction.systemImage)
            }
            .buttonStyle(TVHeroActionButtonStyle())
            .focused($isPrimaryActionFocused)
            .disabled(!primaryAction.isEnabled)
            .opacity(primaryAction.isEnabled ? 1 : 0.55)

            if let secondaryAction {
                Button(action: secondaryAction.action) {
                    TVHeroCircleIconLabel(
                        systemImage: secondaryAction.systemImage,
                        isHighlighted: secondaryAction.isHighlighted
                    )
                }
                .buttonStyle(TVHeroActionButtonStyle())
                .disabled(!secondaryAction.isEnabled)
                .opacity(secondaryAction.isEnabled || secondaryAction.isHighlighted ? 1 : 0.45)
                .accessibilityLabel(secondaryAction.title)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: secondaryAction.isHighlighted)
            }
            #else
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
                        .background {
                            Circle()
                                .fill(secondaryAction.isHighlighted ? Color.green : Color.clear)
                                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: secondaryAction.isHighlighted)
                        }
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(secondaryAction.isHighlighted ? .white.opacity(0.55) : .white.opacity(0.18), lineWidth: 0.8)
                        }
                        .scaleEffect(secondaryAction.isHighlighted ? 1.04 : 1)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: secondaryAction.isHighlighted)
                }
                .buttonStyle(.plain)
                .disabled(!secondaryAction.isEnabled)
                .opacity(secondaryAction.isEnabled || secondaryAction.isHighlighted ? 1 : 0.45)
                .accessibilityLabel(secondaryAction.title)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: secondaryAction.isHighlighted)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
    }

    private var heroActionSpacing: CGFloat {
        #if os(tvOS)
        16
        #else
        14
        #endif
    }

    @ViewBuilder
    private var overviewSection: some View {
        if let overviewText {
            VStack(alignment: .leading, spacing: 5) {
                #if os(tvOS)
                Text(overviewText)
                    .font(overviewFont)
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(isOverviewExpanded || !shouldShowOverviewToggle ? nil : overviewLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if shouldShowOverviewToggle {
                    overviewToggleButton(isOverviewExpanded ? "LESS" : "MORE")
                        .padding(.top, 4)
                }
                #else
                ZStack(alignment: .bottomTrailing) {
                    Text(overviewText)
                        .font(overviewFont)
                        .lineSpacing(2)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(isOverviewExpanded || !shouldShowOverviewToggle ? nil : overviewLineLimit)
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
                #endif
            }
            .padding(.top, 10)
        }
    }

    private var overviewFont: Font {
        #if os(tvOS)
        .callout
        #else
        .subheadline
        #endif
    }

    private var overviewLineLimit: Int {
        #if os(tvOS)
        3
        #else
        2
        #endif
    }

    private func overviewToggleButton(_ title: String) -> some View {
        OverviewToggleButton(title: title) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOverviewExpanded.toggle()
            }
        }
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
    private var ratingsRow: some View {
        if !ratingItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(ratingItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Text("·")
                                .foregroundStyle(.white.opacity(0.36))
                        }

                        ratingItem(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func ratingItem(_ item: DetailHeroRatingItem) -> some View {
        #if os(tvOS)
        Text(item.text)
        #else
        if let destination = item.destination {
            Link(destination: destination) {
                HStack(spacing: 3) {
                    Text(item.text)
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(item.text)
        }
        #endif
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
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                    Text(String(format: "%.1f", rating))
                }
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
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
        #if os(macOS)
        guard containerWidth > 0 else { return 560 }
        return min(max(containerWidth * 0.46, 430), 620)
        #elseif os(tvOS)
        // tvOS canvas is 1920×1080; hero fills ~90% of screen height,
        // matching the Discover hero carousel.
        guard containerWidth > 0 else { return 960 }
        return min(max(containerWidth * 0.552, 720), 1032)
        #else
        horizontalSizeClass == .compact ? 660 : 780
        #endif
    }

    private var heroContentAlignment: HorizontalAlignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var heroFrameAlignment: Alignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var heroContentMaxWidth: CGFloat {
        #if os(macOS)
        560
        #elseif os(tvOS)
        // Allow wide content to breathe — TV screen is 1920pt wide
        900
        #else
        540
        #endif
    }

    private var heroTitleMaxWidth: CGFloat {
        #if os(macOS)
        336
        #elseif os(tvOS)
        800
        #else
        430
        #endif
    }

    private var heroLogoMaxHeight: CGFloat {
        #if os(macOS)
        78
        #elseif os(tvOS)
        180
        #else
        142
        #endif
    }

    private var heroHorizontalPadding: CGFloat {
        #if os(macOS)
        56
        #elseif os(tvOS)
        // tvOS safe area is ~90pt on each side
        90
        #else
        28
        #endif
    }

    private var heroBottomPadding: CGFloat {
        #if os(macOS)
        60
        #elseif os(tvOS)
        80
        #else
        48
        #endif
    }
}

#if DEBUG
#Preview("Detail Poster Hero — TV Show") {
    DetailPosterHeroView(
        title: SeerrTVDetail.previewShow.displayTitle,
        artworkURL: nil,
        logoURL: nil,
        mediaTypeLabel: "TV Show",
        year: SeerrTVDetail.previewShow.year,
        runtime: nil,
        rating: SeerrTVDetail.previewShow.voteAverage,
        overview: SeerrTVDetail.previewShow.overview,
        badges: PreviewSupport.sampleBadges,
        genres: SeerrTVDetail.previewShow.genres?.compactMap(\.name) ?? [],
        ratingItems: PreviewSupport.sampleRatingItems,
        verticalOffset: 0,
        primaryAction: PreviewSupport.playAction,
        secondaryAction: PreviewSupport.addToFavoritesAction
    )
    .background(Color.black)
}

#Preview("Detail Poster Hero — Movie") {
    DetailPosterHeroView(
        title: PreviewSupport.previewMovieDetail.displayTitle,
        artworkURL: nil,
        logoURL: nil,
        mediaTypeLabel: "Movie",
        year: PreviewSupport.previewMovieDetail.year,
        runtime: PreviewSupport.previewMovieDetail.runtimeText,
        rating: nil,
        overview: PreviewSupport.previewMovieDetail.overview,
        badges: [],
        genres: PreviewSupport.previewMovieDetail.genres?.compactMap(\.name) ?? [],
        ratingItems: PreviewSupport.sampleRatingItems,
        verticalOffset: 0,
        primaryAction: PreviewSupport.playAction,
        secondaryAction: nil
    )
    .background(Color.black)
}

#Preview("Detail Poster Hero — Request state") {
    DetailPosterHeroView(
        title: "Dune: Part Two",
        artworkURL: nil,
        logoURL: nil,
        mediaTypeLabel: "Movie",
        year: "2024",
        runtime: "2h 46m",
        rating: nil,
        overview: "Paul Atreides unites with the Fremen people on the desert planet Arrakis to wage war against the family who destroyed his family.",
        badges: [DetailBadge(icon: "shield", label: "PG-13", color: .yellow)],
        genres: ["Science Fiction", "Adventure"],
        ratingItems: [],
        verticalOffset: 0,
        primaryAction: PreviewSupport.requestAction,
        secondaryAction: nil
    )
    .background(Color.black)
}
#endif

#if DEBUG && os(iOS)
#Preview("Detail Poster Hero — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    DetailPosterHeroView(
        title: PreviewSupport.previewMovieDetail.displayTitle,
        artworkURL: nil,
        logoURL: nil,
        mediaTypeLabel: "Movie",
        year: PreviewSupport.previewMovieDetail.year,
        runtime: PreviewSupport.previewMovieDetail.runtimeText,
        rating: PreviewSupport.previewMovieDetail.voteAverage,
        overview: PreviewSupport.previewMovieDetail.overview,
        badges: PreviewSupport.sampleBadges,
        genres: PreviewSupport.previewMovieDetail.genres?.compactMap(\.name) ?? [],
        ratingItems: PreviewSupport.sampleRatingItems,
        verticalOffset: 0,
        primaryAction: PreviewSupport.playAction,
        secondaryAction: PreviewSupport.addToFavoritesAction
    )
    .background(Color.black)
}
#endif
