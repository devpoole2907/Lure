import Foundation

struct MediaArtwork: Equatable, Sendable {
    let backdropURL: URL?
    let logoURL: URL?
}

actor MediaArtworkService {
    static let shared = MediaArtworkService()

    private struct CacheKey: Hashable {
        let mediaType: String
        let tmdbId: Int
    }

    private let session: URLSession
    private let tmdbReadToken: String?
    private let tmdbAPIKey: String?
    private let fanartTVAPIKey: String?
    private var cache: [CacheKey: MediaArtwork] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
        self.tmdbReadToken = Self.configuredValue(infoKey: "TMDBReadAccessToken", envKey: "LURE_TMDB_READ_TOKEN")
        self.tmdbAPIKey = Self.configuredValue(infoKey: "TMDBAPIKey", envKey: "LURE_TMDB_API_KEY")
        self.fanartTVAPIKey = Self.configuredValue(infoKey: "FanartTVAPIKey", envKey: "LURE_FANART_API_KEY")
    }

    func artwork(
        mediaType: String,
        tmdbId: Int,
        fallbackBackdropURL: URL?,
        fallbackPosterURL: URL?
    ) async -> MediaArtwork {
        let normalizedType = mediaType == "tv" ? "tv" : "movie"
        let key = CacheKey(mediaType: normalizedType, tmdbId: tmdbId)
        if let cached = cache[key] {
            return MediaArtwork(
                backdropURL: cached.backdropURL ?? fallbackBackdropURL ?? fallbackPosterURL,
                logoURL: cached.logoURL
            )
        }

        async let tmdbImages = fetchTMDBImages(mediaType: normalizedType, tmdbId: tmdbId)
        async let fanartLogo = fetchFanartMovieLogo(mediaType: normalizedType, tmdbId: tmdbId)

        let images = await tmdbImages
        let providerArtwork = MediaArtwork(
            backdropURL: images?.bestBackdropURL,
            logoURL: await fanartLogo ?? images?.bestLogoURL
        )
        cache[key] = providerArtwork
        return MediaArtwork(
            backdropURL: providerArtwork.backdropURL ?? fallbackBackdropURL ?? fallbackPosterURL,
            logoURL: providerArtwork.logoURL
        )
    }

    private func fetchTMDBImages(mediaType: String, tmdbId: Int) async -> TMDBImageResponse? {
        guard tmdbReadToken != nil || tmdbAPIKey != nil else { return nil }

        guard var components = URLComponents(string: "https://api.themoviedb.org/3/\(mediaType)/\(tmdbId)/images") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "include_image_language", value: preferredImageLanguages.joined(separator: ","))
        ]
        if let tmdbAPIKey {
            components.queryItems?.append(URLQueryItem(name: "api_key", value: tmdbAPIKey))
        }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        if let tmdbReadToken {
            request.setValue("Bearer \(tmdbReadToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(TMDBImageResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func fetchFanartMovieLogo(mediaType: String, tmdbId: Int) async -> URL? {
        guard mediaType == "movie", let fanartTVAPIKey else { return nil }

        guard var components = URLComponents(string: "https://webservice.fanart.tv/v3/movies/\(tmdbId)") else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "api_key", value: fanartTVAPIKey)]
        guard let url = components.url else { return nil }

        do {
            let (data, urlResponse) = try await session.data(from: url)
            guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let response = try JSONDecoder().decode(FanartMovieResponse.self, from: data)
            return response.bestLogoURL
        } catch {
            return nil
        }
    }

    private var preferredImageLanguages: [String] {
        var languages: [String] = []
        if let language = Locale.current.language.languageCode?.identifier, !language.isEmpty {
            languages.append(language)
        }
        languages.append("en")
        languages.append("null")
        var seen = Set<String>()
        return languages.filter { seen.insert($0).inserted }
    }

    private static func configuredValue(infoKey: String, envKey: String) -> String? {
        let infoValue = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String
        let envValue = ProcessInfo.processInfo.environment[envKey]

        return [infoValue, envValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { value in
                !value.isEmpty && !value.hasPrefix("$(")
            }
    }
}

private struct TMDBImageResponse: Decodable, Sendable {
    let backdrops: [TMDBArtworkImage]
    let logos: [TMDBArtworkImage]

    var bestBackdropURL: URL? {
        bestImage(from: backdrops, preferTextless: true).flatMap {
            ImageURL.backdrop($0.filePath, size: .large)
        }
    }

    var bestLogoURL: URL? {
        bestImage(from: logos, preferTextless: false).flatMap {
            ImageURL.logo($0.filePath)
        }
    }

    private func bestImage(from images: [TMDBArtworkImage], preferTextless: Bool) -> TMDBArtworkImage? {
        images
            .filter { $0.filePath?.isEmpty == false }
            .sorted { lhs, rhs in
                let lhsRank = languageRank(lhs.iso6391, preferTextless: preferTextless)
                let rhsRank = languageRank(rhs.iso6391, preferTextless: preferTextless)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.voteCount != rhs.voteCount { return lhs.voteCount > rhs.voteCount }
                if lhs.voteAverage != rhs.voteAverage { return lhs.voteAverage > rhs.voteAverage }
                return lhs.width > rhs.width
            }
            .first
    }

    private func languageRank(_ language: String?, preferTextless: Bool) -> Int {
        let normalized = language?.lowercased()
        if preferTextless, normalized == nil { return 0 }
        if normalized == Locale.current.language.languageCode?.identifier.lowercased() { return preferTextless ? 1 : 0 }
        if normalized == "en" { return preferTextless ? 2 : 1 }
        if normalized == nil { return preferTextless ? 0 : 2 }
        return 3
    }
}

private struct TMDBArtworkImage: Decodable, Sendable {
    let filePath: String?
    let iso6391: String?
    let width: Int
    let voteAverage: Double
    let voteCount: Int

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case iso6391 = "iso_639_1"
        case width
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        self.iso6391 = try container.decodeIfPresent(String.self, forKey: .iso6391)
        self.width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 0
        self.voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage) ?? 0
        self.voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount) ?? 0
    }
}

private struct FanartMovieResponse: Decodable, Sendable {
    let hdmovielogo: [FanartArtworkImage]?
    let movielogo: [FanartArtworkImage]?

    var bestLogoURL: URL? {
        ((hdmovielogo ?? []) + (movielogo ?? []))
            .filter { $0.url != nil }
            .sorted { lhs, rhs in
                let lhsRank = languageRank(lhs.lang)
                let rhsRank = languageRank(rhs.lang)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.likesValue > rhs.likesValue
            }
            .first?
            .url
    }

    private func languageRank(_ language: String?) -> Int {
        let normalized = language?.lowercased()
        if normalized == Locale.current.language.languageCode?.identifier.lowercased() { return 0 }
        if normalized == "en" { return 1 }
        if normalized == nil { return 2 }
        return 3
    }
}

private struct FanartArtworkImage: Decodable, Sendable {
    let url: URL?
    let lang: String?
    let likes: String?

    var likesValue: Int {
        likes.flatMap(Int.init) ?? 0
    }
}
