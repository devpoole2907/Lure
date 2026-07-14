import SwiftUI

struct EpisodeDetailRoute: Identifiable, Hashable {
    let itemId: String
    let seriesTitle: String
    let episodeTitle: String
    let episodeLabel: String?

    var id: String { itemId }
}

struct EpisodeDetailView: View {
    let route: EpisodeDetailRoute
    let jellyfinClient: JellyfinAPIClient?
    let onPlay: (JellyfinItem) -> Void
    private let shouldLoadEpisode: Bool

    @State private var episode: JellyfinItem?
    @State private var mediaQuality: MediaQualityInfo?
    @State private var mediaSource: JellyfinMediaSource?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var heroVerticalOffset: CGFloat = 0

    init(
        route: EpisodeDetailRoute,
        jellyfinClient: JellyfinAPIClient?,
        onPlay: @escaping (JellyfinItem) -> Void
    ) {
        self.route = route
        self.jellyfinClient = jellyfinClient
        self.onPlay = onPlay
        self.shouldLoadEpisode = true
    }

    #if DEBUG
    init(previewEpisode: JellyfinItem, seriesTitle: String) {
        self.route = EpisodeDetailRoute(
            itemId: previewEpisode.id ?? "preview-episode",
            seriesTitle: seriesTitle,
            episodeTitle: previewEpisode.name ?? "Episode",
            episodeLabel: previewEpisode.episodeLabel
        )
        self.jellyfinClient = nil
        self.onPlay = { _ in }
        self.shouldLoadEpisode = false
        self._episode = State(initialValue: previewEpisode)
        self._isLoading = State(initialValue: false)
    }
    #endif

    var body: some View {
        Group {
            if isLoading, episode == nil {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Episode Unavailable", systemImage: "tv.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Retry") {
                        Task { await loadEpisode() }
                    }
                }
            } else {
                scrollContent
                    .background { artBackground }
            }
        }
        .lureNavigationTitle(episode?.name ?? route.episodeTitle)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
        .task(id: route.itemId) {
            guard shouldLoadEpisode else { return }
            await loadEpisode()
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: detailStackAlignment, spacing: 20) {
                heroSection

                VStack(alignment: detailContentAlignment, spacing: 20) {
                    if !episodeCast.isEmpty {
                        castCard(episodeCast)
                    }

                    let rows = infoRows
                    if !rows.isEmpty {
                        rowsCard(header: "Info", icon: "info.circle", rows: rows)
                    }
                }
                .padding(.horizontal, detailContentHorizontalPadding)
                .padding(.bottom, 44)
                .frame(maxWidth: detailContentMaxWidth, alignment: detailFrameAlignment)
                .frame(maxWidth: .infinity)
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: [.top, .horizontal])
        #else
        .ignoresSafeArea(edges: .top)
        #endif
