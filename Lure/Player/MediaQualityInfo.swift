import SwiftUI

/// A single quality descriptor (resolution, dynamic range, codec, audio) derived
/// from a Jellyfin media source. Rendered as a chip on the movie detail view when
/// the title is present in the Jellyfin library.
struct MediaQualityBadge: Identifiable, Hashable {
    enum Kind: Hashable {
        case resolution
        case dynamicRange
        case audio
    }

    let kind: Kind
    let label: String

    var id: String { "\(kind)-\(label)" }

    var icon: String {
        switch kind {
        case .resolution: "tv"
        case .dynamicRange: "sparkles"
        case .audio: "waveform"
        }
    }

    var tint: Color {
        switch kind {
        case .resolution: .cyan
        case .dynamicRange: .orange
        case .audio: .pink
        }
    }
}

/// Quality summary for a playable Jellyfin item, built from the primary video and
/// default audio streams of its first media source.
struct MediaQualityInfo: Equatable {
    let badges: [MediaQualityBadge]

    var isEmpty: Bool { badges.isEmpty }

    /// Builds badges across *all* media sources (versions/copies) of an item.
    /// When a title has multiple copies with differing qualities — e.g. a 4K and a
    /// 1080p file — each distinct value gets its own chip; identical qualities are
    /// de-duplicated so we never show "1080p 1080p".
    init?(mediaSources: [JellyfinMediaSource]?) {
        guard let sources = mediaSources, !sources.isEmpty else { return nil }

        func videoStream(_ source: JellyfinMediaSource) -> JellyfinMediaStream? {
            source.mediaStreams?.first { $0.type == "Video" }
        }
        func audioStream(_ source: JellyfinMediaSource) -> JellyfinMediaStream? {
            source.mediaStreams?.first { $0.type == "Audio" && $0.isDefault == true }
                ?? source.mediaStreams?.first { $0.type == "Audio" }
        }

        let resolutions = sources.compactMap { source in
            Self.resolutionLabel(width: videoStream(source)?.width, height: videoStream(source)?.height)
        }
        let ranges = sources.compactMap { source in
            Self.dynamicRangeLabel(videoRange: videoStream(source)?.videoRange, videoRangeType: videoStream(source)?.videoRangeType)
        }
        let audios = sources.compactMap { source in
            Self.audioLabel(codec: audioStream(source)?.codec, channels: audioStream(source)?.channels, displayTitle: audioStream(source)?.displayTitle)
        }

        var badges: [MediaQualityBadge] = []
        // Resolution chips ordered best-first (4K before 1080p).
        for label in Self.distinct(resolutions).sorted(by: { Self.resolutionRank($0) > Self.resolutionRank($1) }) {
            badges.append(MediaQualityBadge(kind: .resolution, label: label))
        }
        for label in Self.distinct(ranges) {
            badges.append(MediaQualityBadge(kind: .dynamicRange, label: label))
        }
        for label in Self.distinct(audios) {
            badges.append(MediaQualityBadge(kind: .audio, label: label))
        }

        guard !badges.isEmpty else { return nil }
        self.badges = badges
    }

    /// First-occurrence-preserving de-duplication.
    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func resolutionRank(_ label: String) -> Int {
        switch label {
        case "4K": 4
        case "1080p": 3
        case "720p": 2
        case "SD": 1
        default: 0
        }
    }

    // MARK: - Derivation

    private static func resolutionLabel(width: Int?, height: Int?) -> String? {
        // Use width as the primary signal — cinematic aspect ratios shrink height
        // (e.g. 1080p scope content is only ~800px tall) but keep a stable width.
        let w = width ?? 0
        let h = height ?? 0
        let widest = max(w, h)
        switch widest {
        case 3000...: return "4K"
        case 1900...: return "1080p"
        case 1200...: return "720p"
        case 1...: return "SD"
        default: return nil
        }
    }

    private static func dynamicRangeLabel(videoRange: String?, videoRangeType: String?) -> String? {
        let type = (videoRangeType ?? "").uppercased()
        let range = (videoRange ?? "").uppercased()

        if type.contains("DOVI") || type.contains("DV") {
            return "Dolby Vision"
        }
        if type.contains("HDR10PLUS") || type.contains("HDR10+") {
            return "HDR10+"
        }
        if type.contains("HDR10") {
            return "HDR10"
        }
        if type.contains("HLG") {
            return "HLG"
        }
        if range == "HDR" {
            return "HDR"
        }
        return nil
    }

    private static func audioLabel(codec: String?, channels: Int?, displayTitle: String?) -> String? {
        if let title = displayTitle, title.localizedCaseInsensitiveContains("atmos") {
            return "Dolby Atmos"
        }

        let codecName: String?
        switch codec?.lowercased() {
        case "eac3": codecName = "Dolby Digital+"
        case "ac3": codecName = "Dolby Digital"
        case "truehd": codecName = "Dolby TrueHD"
        case "dts", "dca": codecName = "DTS"
        case "dts-hd", "dtshd": codecName = "DTS-HD"
        case "aac": codecName = "AAC"
        case "flac": codecName = "FLAC"
        case "opus": codecName = "Opus"
        case "mp3": codecName = "MP3"
        case .some(let other) where !other.isEmpty: codecName = other.uppercased()
        default: codecName = nil
        }

        let layout = channelLayout(channels)

        switch (codecName, layout) {
        case let (name?, layout?): return "\(name) \(layout)"
        case let (name?, nil): return name
        case let (nil, layout?): return layout
        default: return nil
        }
    }

    private static func channelLayout(_ channels: Int?) -> String? {
        switch channels {
        case 1: return "Mono"
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case .some(let count) where count > 2: return "\(count)ch"
        default: return nil
        }
    }
}
