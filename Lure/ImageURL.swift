import Foundation

enum ImageURL {
    static func poster(_ path: String?, size: PosterSize = .medium) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: size.baseURL + path)
    }

    static func backdrop(_ path: String?, size: BackdropSize = .large) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: size.baseURL + path)
    }

    static func profile(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: LureConstants.TMDB.profileMedium + path)
    }

    enum PosterSize {
        case small, medium, large

        var baseURL: String {
            switch self {
            case .small: LureConstants.TMDB.posterSmall
            case .medium: LureConstants.TMDB.posterMedium
            case .large: LureConstants.TMDB.posterLarge
            }
        }
    }

    enum BackdropSize {
        case small, large

        var baseURL: String {
            switch self {
            case .small: LureConstants.TMDB.backdropSmall
            case .large: LureConstants.TMDB.backdropLarge
            }
        }
    }
}