#if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
#if os(macOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, newValue in
            heroVerticalOffset = max(-newValue, 0)
        }
        .environment(\.colorScheme, .dark)
    }

    private var heroSection: some View {
        DetailPosterHeroView(
            title: episode?.name ?? route.episodeTitle,
            artworkURL: episodeArtworkURL,
            logoURL: nil,
            mediaTypeLabel: route.episodeLabel ?? "Episode",
            year: nil,
            runtime: durationText,
            rating: episode?.communityRating,
            overview: episode?.overview,
            badges: episodeBadges,
            genres: [],
            ratingItems: [],
            verticalOffset: heroVerticalOffset,
            primaryAction: DetailPosterHeroAction(
                title: "Play Episode",
                systemImage: "play.fill",
                isEnabled: episode?.id != nil
            ) {
                if let episode {
                    onPlay(episode)
                }
            },
            secondaryAction: nil
        )
    }

    private var artBackground: some View {
        AsyncImage(
            url: episodeArtworkURL,
            transaction: Transaction(animation: .easeInOut(duration: 0.3))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure, .empty:
                Rectangle().fill(Color.indigo.opacity(0.35))
            @unknown default:
                Rectangle().fill(Color.indigo.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(1.4)
        .blur(radius: 60)
        .saturation(1.35)
        .overlay(Color.black.opacity(0.58))
        .ignoresSafeArea()
    }

    private var episodeArtworkURL: URL? {
        guard let client = jellyfinClient else { return nil }
        #if os(tvOS)
        return client.primaryImageURL(itemId: route.itemId, width: 1920)
        #else
        return client.primaryImageURL(itemId: route.itemId, width: 1000)
        #endif
    }

    private var detailStackAlignment: HorizontalAlignment {
        #if os(tvOS) || os(macOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailContentAlignment: HorizontalAlignment {
        #if os(tvOS) || os(macOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailFrameAlignment: Alignment {
        #if os(tvOS) || os(macOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailContentMaxWidth: CGFloat {
        #if os(tvOS) || os(macOS)
        .infinity
        #else
        720
        #endif
    }

    private var detailContentHorizontalPadding: CGFloat {
        #if os(tvOS)
        90
        #elseif os(macOS)
        44
        #else
        16
        #endif
    }

    private var episodeBadges: [DetailBadge] {
        var badges: [DetailBadge] = []
        if episode?.userData?.played == true {
            badges.append(DetailBadge(icon: "checkmark.circle", label: "Watched", color: .green))
        }
        if let mediaQuality {
            for badge in mediaQuality.badges {
                badges.append(DetailBadge(icon: badge.icon, label: badge.label, color: badge.tint))
            }
        }
        return badges
    }

    private var durationText: String? {
        guard let seconds = episode?.durationSeconds, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "\(minutes)m"
    }

    private var infoRows: [(String, String, String)] {
        var rows: [(String, String, String)] = []
        rows.append(("tv", "Series", episode?.seriesName ?? route.seriesTitle))
        if let season = episode?.parentIndexNumber {
            rows.append(("rectangle.stack", "Season", "\(season)"))
        }
        if let number = episode?.indexNumber {
            rows.append(("play.rectangle", "Episode", "\(number)"))
        }
        if let durationText {
            rows.append(("clock", "Runtime", durationText))
        }
        if let fileSizeText {
            rows.append(("externaldrive", "File Size", fileSizeText))
        }
        if let bitrateText {
            rows.append(("speedometer", "Bitrate", bitrateText))
        }
        if let rating = episode?.communityRating, rating > 0 {
            rows.append(("star.fill", "Rating", String(format: "%.1f", rating)))
        }
        if let resume = episode?.resumeLabel {
            rows.append(("play.circle", "Resume", resume))
        }
        return rows
    }

    private var episodeCast: [JellyfinPerson] {
        guard let people = episode?.people else { return [] }
        let actors = people.filter { ($0.type ?? "").localizedCaseInsensitiveContains("Actor") }
        let cast = actors.isEmpty ? people : actors
        return Array(cast.prefix(24))
    }

    private var fileSizeText: String? {
        guard let size = mediaSource?.size, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var bitrateText: String? {
        guard let bitrate = mediaSource?.bitrate, bitrate > 0 else { return nil }
        let megabits = Double(bitrate) / 1_000_000
        if megabits >= 10 {
            return String(format: "%.0f Mbps", megabits)
        }
        return String(format: "%.1f Mbps", megabits)
    }

    @MainActor
    private func loadEpisode() async {
        guard let jellyfinClient else {
            errorMessage = "Jellyfin playback is not configured."
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            async let episodeTask = jellyfinClient.getItem(itemId: route.itemId)
            async let playbackInfoTask = jellyfinClient.getPlaybackInfo(itemId: route.itemId)
            let loadedEpisode = try await episodeTask
            let playbackInfo = try? await playbackInfoTask
            withAnimation(.smooth(duration: 0.3)) {
                episode = loadedEpisode
                mediaQuality = MediaQualityInfo(mediaSources: playbackInfo?.mediaSources)
                mediaSource = playbackInfo?.mediaSources?.first
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func rowsCard(header: String, icon: String, rows: [(String, String, String)]) -> some View {
        #if os(tvOS)
        let horizontalPadding: CGFloat = 28
        let headerTopPadding: CGFloat = 22
        let headerBottomPadding: CGFloat = 12
        let rowVerticalPadding: CGFloat = 14
        let rowSpacing: CGFloat = 14
        let iconWidth: CGFloat = 24
        let dividerLeadingPadding: CGFloat = 66
        #else
        let horizontalPadding: CGFloat = 16
        let headerTopPadding: CGFloat = 14
        let headerBottomPadding: CGFloat = 8
        let rowVerticalPadding: CGFloat = 11
        let rowSpacing: CGFloat = 10
        let iconWidth: CGFloat = 16
        let dividerLeadingPadding: CGFloat = 42
        #endif

        return VStack(alignment: .leading, spacing: 0) {
            Label(header, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, headerTopPadding)
                .padding(.bottom, headerBottomPadding)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: rowSpacing) {
                    Image(systemName: row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: iconWidth, alignment: .center)
                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.2)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, rowVerticalPadding)

                if index < rows.count - 1 {
                    Divider().padding(.leading, dividerLeadingPadding)
                }
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        #if os(tvOS)
        .focusable()
        #endif
    }

    private func castCard(_ cast: [JellyfinPerson]) -> some View {
        #if os(tvOS)
        let avatarSize: CGFloat = 150
        let cellWidth: CGFloat = 180
        let cellHeight: CGFloat = 280
        let nameTextHeight: CGFloat = 58
        let roleTextHeight: CGFloat = 54
        let castSpacing: CGFloat = 36
        let nameFont = Font.body.weight(.semibold)
        let roleFont = Font.callout
        #else
        let avatarSize: CGFloat = 56
        let cellWidth: CGFloat = 76
        let cellHeight: CGFloat = 132
        let nameTextHeight: CGFloat = 30
        let roleTextHeight: CGFloat = 30
        let castSpacing: CGFloat = 12
        let nameFont = Font.caption2
        let roleFont = Font.caption2
        #endif

        return VStack(alignment: .leading, spacing: 10) {
            Label("Cast", systemImage: "person.2")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: castSpacing) {
                    ForEach(cast) { person in
                        let cell = VStack(spacing: 4) {
                            AsyncImage(url: personImageURL(for: person)) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(.quaternary)
                                    .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                            }
                            .frame(width: avatarSize, height: avatarSize)
                            .clipShape(Circle())

                            Text(person.name ?? "")
                                .font(nameFont)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: cellWidth, height: nameTextHeight, alignment: .top)

                            Text(person.role ?? "")
                                .font(roleFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: cellWidth, height: roleTextHeight, alignment: .top)
                        }
                        .frame(width: cellWidth, height: cellHeight, alignment: .top)

                        #if os(tvOS)
                        // Jellyfin people carry no TMDB id — push a name-only
                        // route; CastPersonSheet resolves the person via Seerr
                        // search. Handled by TVDetailView's CastPersonRoute
                        // destination in the same stack.
                        NavigationLink(value: CastPersonRoute(
                            personId: nil,
                            fallbackName: person.name,
                            fallbackProfileURL: personImageURL(for: person)
                        )) {
                            cell
                        }
                        .buttonStyle(TVPosterFocusButtonStyle(scale: 1.08))
                        #else
                        cell
                        #endif
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            #if os(tvOS)
            .scrollClipDisabled()
            #else
            .horizontalSoftEdges()
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        #if os(tvOS)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        #endif
    }

    private func personImageURL(for person: JellyfinPerson) -> URL? {
        guard let client = jellyfinClient,
              let id = person.jellyfinId,
              person.primaryImageTag != nil else {
            return nil
        }
        return client.primaryImageURL(itemId: id, width: 160)
    }
}

#if DEBUG && os(iOS)
#Preview("Episode Detail — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        EpisodeDetailView(
            previewEpisode: JellyfinItem(
                id: "preview-episode-3",
                name: "Voices After Midnight",
                type: "Episode",
                productionYear: 2025,
                providerIds: nil,
                seriesId: "preview-series",
                seriesName: "The Midnight Signal",
                seasonId: "preview-season-1",
                indexNumber: 3,
                parentIndexNumber: 1,
                userData: nil,
                runTimeTicks: 31_200_000_000,
                dateCreated: nil,
                communityRating: 8.6,
                overview: "Mara traces a broadcast that seems to be arriving from a studio abandoned decades ago.",
                people: nil,
                imageTags: nil
            ),
            seriesTitle: "The Midnight Signal"
        )
    }
}
#endif
