import SwiftUI

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
            .navigationTitle(seriesTitle)
            .navigationBarTitleDisplayMode(.inline)
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
    }

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
