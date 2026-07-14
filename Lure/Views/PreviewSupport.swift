import Foundation
import SwiftUI

/// Shared fixture data for SwiftUI `#Preview` macros across the app.
/// All values are static and make no network calls.
#if DEBUG
enum PreviewSupport {

    // MARK: - SeerrAPIClient

    /// A no-op stub that satisfies the `SeerrAPIClient` type requirement.
    /// Never hits the network — all calls from preview views will simply stall
    /// or be ignored because previews don't drive async `.task` completions.
    static var apiClient: SeerrAPIClient {
        SeerrAPIClient(baseURL: "https://preview.example.invalid")
    }

    // MARK: - SeerrUser

    static var regularUser: SeerrUser {
        SeerrUser(
            id: 1,
            displayNameValue: "Preview User",
            jellyfinUsername: "preview",
            discordUsername: nil,
            email: "preview@example.com",
            username: "preview",
            plexUsername: nil,
            userType: 1,
            permissions: 2,        // request permission only
            avatar: nil,
            createdAt: nil,
            updatedAt: nil,
            requestCount: 12
        )
    }

    static var adminUser: SeerrUser {
        SeerrUser(
            id: 2,
            displayNameValue: "Admin User",
            jellyfinUsername: "admin",
            discordUsername: nil,
            email: "admin@example.com",
            username: "admin",
            plexUsername: nil,
            userType: 1,
            permissions: 2097151,  // all bits set → admin
            avatar: nil,
            createdAt: nil,
            updatedAt: nil,
            requestCount: 0
        )
    }

    // MARK: - LureRouter

    @MainActor
    static func router(tab: LureTab = .discover) -> LureRouter {
        let r = LureRouter()
        r.selectedTab = tab
        return r
    }

    // MARK: - JellyfinService

    @MainActor
    static var jellyfinService: JellyfinService {
        JellyfinService()
    }

    // MARK: - InAppNotificationCenter

    @MainActor
    static var notificationCenter: InAppNotificationCenter {
        InAppNotificationCenter()
    }

    // MARK: - PlayerCoordinator

    @MainActor
    static var playerCoordinator: PlayerCoordinator {
        PlayerCoordinator(jellyfinService: jellyfinService)
    }

    // MARK: - RequestsCoordinator

    @MainActor
    static var requestsCoordinator: RequestsCoordinator {
        RequestsCoordinator()
    }

    // MARK: - SeerrMediaItem helpers

    static func movieItem(
        id: Int = 550,
        title: String = "Fight Club",
        year: String = "1999",
        voteAverage: Double = 8.4,
        mediaInfo: SeerrMediaInfo? = nil
    ) -> SeerrMediaItem {
        .movie(SeerrMovieResult(
            id: id,
            mediaType: "movie",
            popularity: 61.4,
            posterPath: nil,
            backdropPath: nil,
            voteCount: 26723,
            voteAverage: voteAverage,
            genreIds: [18, 53],
            overview: "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.",
            originalLanguage: "en",
            title: title,
            originalTitle: title,
            releaseDate: "\(year)-10-15",
            adult: false,
            mediaInfo: mediaInfo
        ))
    }

    static func tvItem(
        id: Int = 1399,
        title: String = "Game of Thrones",
        year: String = "2011",
        voteAverage: Double = 8.3,
        mediaInfo: SeerrMediaInfo? = nil
    ) -> SeerrMediaItem {
        .tv(SeerrTvResult(
            id: id,
            mediaType: "tv",
            popularity: 369.0,
            posterPath: nil,
            backdropPath: nil,
            voteCount: 21808,
            voteAverage: voteAverage,
            genreIds: [10759, 18, 10765],
            overview: "Seven noble families fight for control of the mythical land of Westeros.",
            originalLanguage: "en",
            name: title,
            originalName: title,
            originCountry: ["US"],
            firstAirDate: "\(year)-04-17",
            mediaInfo: mediaInfo
        ))
    }

    /// A small catalogue of fixture items for carousels / sliders.
    static var sampleItems: [SeerrMediaItem] {
        [
            movieItem(id: 550, title: "Fight Club", year: "1999", voteAverage: 8.4),
            tvItem(id: 1399, title: "Game of Thrones", year: "2011", voteAverage: 8.3),
            movieItem(id: 13, title: "Forrest Gump", year: "1994", voteAverage: 8.5),
            tvItem(id: 1396, title: "Breaking Bad", year: "2008", voteAverage: 9.5),
            movieItem(id: 155, title: "The Dark Knight", year: "2008", voteAverage: 9.0),
            tvItem(id: 66732, title: "Stranger Things", year: "2016", voteAverage: 8.6),
            movieItem(id: 680, title: "Pulp Fiction", year: "1994", voteAverage: 8.5),
            tvItem(id: 1402, title: "The Walking Dead", year: "2010", voteAverage: 7.9)
        ]
    }

    // MARK: - SeerrMovieDetail

