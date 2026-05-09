import Foundation

struct PlayerPresentation: Identifiable {
    let id = UUID()
    let vm: PlayerViewModel
    let itemId: String
    let title: String
    let episodeLabel: String?
    let serviceUrl: String?
    let tmdbId: Int?
    let releaseYear: Int?
    let mediaType: String
}
