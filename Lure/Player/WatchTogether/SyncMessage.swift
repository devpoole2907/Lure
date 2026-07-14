import Foundation

/// Wire message carried by `GroupSessionMessenger` between Watch Together participants.
/// Play/pause/seek/rateChanged are sent reliably (default `GroupSessionMessenger`
/// delivery mode); `heartbeat` is a periodic best-effort drift check sent only by the
/// session originator. Any participant may send play/pause/seek -- control isn't
/// host-locked.
enum SyncMessage: Codable, Sendable {
    case play(position: Double)
    case pause(position: Double)
    case seek(position: Double)
    case rateChanged(Float)
    case heartbeat(position: Double, isPlaying: Bool)
    /// Broadcast when a participant's item changes in-session (e.g. next episode,
    /// picking a different title) so the other side follows along instead of getting
    /// nudged by play/pause/seek messages for a player that's on the wrong item
    /// (ISSUE watch-together #3).
    case mediaChanged(itemId: String, title: String, episodeLabel: String?)
}