    static var previewMovieDetail: SeerrMovieDetail {
        SeerrMovieDetail(
            id: 550,
            imdbId: "tt0137523",
            adult: false,
            backdropPath: nil,
            posterPath: nil,
            budget: 63000000,
            genres: [
                SeerrGenre(id: 18, name: "Drama"),
                SeerrGenre(id: 53, name: "Thriller")
            ],
            homepage: nil,
            relatedVideos: nil,
            originalLanguage: "en",
            originalTitle: "Fight Club",
            overview: "A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy. Its an odd mix of therapist and patient as their offbeat, antiestablishment outlook spawns a massive underground group.",
            popularity: 61.4,
            productionCompanies: [
                SeerrProductionCompany(id: 508, logoPath: nil, originCountry: "US", name: "Regency Enterprises")
            ],
            releaseDate: "1999-10-15",
            releases: nil,
            revenue: 100853753,
            runtime: 139,
            status: "Released",
            tagline: "Mischief. Mayhem. Soap.",
            title: "Fight Club",
            voteAverage: 8.439,
            voteCount: 26723,
            credits: nil,
            collection: nil,
            mediaInfo: SeerrMediaInfo(
                id: 1,
                tmdbId: 550,
                tvdbId: nil,
                status: LureConstants.MediaStatus.available.rawValue,
                requests: nil,
                seasons: nil,
                mediaType: "movie",
                plexUrl: nil,
                serviceUrl: nil
            ),
            externalIds: nil,
            watchProviders: nil
        )
    }

    static var previewMovieDetailRequested: SeerrMovieDetail {
        SeerrMovieDetail(
            id: 13,
            imdbId: "tt0109830",
            adult: false,
            backdropPath: nil,
            posterPath: nil,
            budget: 55000000,
            genres: [SeerrGenre(id: 35, name: "Comedy"), SeerrGenre(id: 18, name: "Drama")],
            homepage: nil,
            relatedVideos: nil,
            originalLanguage: "en",
            originalTitle: "Forrest Gump",
            overview: "A man with a low IQ has accomplished great things in his life and has been present during significant historic events.",
            popularity: 71.2,
            productionCompanies: nil,
            releaseDate: "1994-07-06",
            releases: nil,
            revenue: 678226465,
            runtime: 142,
            status: "Released",
            tagline: "The world will never be the same once you've seen it through the eyes of Forrest Gump.",
            title: "Forrest Gump",
            voteAverage: 8.477,
            voteCount: 24518,
            credits: nil,
            collection: nil,
            mediaInfo: SeerrMediaInfo(
                id: 2,
                tmdbId: 13,
                tvdbId: nil,
                status: LureConstants.MediaStatus.pending.rawValue,
                requests: nil,
                seasons: nil,
                mediaType: "movie",
                plexUrl: nil,
                serviceUrl: nil
            ),
            externalIds: nil,
            watchProviders: nil
        )
    }

    // MARK: - DetailPosterHeroAction

    static var playAction: DetailPosterHeroAction {
        DetailPosterHeroAction(title: "Play", systemImage: "play.fill", isEnabled: true) {}
    }

    static var requestAction: DetailPosterHeroAction {
        DetailPosterHeroAction(title: "Request", systemImage: "plus.circle.fill", isEnabled: true) {}
    }

    static var addToFavoritesAction: DetailPosterHeroAction {
        DetailPosterHeroAction(title: "Add to Favorites", systemImage: "plus", isEnabled: true, isHighlighted: false) {}
    }

    // MARK: - DetailHeroRatingItem

    static var sampleRatingItems: [DetailHeroRatingItem] {
        [
            DetailHeroRatingItem(label: "IMDb", value: "8.4"),
            DetailHeroRatingItem(label: "TMDb", value: "84%"),
            DetailHeroRatingItem(label: "RT", value: "91%"),
            DetailHeroRatingItem(label: "Audience", value: "82%")
        ]
    }

    // MARK: - DetailBadge

    static var sampleBadges: [DetailBadge] {
        [
            DetailBadge(icon: "shield", label: "R", color: .yellow),
            DetailBadge(icon: "checkmark.circle.fill", label: "Available", color: .green)
        ]
    }

    // MARK: - SearchGenreTile

    static var sampleGenreTiles: [SearchGenreTile] {
        [
            SearchGenreTile(genreID: 28,    mediaType: "movie", name: "Action",       artworkURL: nil),
            SearchGenreTile(genreID: 12,    mediaType: "movie", name: "Adventure",    artworkURL: nil),
            SearchGenreTile(genreID: 16,    mediaType: "movie", name: "Animation",    artworkURL: nil),
            SearchGenreTile(genreID: 35,    mediaType: "movie", name: "Comedy",       artworkURL: nil),
            SearchGenreTile(genreID: 80,    mediaType: "movie", name: "Crime",        artworkURL: nil),
            SearchGenreTile(genreID: 18,    mediaType: "movie", name: "Drama",        artworkURL: nil),
            SearchGenreTile(genreID: 27,    mediaType: "movie", name: "Horror",       artworkURL: nil),
            SearchGenreTile(genreID: 878,   mediaType: "movie", name: "Sci-Fi",       artworkURL: nil),
            SearchGenreTile(genreID: 10749, mediaType: "movie", name: "Romance",      artworkURL: nil),
            SearchGenreTile(genreID: 53,    mediaType: "movie", name: "Thriller",     artworkURL: nil),
            SearchGenreTile(genreID: 10759, mediaType: "tv",    name: "Action & Adventure", artworkURL: nil),
            SearchGenreTile(genreID: 10751, mediaType: "tv",    name: "Family",       artworkURL: nil)
        ]
    }
}
#endif
