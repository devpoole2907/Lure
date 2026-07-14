import SwiftUI

// MARK: - Previews

#if DEBUG && !os(macOS)
// EpisodePickerView is a modal sheet used on iOS and tvOS (not presented on macOS).
#Preview("Episode Picker — Not in Library") {
    // With no real JellyfinService client, loadSeries() will set the
    // "Jellyfin not configured" error message, which previews the error state.
    EpisodePickerView(
        tmdbId: 1399,
        seriesTitle: "Game of Thrones",
        serviceUrl: nil,
        jellyfinSeriesId: nil
    ) { _, _, _ in }
    .environment(PreviewSupport.jellyfinService)
}
#endif

#if DEBUG && os(iOS)
#Preview("Episode Picker — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    EpisodePickerView(
        tmdbId: 1399,
        seriesTitle: "Game of Thrones",
        serviceUrl: nil,
        jellyfinSeriesId: nil
    ) { _, _, _ in }
    .environment(PreviewSupport.jellyfinService)
}
#endif

struct EpisodePickerView: View {
    let tmdbId: Int
    let seriesTitle: String
    let serviceUrl: String?
    let jellyfinSeriesId: String?
    let onPlay: (String, String?, String) -> Void

    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(\.dismiss) private var dismiss
    @State private var client: JellyfinAPIClient?
    @State private var seriesId: String?
    @State private var seasons: [JellyfinSeason] = []
    @State private var selectedSeasonId: String?
    @State private var episodes: [JellyfinItem] = []
    @State private var isLoadingSeasons = false
    @State private var isLoadingEpisodes = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingSeasons {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Unable to Load", systemImage: "tv.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") { Task { await loadSeries() } }
                    }
                } else if seasons.isEmpty {
                    ContentUnavailableView(
                        "Not in Library",
                        systemImage: "questionmark.folder",
                        description: Text("This show wasn't found in your Jellyfin library.")
                    )
                } else {
                    episodeList
                }
            }
            .lureNavigationTitle(seriesTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await loadSeries() }
    }

    @ViewBuilder
    private var episodeList: some View {
        #if os(tvOS)
        tvEpisodeList
        #else
        List {
            if seasons.count > 1 {
                Section {
                    Picker("Season", selection: $selectedSeasonId) {
                        ForEach(seasons) { season in
                            Text(season.name ?? "Season").tag(season.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: selectedSeasonId) { _, newId in
                    guard let id = newId else { return }
                    Task { await loadEpisodes(seasonId: id) }
                }
            }

            Section {
                if isLoadingEpisodes {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(episodes, id: \.id) { episode in
                        Button {
                            guard let id = episode.id else { return }
                            onPlay(id, episode.detailedEpisodeLabel, episode.seriesName ?? seriesTitle)
                            dismiss()
                        } label: {
                            episodeRow(episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        #endif
    }

    #if os(tvOS)
    private var tvEpisodeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                if seasons.count > 1 {
                    tvSeasonPicker
                }

                if isLoadingEpisodes {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.large)
                        Spacer()
                    }
                    .frame(minHeight: 260)
                } else if episodes.isEmpty {
                    ContentUnavailableView(
                        "No Episodes",
                        systemImage: "play.rectangle",
                        description: Text("No playable episodes were found for this season.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    LazyVGrid(columns: tvEpisodeColumns, alignment: .leading, spacing: 26) {
                        ForEach(episodes, id: \.id) { episode in
                            Button {
                                guard let id = episode.id else { return }
                                onPlay(id, episode.detailedEpisodeLabel, episode.seriesName ?? seriesTitle)
                                dismiss()
                            } label: {
                                tvEpisodeCard(episode)
                            }
                            .buttonStyle(.card)
                        }
                    }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 54)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tvSeasonPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Season")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(seasons.enumerated()), id: \.offset) { _, season in
                        let isSelected = season.id == selectedSeasonId
                        Button {
                            guard let id = season.id else { return }
                            selectedSeasonId = id
                            Task { await loadEpisodes(seasonId: id) }
                        } label: {
                            Text(season.name ?? "Season")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isSelected ? .black : .primary)
                                .padding(.horizontal, 28)
                                .frame(height: 64)
                                .background {
                                    if isSelected {
                                        Capsule().fill(.white)
                                    } else {
                                        Capsule().fill(.regularMaterial)
                                    }
                                }
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var tvEpisodeColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 460), spacing: 26, alignment: .top)]
    }

    private func tvEpisodeCard(_ episode: JellyfinItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label = episode.episodeLabel {
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(episode.name ?? "Episode")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let resumeLabel = episode.resumeLabel {
                Label("Resume \(resumeLabel)", systemImage: "play.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.blue)
            }

            if let overview = episode.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
               !overview.isEmpty {
                Text(overview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .contentShape(Rectangle())
    }
    #endif

    private func episodeRow(_ episode: JellyfinItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label = episode.episodeLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(episode.name ?? "Episode")
                .font(.subheadline.weight(.medium))
            if let label = episode.resumeLabel {
                Label("Resume \(label)", systemImage: "play.circle")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func loadSeries() async {
        errorMessage = nil
        guard let apiClient = jellyfinService.client else {
            errorMessage = "Jellyfin not configured. Go to Settings → Jellyfin Playback."
            return
        }
        client = apiClient
        isLoadingSeasons = true
        defer { isLoadingSeasons = false }

        do {
            guard let sid = try await resolvedSeriesId() else {
                seasons = []
                return
            }
            seriesId = sid
            seasons = try await apiClient.getSeasons(seriesId: sid)
            let firstId = seasons.first?.id
            selectedSeasonId = firstId
            if let fid = firstId {
                await loadEpisodes(seasonId: fid)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedSeriesId() async throws -> String? {
        if let jellyfinSeriesId, !jellyfinSeriesId.isEmpty {
            return jellyfinSeriesId
        }
        return try await jellyfinService.findItemId(
            serviceUrl: serviceUrl,
            tmdbId: tmdbId,
            mediaType: "tv",
            title: seriesTitle,
            releaseYear: nil
        )
    }

    private func loadEpisodes(seasonId: String) async {
        guard let apiClient = client, let sid = seriesId else { return }
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            episodes = try await apiClient.getEpisodes(seriesId: sid, seasonId: seasonId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
