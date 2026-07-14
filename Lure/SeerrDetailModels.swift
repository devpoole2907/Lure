import Foundation

// MARK: - Movie Detail

struct SeerrMovieDetail: Codable, Identifiable, Sendable {
    let id: Int
    let imdbId: String?
    let adult: Bool?
    let backdropPath: String?
    let posterPath: String?
    let budget: Int?
    let genres: [SeerrGenre]?
    let homepage: String?
    let relatedVideos: [SeerrRelatedVideo]?
    let originalLanguage: String?
    let originalTitle: String?
    let overview: String?
    let popularity: Double?
    let productionCompanies: [SeerrProductionCompany]?
    let releaseDate: String?
    let releases: SeerrReleaseResults?
    let revenue: Int?
    let runtime: Int?
    let status: String?
    let tagline: String?
    let title: String?
    let voteAverage: Double?
    let voteCount: Int?
    let credits: SeerrCredits?
    let collection: SeerrCollection?
    let mediaInfo: SeerrMediaInfo?
    let externalIds: SeerrExternalIds?
    let watchProviders: [SeerrWatchProviders]?

    var displayTitle: String { title ?? originalTitle ?? "Unknown" }
    var posterURL: URL? { ImageURL.poster(posterPath, size: .large) }
    /// Full-resolution poster for the full-bleed detail hero (w500 looks soft there).
    var heroPosterURL: URL? { ImageURL.poster(posterPath, size: .original) }
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }
    var heroBackdropURL: URL? { ImageURL.backdrop(backdropPath, size: .original) }
    var runtimeText: String? { Self.runtimeText(minutes: runtime) }

    var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    var trailerVideos: [SeerrRelatedVideo] {
        SeerrRelatedVideo.uniqueYouTubeTrailers(in: relatedVideos)
    }

    var trailerURL: URL? {
        trailerVideos.first?.youtubeURL
    }

    /// US content certification (e.g. "PG-13", "R"). Falls back to first available region.
    var certificationText: String? {
        let dates = releases?.preferredReleaseDates ?? []
        let typeOrder = [3, 2, 1, 4, 5, 6]
        let sorted = dates.sorted { a, b in
            let ai = typeOrder.firstIndex(of: a.type ?? 0) ?? 99
            let bi = typeOrder.firstIndex(of: b.type ?? 0) ?? 99
            return ai < bi
        }
        return sorted.compactMap { date -> String? in
            guard let cert = date.certification, !cert.isEmpty else { return nil }
            return cert
        }.first
    }

    /// US watch providers (streaming). Falls back to first available region.
    var usWatchProviders: SeerrWatchProviders? {
        preferredWatchProviders
    }

    var preferredWatchProviders: SeerrWatchProviders? {
        Self.preferredWatchProviders(from: watchProviders)
    }

    static func preferredWatchProviders(from providers: [SeerrWatchProviders]?) -> SeerrWatchProviders? {
        guard let providers, !providers.isEmpty else { return nil }

        let preferredRegions = [Locale.current.region?.identifier, "US"].compactMap(\.self)
        for region in preferredRegions {
            if let provider = providers.first(where: {
                $0.iso_3166_1 == region && !$0.namedAvailabilityProviders.isEmpty
            }) {
                return provider
            }
        }

        return providers.first(where: { !$0.namedStreamingProviders.isEmpty })
            ?? providers.first(where: { !$0.namedAvailabilityProviders.isEmpty })
            ?? providers.first
    }

    var releaseAvailabilityText: String? {
        if mediaInfo?.isAvailable == true {
            return "Available to Watch"
        }

        let relevantReleaseDates = releases?.preferredReleaseDates ?? []
        let now = Date()
        let hasHomeRelease = relevantReleaseDates.contains {
            guard let type = $0.type, let releaseDate = $0.parsedDate else { return false }
            return (type == 4 || type == 5 || type == 6) && releaseDate <= now
        }
        if hasHomeRelease {
            return "Digital/Home Release"
        }

        let hasTheatricalRelease = relevantReleaseDates.contains {
            guard let type = $0.type, let releaseDate = $0.parsedDate else { return false }
            return (type == 2 || type == 3) && releaseDate <= now
        }
        if hasTheatricalRelease {
            return "In Theaters"
        }

        if let releaseDate = Self.releaseDateFormatter.date(from: releaseDate ?? ""), releaseDate > now {
            return "Coming Soon"
        }

        if releaseDate != nil {
            return "Released"
        }

        return nil
    }

    private static let releaseDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func runtimeText(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0, remainingMinutes > 0 {
            return "\(hours)h \(remainingMinutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - TV Detail

struct SeerrTVDetail: Codable, Identifiable, Sendable {
    let id: Int
    let backdropPath: String?
    let posterPath: String?
    let contentRatings: SeerrContentRatings?
    let createdBy: [SeerrCreator]?
    let episodeRunTime: [Int]?
    let firstAirDate: String?
    let genres: [SeerrGenre]?
    let homepage: String?
    let inProduction: Bool?
    let languages: [String]?
    let lastAirDate: String?
    let name: String?
    let originalName: String?
    let numberOfEpisodes: Int?
    let numberOfSeasons: Int?
    let originCountry: [String]?
    let originalLanguage: String?
    let overview: String?
    let popularity: Double?
    let productionCompanies: [SeerrProductionCompany]?
    let seasons: [SeerrTVSeason]?
    let status: String?            // "Returning Series", "Ended", etc.
    let tagline: String?
    let type: String?
    let voteAverage: Double?
    let voteCount: Int?
    let credits: SeerrCredits?
    let mediaInfo: SeerrMediaInfo?
    let externalIds: SeerrExternalIds?
    let relatedVideos: [SeerrRelatedVideo]?
    let networks: [SeerrNetwork]?
    let watchProviders: [SeerrWatchProviders]?

    var displayTitle: String { name ?? originalName ?? "Unknown" }
    var posterURL: URL? { ImageURL.poster(posterPath, size: .large) }
    /// Full-resolution poster for the full-bleed detail hero (w500 looks soft there).
    var heroPosterURL: URL? { ImageURL.poster(posterPath, size: .original) }
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }
    var heroBackdropURL: URL? { ImageURL.backdrop(backdropPath, size: .original) }
    var hasPlayableContent: Bool { mediaInfo?.hasPlayableTVContent == true }

    var year: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }

    var trailerVideos: [SeerrRelatedVideo] {
        SeerrRelatedVideo.uniqueYouTubeTrailers(in: relatedVideos)
    }

    var trailerURL: URL? {
        trailerVideos.first?.youtubeURL
    }

    /// US content rating (e.g. "TV-MA", "TV-14"). Falls back to first available region.
    var contentRatingText: String? {
        contentRatings?.results?.first(where: { $0.iso_3166_1 == "US" })?.rating
            ?? contentRatings?.results?.first?.rating
    }

    /// US watch providers (streaming). Falls back to first available region.
    var usWatchProviders: SeerrWatchProviders? {
        preferredWatchProviders
    }

    var preferredWatchProviders: SeerrWatchProviders? {
        SeerrMovieDetail.preferredWatchProviders(from: watchProviders)
    }

    /// Requestable seasons (non-specials, non-zero)
    var requestableSeasons: [SeerrTVSeason] {
        (seasons ?? []).filter { $0.seasonNumber > 0 && ($0.episodeCount ?? 0) > 0 }
    }
}

