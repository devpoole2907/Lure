import Foundation

struct TrailerShelfItem: Identifiable, Hashable, Sendable {
    enum Destination: Hashable, Sendable {
        case jellyfin(itemId: String)
        case youtube(videoId: String)
    }

    let id: String
    let title: String
    let thumbnailURL: URL?
    let sourceLabel: String
    let sourceIcon: String
    let destination: Destination

    static func preferred(
        localTrailers: [JellyfinLocalTrailer],
        youtubeVideos: [SeerrRelatedVideo],
        fallbackArtworkURL: URL?
    ) -> [Self] {
        if !localTrailers.isEmpty {
            var seen = Set<String>()
            return localTrailers.compactMap { trailer in
                guard seen.insert(trailer.id).inserted else { return nil }
                return Self(
                    id: "jellyfin:\(trailer.id)",
                    title: trailer.title,
                    thumbnailURL: trailer.thumbnailURL ?? fallbackArtworkURL,
                    sourceLabel: "Jellyfin",
                    sourceIcon: "play.tv.fill",
                    destination: .jellyfin(itemId: trailer.id)
                )
            }
        }

        var seen = Set<String>()
        return youtubeVideos.compactMap { video in
            guard let videoId = video.youtubeVideoId,
                  seen.insert(videoId).inserted
            else { return nil }

            let trimmedTitle = video.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = if let trimmedTitle, !trimmedTitle.isEmpty {
                trimmedTitle
            } else {
                "Trailer"
            }
            return Self(
                id: "youtube:\(videoId)",
                title: title,
                thumbnailURL: video.youtubeThumbnailURL,
                sourceLabel: "YouTube",
                sourceIcon: "play.rectangle.fill",
                destination: .youtube(videoId: videoId)
            )
        }
    }
}
