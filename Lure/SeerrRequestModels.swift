import Foundation

// MARK: - Request (response)

struct SeerrMediaRequest: Codable, Identifiable, Sendable {
    let id: Int
    let status: Int                    // RequestStatus enum
    let media: SeerrRequestMedia?
    let requestedBy: SeerrUser?
    let modifiedBy: SeerrUser?
    let createdAt: String?
    let updatedAt: String?
    let type: String?                  // "movie" or "tv"
    let is4k: Bool?
    let serverId: Int?
    let profileId: Int?
    let rootFolder: String?
    let tags: [Int]?
    let seasons: [SeerrSeasonRequest]?

    var requestStatus: LureConstants.RequestStatus? {
        LureConstants.RequestStatus(rawValue: status)
    }

    var displayTitle: String {
        media?.displayTitle ?? "Unknown"
    }

    var isMovie: Bool { type == "movie" }
    var isTv: Bool { type == "tv" }
    var qualityLabel: String { is4k == true ? "4K" : "HD" }
    var isActive: Bool {
        guard let requestStatus else { return false }
        return requestStatus != .declined && requestStatus != .failed
    }
}

struct SeerrRequestMedia: Codable, Sendable {
    let id: Int?
    let tmdbId: Int?
    let tvdbId: Int?
    let status: Int?
    let mediaType: String?
    let title: String?
    let originalTitle: String?
    let name: String?
    let originalName: String?
    let posterPath: String?

    var posterURL: URL? { ImageURL.poster(posterPath) }
    var displayTitle: String { title ?? name ?? originalTitle ?? originalName ?? "Unknown" }

    var mediaStatus: LureConstants.MediaStatus? {
        guard let status else { return nil }
        return LureConstants.MediaStatus(rawValue: status)
    }
}

struct SeerrSeasonRequest: Codable, Identifiable, Sendable {
    let id: Int
    let seasonNumber: Int
    let status: Int

    var requestStatus: LureConstants.RequestStatus? {
        LureConstants.RequestStatus(rawValue: status)
    }
}

// MARK: - Request List Response

struct SeerrRequestListResponse: Codable, Sendable {
    let pageInfo: SeerrPageInfo
    let results: [SeerrMediaRequest]
}

// MARK: - Request Count

struct SeerrRequestCount: Codable, Sendable {
    let total: Int?
    let movie: Int?
    let tv: Int?
    let pending: Int?
    let approved: Int?
    let processing: Int?
    let available: Int?
    let declined: Int?
    let failed: Int?
    let completed: Int?
}

// MARK: - Create Request Body

struct SeerrCreateRequestBody: Codable, Sendable {
    let mediaType: String          // "movie" or "tv"
    let mediaId: Int               // TMDb ID
    let is4k: Bool?
    let serverId: Int?
    let profileId: Int?
    let rootFolder: String?
    let seasons: [Int]?            // Season numbers (TV only)
    let tags: [Int]?
    let userId: Int?               // Request on behalf of (admin only)
}

// MARK: - Discover Slider Config

struct SeerrDiscoverSlider: Codable, Identifiable, Sendable {
    let id: Int
    let type: Int?
    let title: String?
    let isBuiltIn: Bool?
    let enabled: Bool?
    let data: String?              // JSON string with slider parameters

    /// The API endpoint this slider points to
    var endpoint: String? {
        // Built-in sliders map to standard endpoints
        // Custom sliders have data JSON with genre/keyword filters
        switch type {
        case 1: "/api/v1/discover/trending"
        case 2: "/api/v1/discover/movies"
        case 3: "/api/v1/discover/tv"
        case 4: "/api/v1/discover/movies/upcoming"
        case 5: "/api/v1/discover/movies"        // Popular movies
        case 6: "/api/v1/discover/tv"             // Popular TV
        default: nil
        }
    }
}