// MARK: - TV Season

struct SeerrTVSeason: Codable, Identifiable, Sendable {
    var id: Int { seasonNumber }
    let seasonNumber: Int
    let airDate: String?
    let episodeCount: Int?
    let name: String?
    let overview: String?
    let posterPath: String?
}

// MARK: - Supporting Types

struct SeerrRelatedVideo: Codable, Sendable {
    let url: String?
    let key: String?
    let name: String?
    let size: Int?
    let type: String?              // "Trailer", "Teaser", "Clip", etc.
    let site: String?              // "YouTube"

    var youtubeVideoId: String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isYouTubeTrailer: Bool {
        type?.caseInsensitiveCompare("Trailer") == .orderedSame &&
        site?.caseInsensitiveCompare("YouTube") == .orderedSame &&
        youtubeVideoId != nil
    }

    var youtubeURL: URL? {
        guard let youtubeVideoId else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(youtubeVideoId)")
    }

    var youtubeThumbnailURL: URL? {
        guard let youtubeVideoId else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(youtubeVideoId)/hqdefault.jpg")
    }

    static func uniqueYouTubeTrailers(in videos: [Self]?) -> [Self] {
        var seen = Set<String>()
        return (videos ?? []).filter { video in
            guard video.isYouTubeTrailer,
                  let videoId = video.youtubeVideoId
            else { return false }
            return seen.insert(videoId).inserted
        }
    }
}

