import SwiftUI

struct TVSeasonEpisodeShelf: View {
    let show: SeerrTVDetail
    let jellyfinClient: JellyfinAPIClient?
    let jellyfinSeriesId: String?
    let onPlayEpisode: (JellyfinItem?) -> Void
    let onOpenEpisodePicker: () -> Void

    @State private var selectedSeasonNumber: Int
    @State private var jellyfinEpisodesBySeasonNumber: [Int: [JellyfinItem]] = [:]
    private let horizontalBleed: CGFloat = 16

    init(
        show: SeerrTVDetail,
        jellyfinClient: JellyfinAPIClient? = nil,
        jellyfinSeriesId: String? = nil,
        onPlayEpisode: @escaping (JellyfinItem?) -> Void = { _ in },
        onOpenEpisodePicker: @escaping () -> Void = {}
    ) {
        self.show = show
        self.jellyfinClient = jellyfinClient
        self.jellyfinSeriesId = jellyfinSeriesId
        self.onPlayEpisode = onPlayEpisode
        self.onOpenEpisodePicker = onOpenEpisodePicker
        self._selectedSeasonNumber = State(initialValue: show.requestableSeasons.first?.seasonNumber ?? 1)
    }

    private var seasons: [SeerrTVSeason] {
        show.requestableSeasons
    }

    private var selectedSeason: SeerrTVSeason? {
        seasons.first { $0.seasonNumber == selectedSeasonNumber } ?? seasons.first
    }

    private var selectedStatusSeason: SeerrSeasonStatus? {
        guard let selectedSeason else { return nil }
        return show.mediaInfo?.seasons?.first { $0.seasonNumber == selectedSeason.seasonNumber }
    }

    private var seasonNumbers: [Int] {
        seasons.map(\.seasonNumber)
    }

