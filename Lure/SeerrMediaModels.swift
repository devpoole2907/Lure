import Foundation

// MARK: - Media Info (attached to every media result)

struct SeerrMediaInfo: Codable, Sendable {
    let id: Int?
    let tmdbId: Int?
    let tvdbId: Int?
    let status: Int?               // MediaStatus enum value (1-6)
    let requests: [SeerrMediaRequest]?
    let seasons: [SeerrSeasonStatus]?
    let mediaType: String?
    let plexUrl: String?
    let serviceUrl: String?

    var mediaStatus: LureConstants.MediaStatus? {
        guard let status else { return nil }
        return LureConstants.MediaStatus(rawValue: status)
    }

    var isAvailable: Bool { mediaStatus == .available }
    var isRequested: Bool {
        mediaStatus == .pending ||
        mediaStatus == .processing ||
        !activeRequests.isEmpty
    }

    var activeRequests: [SeerrMediaRequest] {
        (requests ?? []).filter(\.isActive)
    }

    var has4KRequest: Bool {
        activeRequests.contains { $0.is4k == true }
    }

    var hasHDRequest: Bool {
        activeRequests.contains { $0.is4k != true }
    }

    var requestStatusLabel: String? {
        guard !activeRequests.isEmpty else { return nil }
        switch (hasHDRequest, has4KRequest) {
        case (true, true):
            return "Requested HD + 4K"
        case (false, true):
            return "Requested 4K"
        case (true, false):
            return "Requested HD"
        default:
            return "Requested"
        }
    }
}

struct SeerrSeasonStatus: Codable, Sendable {
    let seasonNumber: Int
    let status: Int?
    let episodes: [SeerrEpisodeStatus]?

    var mediaStatus: LureConstants.MediaStatus? {
        guard let status else { return nil }
        return LureConstants.MediaStatus(rawValue: status)
    }
}

struct SeerrEpisodeStatus: Codable, Sendable {
    let id: Int?
    let episodeNumber: Int?
    let status: Int?
}

// MARK: - Movie Result (list/discover)

struct SeerrMovieResult: Codable, Identifiable, Sendable {
    let id: Int
    let mediaType: String?
    let popularity: Double?
    let posterPath: String?
    let backdropPath: String?
    let voteCount: Int?
    let voteAverage: Double?
    let genreIds: [Int]?
    let overview: String?
    let originalLanguage: String?
    let title: String?
    let originalTitle: String?
    let releaseDate: String?
    let adult: Bool?
    let mediaInfo: SeerrMediaInfo?

    var posterURL: URL? { ImageURL.poster(posterPath) }
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }
    var displayTitle: String { title ?? originalTitle ?? "Unknown" }

    var year: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }
}

// MARK: - TV Result (list/discover)

struct SeerrTvResult: Codable, Identifiable, Sendable {
    let id: Int
    let mediaType: String?
    let popularity: Double?
    let posterPath: String?
    let backdropPath: String?
    let voteCount: Int?
    let voteAverage: Double?
    let genreIds: [Int]?
    let overview: String?
    let originalLanguage: String?
    let name: String?
    let originalName: String?
    let originCountry: [String]?
    let firstAirDate: String?
    let mediaInfo: SeerrMediaInfo?

    var posterURL: URL? { ImageURL.poster(posterPath) }
    var backdropURL: URL? { ImageURL.backdrop(backdropPath) }
    var displayTitle: String { name ?? originalName ?? "Unknown" }

    var year: String? {
        guard let firstAirDate, firstAirDate.count >= 4 else { return nil }
        return String(firstAirDate.prefix(4))
    }
}

// MARK: - Person Result

struct SeerrPersonResult: Codable, Identifiable, Sendable {
    let id: Int
    let profilePath: String?
    let adult: Bool?
    let mediaType: String?
    let name: String?
    let knownForDepartment: String?

    var profileURL: URL? { ImageURL.profile(profilePath) }
}

// MARK: - Combined Search/Discover Result