struct SeerrReleaseResults: Codable, Sendable {
    let results: [SeerrReleaseCountry]?

    var preferredReleaseDates: [SeerrReleaseDate] {
        if let usDates = results?.first(where: { $0.iso31661 == "US" })?.releaseDates, !usDates.isEmpty {
            return usDates
        }
        return results?.flatMap(\.releaseDates) ?? []
    }
}

struct SeerrReleaseCountry: Codable, Sendable {
    let iso31661: String?
    let rating: String?
    let releaseDates: [SeerrReleaseDate]

    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case rating
        case releaseDates = "release_dates"
    }
}

struct SeerrReleaseDate: Codable, Sendable {
    let certification: String?
    let iso6391: String?
    let note: String?
    let releaseDate: String?
    let type: Int?

    enum CodingKeys: String, CodingKey {
        case certification
        case iso6391 = "iso_639_1"
        case note
        case releaseDate = "release_date"
        case type
    }

    var parsedDate: Date? {
        Self.isoFormatter.date(from: releaseDate ?? "")
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

struct SeerrProductionCompany: Codable, Identifiable, Sendable {
    let id: Int?
    let logoPath: String?
    let originCountry: String?
    let name: String?
}

struct SeerrNetwork: Codable, Identifiable, Sendable {
    let id: Int?
    let logoPath: String?
    let originCountry: String?
    let name: String?
}

struct SeerrCreator: Codable, Identifiable, Sendable {
    let id: Int?
    let name: String?
    let profilePath: String?
}

struct SeerrCredits: Codable, Sendable {
    let cast: [SeerrCastMember]?
    let crew: [SeerrCrewMember]?
}

struct SeerrCastMember: Codable, Identifiable, Sendable {
    let id: Int?
    let name: String?
    let character: String?
    let profilePath: String?
    let order: Int?

    var profileURL: URL? { ImageURL.profile(profilePath) }
}

struct SeerrCrewMember: Codable, Identifiable, Sendable {
    let id: Int?
    let name: String?
    let job: String?
    let department: String?
    let profilePath: String?
}

struct SeerrCollection: Codable, Identifiable, Sendable {
    let id: Int?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let overview: String?
    let parts: [SeerrMovieResult]?

    var posterURL: URL? { ImageURL.poster(posterPath, size: .medium) }
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }
}

struct SeerrCollectionsResponse: Codable, Sendable {
    let page: Int?
    let totalPages: Int?
    let totalResults: Int?
    let results: [SeerrCollection]
}

struct SeerrExternalIds: Codable, Sendable {
    let imdbId: String?
    let freebaseMid: String?
    let freebaseId: String?
    let tvdbId: Int?
    let tvrageId: Int?
    let facebookId: String?
    let instagramId: String?
    let twitterId: String?
}

struct SeerrContentRatings: Codable, Sendable {
    let results: [SeerrContentRating]?
}

struct SeerrContentRating: Codable, Sendable {
    let iso_3166_1: String?
    let rating: String?
}

struct SeerrWatchProviders: Codable, Sendable {
    let iso_3166_1: String?
    let link: String?
    let buy: [SeerrWatchProvider]?
    let flatrate: [SeerrWatchProvider]?
    let rent: [SeerrWatchProvider]?
    let free: [SeerrWatchProvider]?
    let ads: [SeerrWatchProvider]?

