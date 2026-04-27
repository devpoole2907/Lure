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
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }

    var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    var trailerURL: URL? {
        guard let video = relatedVideos?.first(where: { $0.type == "Trailer" && $0.site == "YouTube" }),
              let key = video.key else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
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
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }

    var year: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }

    var trailerURL: URL? {
        guard let video = relatedVideos?.first(where: { $0.type == "Trailer" && $0.site == "YouTube" }),
              let key = video.key else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
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

    private static let isoFormatter = ISO8601DateFormatter()
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

struct SeerrRatingsCombined: Codable, Sendable {
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
}