enum SeerrMediaItem: Identifiable, Sendable {
    case movie(SeerrMovieResult)
    case tv(SeerrTvResult)
    case person(SeerrPersonResult)

    var id: String {
        switch self {
        case .movie(let m): "movie-\(m.id)"
        case .tv(let t): "tv-\(t.id)"
        case .person(let p): "person-\(p.id)"
        }
    }

    var posterURL: URL? {
        switch self {
        case .movie(let m): m.posterURL
        case .tv(let t): t.posterURL
        case .person(let p): p.profileURL
        }
    }

    var title: String {
        switch self {
        case .movie(let m): m.displayTitle
        case .tv(let t): t.displayTitle
        case .person(let p): p.name ?? "Unknown"
        }
    }

    var year: String? {
        switch self {
        case .movie(let m): m.year
        case .tv(let t): t.year
        case .person: nil
        }
    }

    var voteAverage: Double? {
        switch self {
        case .movie(let m): m.voteAverage
        case .tv(let t): t.voteAverage
        case .person: nil
        }
    }

    var mediaType: String {
        switch self {
        case .movie: "movie"
        case .tv: "tv"
        case .person: "person"
        }
    }

    var mediaInfo: SeerrMediaInfo? {
        switch self {
        case .movie(let m): m.mediaInfo
        case .tv(let t): t.mediaInfo
        case .person: nil
        }
    }

    var tmdbId: Int {
        switch self {
        case .movie(let m): m.id
        case .tv(let t): t.id
        case .person(let p): p.id
        }
    }
}

// MARK: - Paginated Response

struct SeerrPageInfo: Codable, Sendable {
    let pages: Int?
    let pageSize: Int?
    let results: Int?
    let page: Int?
}

struct SeerrDiscoverResponse: Codable, Sendable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [SeerrMixedResult]
}

/// The discover/search endpoints return mixed types. We decode based on `mediaType`.
struct SeerrMixedResult: Codable, Sendable {
    let id: Int
    let mediaType: String?

    // Movie fields
    let title: String?
    let originalTitle: String?
    let releaseDate: String?

    // TV fields
    let name: String?
    let originalName: String?
    let firstAirDate: String?
    let originCountry: [String]?

    // Person fields
    let profilePath: String?
    let knownForDepartment: String?

    // Shared fields
    let popularity: Double?
    let posterPath: String?
    let backdropPath: String?
    let voteCount: Int?
    let voteAverage: Double?
    let genreIds: [Int]?
    let overview: String?
    let originalLanguage: String?
    let adult: Bool?
    let mediaInfo: SeerrMediaInfo?

    func toMediaItem() -> SeerrMediaItem {
        switch mediaType {
        case "movie":
            return .movie(SeerrMovieResult(
                id: id, mediaType: mediaType, popularity: popularity,
                posterPath: posterPath, backdropPath: backdropPath,
                voteCount: voteCount, voteAverage: voteAverage,
                genreIds: genreIds, overview: overview,
                originalLanguage: originalLanguage, title: title,
                originalTitle: originalTitle, releaseDate: releaseDate,
                adult: adult, mediaInfo: mediaInfo
            ))
        case "tv":
            return .tv(SeerrTvResult(
                id: id, mediaType: mediaType, popularity: popularity,
                posterPath: posterPath, backdropPath: backdropPath,
                voteCount: voteCount, voteAverage: voteAverage,
                genreIds: genreIds, overview: overview,
                originalLanguage: originalLanguage, name: name,
                originalName: originalName, originCountry: originCountry,
                firstAirDate: firstAirDate, mediaInfo: mediaInfo
            ))
        default:
            return .person(SeerrPersonResult(
                id: id, profilePath: profilePath, adult: adult,
                mediaType: mediaType, name: name ?? title,
                knownForDepartment: knownForDepartment
            ))
        }
    }
}

// MARK: - Genre

struct SeerrGenre: Codable, Identifiable, Sendable {
    let id: Int?
    let name: String?
}
