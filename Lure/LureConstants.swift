import Foundation

enum LureConstants {
    static let keychainService = "com.poole.james.Lure"

    enum TMDB {
        static let imageBaseURL = "https://image.tmdb.org/t/p/"
        static let posterSmall = imageBaseURL + "w185"
        static let posterMedium = imageBaseURL + "w342"
        static let posterLarge = imageBaseURL + "w500"
        static let posterXLarge = imageBaseURL + "w780"
        static let posterOriginal = imageBaseURL + "original"
        static let backdropSmall = imageBaseURL + "w300"
        static let backdropLarge = imageBaseURL + "w1280"
        static let profileMedium = imageBaseURL + "w185"
    }

    enum MediaStatus: Int, Codable, Sendable {
        case unknown = 1
        case pending = 2
        case processing = 3
        case partiallyAvailable = 4
        case available = 5
        case deleted = 6
    }

    enum RequestStatus: Int, Codable, Sendable {
        case pending = 1
        case approved = 2
        case declined = 3
        case failed = 4
        case completed = 5
    }
}
