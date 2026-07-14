import Foundation

enum ImageURL {
    static func originalTMDBImageURL(_ url: URL?) -> URL? {
        guard let url,
              url.host?.localizedCaseInsensitiveCompare("image.tmdb.org") == .orderedSame,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var pathSegments = components.percentEncodedPath
            .split(separator: "/")
            .map(String.init)
        guard let providerIndex = pathSegments.firstIndex(of: "p"),
              pathSegments.indices.contains(providerIndex + 1) else {
            return url
        }

        pathSegments[providerIndex + 1] = "original"
        components.percentEncodedPath = "/" + pathSegments.joined(separator: "/")
        return components.url ?? url
    }

    static func poster(_ path: String?, size: PosterSize = .medium) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: size.baseURL + path)
    }

    static func backdrop(_ path: String?, size: BackdropSize = .large) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: size.baseURL + path)
    }

    static func logo(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: LureConstants.TMDB.imageBaseURL + "original" + path)
    }

    static func profile(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: LureConstants.TMDB.profileMedium + path)
    }

    enum PosterSize {
        case small, medium, large, xlarge, original

        var baseURL: String {
            switch self {
            case .small: LureConstants.TMDB.posterSmall
            case .medium: LureConstants.TMDB.posterMedium
            case .large: LureConstants.TMDB.posterLarge
            case .xlarge: LureConstants.TMDB.posterXLarge
            case .original: LureConstants.TMDB.posterOriginal
            }
        }
    }

    enum BackdropSize {
        case small, large, original

        var baseURL: String {
            switch self {
            case .small: LureConstants.TMDB.backdropSmall
            case .large: LureConstants.TMDB.backdropLarge
            case .original: LureConstants.TMDB.backdropOriginal
            }
        }
    }
}
