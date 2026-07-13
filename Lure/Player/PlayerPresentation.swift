import Foundation

struct PlayerPresentation: Identifiable {
    let id = UUID()
    let vm: PlayerViewModel?
    let media: PlayableMedia
}
