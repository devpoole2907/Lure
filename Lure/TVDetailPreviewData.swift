import Foundation

#if DEBUG
extension SeerrTVDetail {
    static let previewShow = SeerrTVDetail(
        id: 1987,
        backdropPath: nil,
        posterPath: nil,
        contentRatings: nil,
        createdBy: nil,
        episodeRunTime: [52],
        firstAirDate: "2025-03-14",
        genres: [
            SeerrGenre(id: 18, name: "Drama"),
            SeerrGenre(id: 9648, name: "Mystery")
        ],
        homepage: nil,
        inProduction: true,
        languages: ["en"],
        lastAirDate: nil,
        name: "The Midnight Signal",
        originalName: nil,
        numberOfEpisodes: 16,
        numberOfSeasons: 2,
        originCountry: ["US"],
        originalLanguage: "en",
        overview: "A late-night radio producer follows a string of impossible broadcasts across the city.",
        popularity: 42.8,
        productionCompanies: nil,
        seasons: [
            SeerrTVSeason(
                seasonNumber: 1,
                airDate: "2025-03-14",
                episodeCount: 8,
                name: "Season 1",
                overview: nil,
                posterPath: nil
            ),
            SeerrTVSeason(
                seasonNumber: 2,
                airDate: "2026-02-20",
                episodeCount: 8,
                name: "Season 2",
                overview: nil,
                posterPath: nil
            )
        ],
        status: "Returning Series",
        tagline: nil,
        type: "Scripted",
        voteAverage: 8.1,
        voteCount: 936,
        credits: nil,
        mediaInfo: SeerrMediaInfo(
            id: 42,
            tmdbId: 1987,
            tvdbId: nil,
            status: LureConstants.MediaStatus.partiallyAvailable.rawValue,
            requests: nil,
            seasons: [
                SeerrSeasonStatus(
                    seasonNumber: 1,
                    status: LureConstants.MediaStatus.available.rawValue,
                    episodes: nil
                ),
                SeerrSeasonStatus(
                    seasonNumber: 2,
                    status: LureConstants.MediaStatus.partiallyAvailable.rawValue,
                    episodes: [
                        SeerrEpisodeStatus(id: 201, episodeNumber: 1, status: LureConstants.MediaStatus.available.rawValue),
                        SeerrEpisodeStatus(id: 202, episodeNumber: 2, status: LureConstants.MediaStatus.available.rawValue),
                        SeerrEpisodeStatus(id: 203, episodeNumber: 3, status: LureConstants.MediaStatus.processing.rawValue),
                        SeerrEpisodeStatus(id: 204, episodeNumber: 4, status: LureConstants.MediaStatus.pending.rawValue)
                    ]
                )
            ],
            mediaType: "tv",
            plexUrl: nil,
            serviceUrl: nil
        ),
        externalIds: nil,
        relatedVideos: nil,
        networks: [
            SeerrNetwork(id: 1, logoPath: nil, originCountry: "US", name: "Lure+")
        ],
        watchProviders: nil
    )
}
#endif