    var namedStreamingProviders: [SeerrWatchProvider] {
        uniqueNamedProviders(from: (flatrate ?? []) + (free ?? []) + (ads ?? []))
    }

    var namedAvailabilityProviders: [SeerrWatchProvider] {
        let streaming = namedStreamingProviders
        if !streaming.isEmpty { return streaming }
        return uniqueNamedProviders(from: (rent ?? []) + (buy ?? []))
    }

    private func uniqueNamedProviders(from providers: [SeerrWatchProvider]) -> [SeerrWatchProvider] {
        var seen: Set<String> = []
        return providers.filter { provider in
            guard let name = provider.providerName, !name.isEmpty else { return false }
            return seen.insert(provider.stableID).inserted
        }
    }
}

struct SeerrWatchProvider: Codable, Identifiable, Sendable {
    var id: Int? { providerId }
    let displayPriority: Int?
    let logoPath: String?
    let providerId: Int?
    let providerName: String?

    enum CodingKeys: String, CodingKey {
        case displayPriority = "display_priority"
        case logoPath = "logo_path"
        case providerId = "provider_id"
        case providerName = "provider_name"
    }

    var logoURL: URL? {
        guard let logoPath, !logoPath.isEmpty else { return nil }
        return URL(string: LureConstants.TMDB.imageBaseURL + "original" + logoPath)
    }

    var stableID: String {
        "\(providerId ?? -1)-\(providerName ?? "")-\(logoPath ?? "")"
    }
}

// MARK: - Person Detail

struct SeerrPersonDetail: Codable, Identifiable, Sendable {
    let id: Int
    let name: String?
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?

    var profileURL: URL? { ImageURL.profile(profilePath) }
}

struct SeerrPersonCombinedCredits: Codable, Sendable {
    let cast: [SeerrPersonCredit]?
    let crew: [SeerrPersonCredit]?
}

struct SeerrPersonCredit: Codable, Identifiable, Sendable {
    let id: Int
    let mediaType: String?
    let title: String?
    let originalTitle: String?
    let name: String?
    let originalName: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let genreIds: [Int]?
    let overview: String?
    let originalLanguage: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let adult: Bool?
    let originCountry: [String]?
    let character: String?
    let job: String?

    func toMediaItem() -> SeerrMediaItem? {
        switch mediaType {
        case "movie":
            return .movie(SeerrMovieResult(
                id: id,
                mediaType: mediaType,
                popularity: popularity,
                posterPath: posterPath,
                backdropPath: backdropPath,
                voteCount: voteCount,
                voteAverage: voteAverage,
                genreIds: genreIds,
                overview: overview,
                originalLanguage: originalLanguage,
                title: title,
                originalTitle: originalTitle,
                releaseDate: releaseDate,
                adult: adult,
                mediaInfo: nil
            ))
        case "tv":
            return .tv(SeerrTvResult(
                id: id,
                mediaType: mediaType,
                popularity: popularity,
                posterPath: posterPath,
                backdropPath: backdropPath,
                voteCount: voteCount,
                voteAverage: voteAverage,
                genreIds: genreIds,
                overview: overview,
                originalLanguage: originalLanguage,
                name: name,
                originalName: originalName,
                originCountry: originCountry,
                firstAirDate: firstAirDate,
                mediaInfo: nil
            ))
        default:
            return nil
        }
    }
}

/// Ratings for a movie/TV title. Seerr exposes two different JSON shapes:
/// the movie `ratingscombined` endpoint nests Rotten Tomatoes + IMDb under
/// `rt`/`imdb`, while the TV `ratings` endpoint returns the RT fields flat at
/// the top level. The custom decoder accepts either so both views work.
struct SeerrRatingsCombined: Sendable {
    let criticsRating: String?     // "Certified Fresh", "Fresh", "Rotten"
    let criticsScore: Int?
    let audienceRating: String?
    let audienceScore: Int?
    let imdbRating: Double?
    let tmdbRating: Double?

