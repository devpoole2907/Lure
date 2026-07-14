import Foundation

/// Stable value passed across the app/player boundary.
///
/// Keep this free of view models and persistence objects so the same payload can
/// later travel to a macOS player window, a tvOS player scene, or a fallback engine.
struct PlayableMedia: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Hashable, Codable, Sendable {
        case movie
        case tv
        case trailer

        init(mediaType: String) {
            switch mediaType.lowercased() {
            case "tv": self = .tv
            case "trailer": self = .trailer
            default: self = .movie
            }
        }
    }

    let id: String
    let itemId: String?
    let title: String
    let episodeLabel: String?
    let serviceUrl: String?
    let tmdbId: Int?
    let releaseYear: Int?
    let kind: Kind

    var mediaType: String { kind.rawValue }

    init(
        itemId: String?,
        title: String,
        episodeLabel: String? = nil,
        serviceUrl: String? = nil,
        tmdbId: Int? = nil,
        releaseYear: Int? = nil,
        kind: Kind
    ) {
        self.itemId = itemId?.nilIfEmpty
        self.title = title
        self.episodeLabel = episodeLabel
        self.serviceUrl = serviceUrl
        self.tmdbId = tmdbId
        self.releaseYear = releaseYear
        self.kind = kind
        id = [
            self.itemId,
            serviceUrl,
            tmdbId.map(String.init),
            kind.rawValue,
            title
        ]
        .compactMap { $0?.nilIfEmpty }
        .joined(separator: ":")
    }

    init(
        itemId: String,
        title: String,
        episodeLabel: String? = nil,
        serviceUrl: String? = nil,
        tmdbId: Int? = nil,
        releaseYear: Int? = nil,
        mediaType: String
    ) {
        self.init(
            itemId: itemId,
            title: title,
            episodeLabel: episodeLabel,
            serviceUrl: serviceUrl,
            tmdbId: tmdbId,
            releaseYear: releaseYear,
            kind: Kind(mediaType: mediaType)
        )
    }

    init(resumeItem item: JellyfinItem) {
        self.init(
            itemId: item.id,
            title: item.seriesName ?? item.name ?? "",
            episodeLabel: item.detailedEpisodeLabel,
            kind: item.type?.lowercased() == "episode" ? .tv : .movie
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