    var body: some View {
        if let selectedSeason, !episodeNumbers(for: selectedSeason).isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                seasonPicker

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(episodeNumbers(for: selectedSeason), id: \.self) { episodeNumber in
                            TVSeasonEpisodeCard(
                                show: show,
                                season: selectedSeason,
                                episodeNumber: episodeNumber,
                                status: status(for: episodeNumber),
                                jellyfinClient: jellyfinClient,
                                jellyfinEpisode: jellyfinEpisode(for: episodeNumber),
                                onPlay: onPlayEpisode,
                                onOpenEpisodePicker: onOpenEpisodePicker
                            )
                        }
                    }
                    .padding(.horizontal, horizontalBleed)
                }
                .padding(.horizontal, -horizontalBleed)
                .horizontalSoftEdges()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear(perform: validateSelection)
            .onChange(of: seasonNumbers) { _, _ in
                validateSelection()
            }
            .task(id: "\(jellyfinSeriesId ?? "none")|\(selectedSeasonNumber)") {
                await loadJellyfinEpisodesForSelectedSeason()
            }
        }
    }

    private var seasonPicker: some View {
        Picker(selection: $selectedSeasonNumber) {
            ForEach(seasons) { season in
                Text(seasonTitle(season)).tag(season.seasonNumber)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .foregroundStyle(.secondary)
                Text(seasonTitle(selectedSeason))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pickerStyle(.menu)
        .tint(.primary)
    }

    private func episodeNumbers(for season: SeerrTVSeason) -> [Int] {
        if let count = season.episodeCount, count > 0 {
            return Array(1...count)
        }

        return (selectedStatusSeason?.episodes ?? [])
            .compactMap(\.episodeNumber)
            .sorted()
    }

    private func status(for episodeNumber: Int) -> LureConstants.MediaStatus? {
        if let episodeStatus = selectedStatusSeason?.episodes?.first(where: { $0.episodeNumber == episodeNumber }),
           let rawStatus = episodeStatus.status {
            return LureConstants.MediaStatus(rawValue: rawStatus)
        }

        if selectedStatusSeason?.status == LureConstants.MediaStatus.available.rawValue {
            return .available
        }

        return nil
    }

    private func jellyfinEpisode(for episodeNumber: Int) -> JellyfinItem? {
        jellyfinEpisodesBySeasonNumber[selectedSeasonNumber]?
            .first { $0.indexNumber == episodeNumber }
    }

    private func seasonTitle(_ season: SeerrTVSeason?) -> String {
        guard let season else { return "Season" }
        return season.name ?? "Season \(season.seasonNumber)"
    }

    private func validateSelection() {
        guard !seasonNumbers.contains(selectedSeasonNumber),
              let firstSeasonNumber = seasonNumbers.first else {
            return
        }

        selectedSeasonNumber = firstSeasonNumber
    }

    @MainActor
    private func loadJellyfinEpisodesForSelectedSeason() async {
        guard jellyfinEpisodesBySeasonNumber[selectedSeasonNumber] == nil,
              let jellyfinClient,
              let jellyfinSeriesId else {
            return
        }

        do {
            let jellyfinSeasons = try await jellyfinClient.getSeasons(seriesId: jellyfinSeriesId)
            guard let seasonID = jellyfinSeasons.first(where: { $0.indexNumber == selectedSeasonNumber })?.id else {
                jellyfinEpisodesBySeasonNumber[selectedSeasonNumber] = []
                return
            }

            let episodes = try await jellyfinClient.getEpisodes(
                seriesId: jellyfinSeriesId,
                seasonId: seasonID
            )
            jellyfinEpisodesBySeasonNumber[selectedSeasonNumber] = episodes
        } catch {
            jellyfinEpisodesBySeasonNumber[selectedSeasonNumber] = []
        }
    }
}

private struct TVSeasonEpisodeCard: View {
    let show: SeerrTVDetail
    let season: SeerrTVSeason
    let episodeNumber: Int
    let status: LureConstants.MediaStatus?
    let jellyfinClient: JellyfinAPIClient?
    let jellyfinEpisode: JellyfinItem?
    let onPlay: (JellyfinItem?) -> Void
    let onOpenEpisodePicker: () -> Void
    @State private var isMarkingWatched = false

    private static let cardWidth: CGFloat = 320
    private static let cardHeight: CGFloat = 300
    private static let cornerRadius: CGFloat = 24

    private var imageURL: URL? {
        // An episode's still is its Primary image. The Thumb endpoint always builds a
        // valid URL but, for episodes that have no Thumb, Jellyfin serves the *series*
        // artwork instead — which is why every card was showing the show poster.
        if let jellyfinClient, let itemID = jellyfinEpisode?.id {
            return jellyfinClient.primaryImageURL(itemId: itemID, width: 500)
        }

        return season.posterURL ?? show.posterURL
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Button {
                onPlay(jellyfinEpisode)
            } label: {
                cardVisual
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the player for this episode.")

            episodeMenu
                .padding(.trailing, 10)
                .padding(.bottom, 10)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
    }

    private var cardVisual: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(
                url: imageURL,
                width: Self.cardWidth,
                height: Self.cardHeight,
                cornerRadius: Self.cornerRadius
            )

            Rectangle()
                .fill(.black.opacity(0.18))

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: .black.opacity(0.38), location: 0.46),
                    .init(color: .black.opacity(0.86), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            cardText
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.7)
        }
    }

    private var cardText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)

            Text("EPISODE \(episodeNumber)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)

            Text(episodeTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            if let episodeOverview {
                Text(episodeOverview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .lineSpacing(2)
                    .minimumScaleFactor(0.86)
            }

            HStack(alignment: .center, spacing: 8) {
                if let durationText {
                    Label(durationText, systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.84))
                }

                Spacer(minLength: 16)
            }
            .padding(.top, 2)
        }
        .padding(22)
        .padding(.trailing, 34)
    }

    private var episodeMenu: some View {
        Menu {
            Button("Play episode", systemImage: "play.fill") {
                if let jellyfinEpisode {
                    onPlay(jellyfinEpisode)
                }
            }
            .disabled(jellyfinEpisode == nil)

            Button("Go to episode", systemImage: "info.circle") {
                onOpenEpisodePicker()
            }

            Button("Mark as watched", systemImage: "checkmark.circle") {
                markAsWatched()
            }
            .disabled(jellyfinEpisode?.id == nil || isMarkingWatched)

            Button("Download", systemImage: "arrow.down.circle") {}
                .disabled(true)
        } label: {
            Label("Episode Options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.bold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .menuStyle(.button)
    }

    private func markAsWatched() {
        guard let jellyfinClient, let itemId = jellyfinEpisode?.id else { return }
        isMarkingWatched = true
        Task {
            try? await jellyfinClient.markPlayed(itemId: itemId)
            await MainActor.run {
                isMarkingWatched = false
            }
        }
    }

    private var episodeTitle: String {
        let title = jellyfinEpisode?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty else { return "Episode \(episodeNumber)" }
        return title
    }

    private var episodeOverview: String? {
        let overview = jellyfinEpisode?.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        return overview?.isEmpty == false ? overview : nil
    }

    private var durationText: String? {
        guard let seconds = jellyfinEpisode?.durationSeconds, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "\(minutes)m"
    }

    private var statusText: String {
        status?.displayName ?? "Not Requested"
    }

    private var accessibilityLabel: String {
        var components = [
            season.name ?? "Season \(season.seasonNumber)",
            "Episode \(episodeNumber)",
            episodeTitle
        ]
        if let durationText {
            components.append(durationText)
        }
        components.append(statusText)
        return components.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("TV Season Episode Shelf") {
    NavigationStack {
        ScrollView {
            TVSeasonEpisodeShelf(show: .previewShow)
                .padding()
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
#endif
