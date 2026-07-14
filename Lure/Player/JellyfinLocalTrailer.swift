import Foundation

/// Lightweight trailer metadata returned by Jellyfin's LocalTrailers endpoint.
/// Playback details are resolved only when the user selects the trailer.
struct JellyfinLocalTrailer: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let thumbnailURL: URL?
}
