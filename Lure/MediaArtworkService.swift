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
        let language: String
    }

    private let session: URLSession
    private let workerBaseURL: URL
    private var cache: [CacheKey: MediaArtwork] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
        self.workerBaseURL = Self.configuredWorkerURL()
    }

    func artwork(
        mediaType: String,
        tmdbId: Int,
        fallbackBackdropURL: URL?,
        fallbackPosterURL: URL?
    ) async -> MediaArtwork {
        let normalizedType = mediaType == "tv" ? "tv" : "movie"
        let language = preferredLanguage
        let key = CacheKey(mediaType: normalizedType, tmdbId: tmdbId, language: language)

        if let cached = cache[key] {
            return MediaArtwork(
                backdropURL: cached.backdropURL ?? fallbackBackdropURL ?? fallbackPosterURL,
                logoURL: cached.logoURL
            )
        }

        let providerArtwork = await fetchArtwork(mediaType: normalizedType, tmdbId: tmdbId, language: language)
        cache[key] = providerArtwork

        return MediaArtwork(
            backdropURL: providerArtwork.backdropURL ?? fallbackBackdropURL ?? fallbackPosterURL,
            logoURL: providerArtwork.logoURL
        )
    }

    private func fetchArtwork(mediaType: String, tmdbId: Int, language: String) async -> MediaArtwork {
        guard var components = URLComponents(url: workerBaseURL.appendingPathComponent("artwork/\(mediaType)/\(tmdbId)"), resolvingAgainstBaseURL: false) else {
            return MediaArtwork(backdropURL: nil, logoURL: nil)
        }
        components.queryItems = [URLQueryItem(name: "language", value: language)]
        guard let url = components.url else {
            return MediaArtwork(backdropURL: nil, logoURL: nil)
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return MediaArtwork(backdropURL: nil, logoURL: nil)
            }
            let payload = try JSONDecoder().decode(ArtworkResponse.self, from: data)
            return MediaArtwork(
                backdropURL: payload.backdropUrl.flatMap(URL.init(string:)),
                logoURL: payload.logoUrl.flatMap(URL.init(string:))
            )
        } catch {
            return MediaArtwork(backdropURL: nil, logoURL: nil)
        }
    }

    private var preferredLanguage: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private static func configuredWorkerURL() -> URL {
        let infoValue = Bundle.main.object(forInfoDictionaryKey: "LureArtworkWorkerURL") as? String
        let envValue = ProcessInfo.processInfo.environment["LURE_ARTWORK_WORKER_URL"]
        let defaultURL = "https://lure-worker.james-5d8.workers.dev"

        let rawValue = [infoValue, envValue, defaultURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { value in
                !value.isEmpty && !value.hasPrefix("$(")
            } ?? defaultURL

        return URL(string: rawValue) ?? URL(string: defaultURL)!
    }
}

private struct ArtworkResponse: Decodable, Sendable {
    let backdropUrl: String?
    let logoUrl: String?
}
