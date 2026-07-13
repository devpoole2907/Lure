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

    @State private var episode: JellyfinItem?
    @State private var mediaQuality: MediaQualityInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var heroVerticalOffset: CGFloat = 0

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
        .navigationTitle(episode?.name ?? route.episodeTitle)
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
        .task(id: route.itemId) {
            await loadEpisode()
        }
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .center, spacing: 20) {
                heroSection

                VStack(alignment: .center, spacing: 20) {
                    let rows = infoRows
                    if !rows.isEmpty {
                        rowsCard(header: "Info", icon: "info.circle", rows: rows)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 44)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
#if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .ignoresSafeArea(edges: .top)
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
        return client.primaryImageURL(itemId: route.itemId, width: 1000)
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
        if let rating = episode?.communityRating, rating > 0 {
            rows.append(("star.fill", "Rating", String(format: "%.1f", rating)))
        }
        if let resume = episode?.resumeLabel {
            rows.append(("play.circle", "Resume", resume))
        }
        return rows
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
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func rowsCard(header: String, icon: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(header, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .center)
                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.2)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if index < rows.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}