    var hasAnyScore: Bool {
        imdbRating != nil ||
        tmdbRating != nil ||
        criticsScore != nil ||
        audienceScore != nil
    }

    init(
        criticsRating: String? = nil,
        criticsScore: Int? = nil,
        audienceRating: String? = nil,
        audienceScore: Int? = nil,
        imdbRating: Double? = nil,
        tmdbRating: Double? = nil
    ) {
        self.criticsRating = criticsRating
        self.criticsScore = criticsScore
        self.audienceRating = audienceRating
        self.audienceScore = audienceScore
        self.imdbRating = imdbRating
        self.tmdbRating = tmdbRating
    }
}

extension SeerrRatingsCombined: Decodable {
    private struct RTBlock: Decodable {
        let criticsRating: String?
        let criticsScore: Int?
        let audienceRating: String?
        let audienceScore: Int?
    }

    private struct IMDBBlock: Decodable {
        let criticsScore: Double?
    }

    private enum CodingKeys: String, CodingKey {
        case rt, imdb
        case criticsRating, criticsScore, audienceRating, audienceScore
        case imdbRating, tmdbRating
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let rt = try? container.decodeIfPresent(RTBlock.self, forKey: .rt) {
            criticsRating = rt.criticsRating
            criticsScore = rt.criticsScore
            audienceRating = rt.audienceRating
            audienceScore = rt.audienceScore
        } else {
            criticsRating = try? container.decodeIfPresent(String.self, forKey: .criticsRating)
            criticsScore = try? container.decodeIfPresent(Int.self, forKey: .criticsScore)
            audienceRating = try? container.decodeIfPresent(String.self, forKey: .audienceRating)
            audienceScore = try? container.decodeIfPresent(Int.self, forKey: .audienceScore)
        }

        if let imdb = try? container.decodeIfPresent(IMDBBlock.self, forKey: .imdb) {
            imdbRating = imdb.criticsScore
        } else {
            imdbRating = try? container.decodeIfPresent(Double.self, forKey: .imdbRating)
        }

        tmdbRating = try? container.decodeIfPresent(Double.self, forKey: .tmdbRating)
    }
}

// MARK: - Detail → MediaItem conversion (used by LibraryViewModel)

extension SeerrMovieDetail {
    func toMediaItem() -> SeerrMediaItem {
        .movie(SeerrMovieResult(
            id: id, mediaType: "movie", popularity: popularity,
            posterPath: posterPath, backdropPath: backdropPath,
            voteCount: voteCount, voteAverage: voteAverage,
            genreIds: genres?.compactMap { $0.id }, overview: overview,
            originalLanguage: originalLanguage, title: title,
            originalTitle: originalTitle, releaseDate: releaseDate,
            adult: adult, mediaInfo: mediaInfo
        ))
    }

    func toLibraryItem(addedAt: Date? = nil) -> LibraryItem {
        LibraryItem(
            mediaType: "movie",
            tmdbId: id,
            title: displayTitle,
            year: year,
            voteAverage: voteAverage,
            posterURL: posterURL,
            isAvailable: mediaInfo?.isAvailable == true,
            addedAt: addedAt
        )
    }
}

extension SeerrTVDetail {
    func toMediaItem() -> SeerrMediaItem {
        .tv(SeerrTvResult(
            id: id, mediaType: "tv", popularity: popularity,
            posterPath: posterPath, backdropPath: backdropPath,
            voteCount: voteCount, voteAverage: voteAverage,
            genreIds: genres?.compactMap { $0.id }, overview: overview,
            originalLanguage: originalLanguage, name: name,
            originalName: originalName, originCountry: originCountry,
            firstAirDate: firstAirDate, mediaInfo: mediaInfo
        ))
    }

    func toLibraryItem(addedAt: Date? = nil) -> LibraryItem {
        LibraryItem(
            mediaType: "tv",
            tmdbId: id,
            title: displayTitle,
            year: year,
            voteAverage: voteAverage,
            posterURL: posterURL,
            isAvailable: hasPlayableContent,
            addedAt: addedAt
        )
    }
}
