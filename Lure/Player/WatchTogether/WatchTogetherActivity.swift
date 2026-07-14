import GroupActivities

/// SharePlay activity carrying the media being watched. Both participants must be on
/// the same Jellyfin server (v1 scope): a `PlayableMedia.itemId` resolved on one
/// device is directly valid on the other's, so no cross-server title resolution is
/// needed. `WatchTogetherCoordinator` uses this purely to get both sides watching the
/// same title in the same room -- actual playback sync rides over `GroupSessionMessenger`
/// as `SyncMessage`s, not over `AVPlayerPlaybackCoordinator`.
struct WatchTogetherActivity: GroupActivity, Codable {
    let media: PlayableMedia

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .watchTogether
        metadata.title = media.title
        metadata.subtitle = media.episodeLabel
        metadata.supportsContinuationOnTV = true
        return metadata
    }
}
