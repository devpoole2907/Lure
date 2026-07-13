import Foundation

// MARK: - Auth

struct JellyfinAuthRequest: Encodable {
    let username: String
    let pw: String
    enum CodingKeys: String, CodingKey {
        case username = "Username"
        case pw = "Pw"
    }
}

struct JellyfinAuthResponse: Decodable, Sendable {
    let accessToken: String?
    let user: JellyfinUserInfo?
    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case user = "User"
    }
}

struct JellyfinUserInfo: Decodable, Sendable {
    let id: String?
    let name: String?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

// MARK: - Items

struct JellyfinItemsResponse: Decodable, Sendable {
    let items: [JellyfinItem]?
    let totalRecordCount: Int?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

struct JellyfinItem: Decodable, Sendable {
    let id: String?
    let name: String?
    let type: String?
    let productionYear: Int?
    let providerIds: [String: String]?
    let seriesId: String?
    let seriesName: String?
    let seasonId: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let userData: JellyfinUserData?
    let runTimeTicks: Int64?
    let dateCreated: String?
    let communityRating: Double?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case productionYear = "ProductionYear"
        case providerIds = "ProviderIds"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case seasonId = "SeasonId"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case userData = "UserData"
        case runTimeTicks = "RunTimeTicks"
        case dateCreated = "DateCreated"
        case communityRating = "CommunityRating"
        case overview = "Overview"
    }

    var resumePositionSeconds: Double {
        Double(userData?.playbackPositionTicks ?? 0) / 10_000_000
    }

    var durationSeconds: Double {
        Double(runTimeTicks ?? 0) / 10_000_000
    }

    var tmdbId: Int? {
        let raw = providerIds?["Tmdb"] ?? providerIds?["tmdb"] ?? providerIds?["TMDB"]
        return raw.flatMap(Int.init)
    }

    var episodeLabel: String? {
        guard let s = parentIndexNumber, let e = indexNumber else { return nil }
        return "S\(s) \u{00B7} E\(e)"
    }

    var resumeLabel: String? {
        let pos = resumePositionSeconds
        guard pos > 30 else { return nil }
        let dur = durationSeconds
        guard dur > 0 else { return nil }
        let m = Int(pos) / 60
        let s2 = Int(pos) % 60
        return "\(m):\(String(format: "%02d", s2))"
    }
}

struct JellyfinUserData: Decodable, Sendable {
    let playbackPositionTicks: Int64?
    let played: Bool?
    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case played = "Played"
    }
}

// MARK: - Seasons / Episodes

struct JellyfinSeasonsResponse: Decodable, Sendable {
    let items: [JellyfinSeason]?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

struct JellyfinSeason: Decodable, Identifiable, Sendable {
    let id: String?
    let name: String?
    let indexNumber: Int?
    let episodeCount: Int?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case indexNumber = "IndexNumber"
        case episodeCount = "ChildCount"
    }
}

struct JellyfinEpisodesResponse: Decodable, Sendable {
    let items: [JellyfinItem]?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

// MARK: - PlaybackInfo

struct JellyfinPlaybackInfoBody: Encodable {
    let deviceProfile: JellyfinDeviceProfile
    let userId: String
    let maxStreamingBitrate: Int
    let startTimeTicks: Int64?
    let enableDirectPlay: Bool
    let enableDirectStream: Bool
    let enableTranscoding: Bool
    let allowVideoStreamCopy: Bool
    let allowAudioStreamCopy: Bool
    let autoOpenLiveStream: Bool
    enum CodingKeys: String, CodingKey {
        case deviceProfile = "DeviceProfile"
        case userId = "UserId"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case startTimeTicks = "StartTimeTicks"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case allowVideoStreamCopy = "AllowVideoStreamCopy"
        case allowAudioStreamCopy = "AllowAudioStreamCopy"
        case autoOpenLiveStream = "AutoOpenLiveStream"
    }
}

struct JellyfinDeviceProfile: Encodable {
    let name: String
    let maxStaticBitrate: Int
    let maxStreamingBitrate: Int
    let directPlayProfiles: [JellyfinDirectPlayProfile]
    let transcodingProfiles: [JellyfinTranscodingProfile]
    let codecProfiles: [JellyfinCodecProfile]
    let subtitleProfiles: [JellyfinSubtitleProfile]
    let containerProfiles: [String]
    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maxStaticBitrate = "MaxStaticBitrate"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case codecProfiles = "CodecProfiles"
        case subtitleProfiles = "SubtitleProfiles"
        case containerProfiles = "ContainerProfiles"
    }

    static let aetherEngine = JellyfinDeviceProfile(
        name: "Lure (AetherEngine)",
        maxStaticBitrate: 200_000_000,
        maxStreamingBitrate: 200_000_000,
        directPlayProfiles: [
            JellyfinDirectPlayProfile(
                container: "mp4,m4v,mov,mkv,matroska,avi,mpegts,ts,ogg,webm,flv",
                type: "Video",
                videoCodec: "h264,hevc,av1,vp9",
                audioCodec: "aac,ac3,eac3,mp3,flac,opus,vorbis,alac,truehd,mlp,dts,dca,dts-hd,dtshd,pcm_s16le,pcm_s24le,pcm_f32le,pcm"
            ),
            JellyfinDirectPlayProfile(
                container: "mp3,aac,m4a,m4b,flac,alac,wav,opus,ogg",
                type: "Audio",
                videoCodec: nil,
                audioCodec: nil
            )
        ],
        transcodingProfiles: [
            JellyfinTranscodingProfile(
                container: "mp4",
                type: "Video",
                audioVideoProtocol: "http",
                videoCodec: "h264,hevc,av1,vp9",
                audioCodec: "aac,ac3,eac3",
                context: "Streaming"
            ),
            JellyfinTranscodingProfile(
                container: "mp3",
                type: "Audio",
                audioVideoProtocol: "http",
                videoCodec: nil,
                audioCodec: "mp3",
                context: "Streaming"
            )
        ],
        codecProfiles: [
            JellyfinCodecProfile(
                type: "Video",
                codec: "hevc",
                conditions: [
                    JellyfinCodecCondition(
                        condition: "EqualsAny",
                        property: "VideoProfile",
                        value: "main|main 10|main10",
                        isRequired: false
                    )
                ]
            )
        ],
        subtitleProfiles: [
            JellyfinSubtitleProfile(format: "srt", method: "Embed"),
            JellyfinSubtitleProfile(format: "ass", method: "Embed"),
            JellyfinSubtitleProfile(format: "ssa", method: "Embed"),
            JellyfinSubtitleProfile(format: "vtt", method: "Embed"),
            JellyfinSubtitleProfile(format: "pgs", method: "Embed"),
            JellyfinSubtitleProfile(format: "pgssub", method: "Embed"),
            JellyfinSubtitleProfile(format: "dvbsub", method: "Embed"),
            JellyfinSubtitleProfile(format: "dvdsub", method: "Embed"),
            JellyfinSubtitleProfile(format: "srt", method: "External"),
            JellyfinSubtitleProfile(format: "ass", method: "External"),
            JellyfinSubtitleProfile(format: "vtt", method: "External")
        ],
        containerProfiles: []
    )
}

struct JellyfinDirectPlayProfile: Encodable {
    let container: String
    let type: String
    let videoCodec: String?
    let audioCodec: String?
    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
    }
}

struct JellyfinTranscodingProfile: Encodable {
    let container: String
    let type: String
    let audioVideoProtocol: String
    let videoCodec: String?
    let audioCodec: String
    let context: String?
    enum CodingKeys: String, CodingKey {
        case container = "Container"
        case type = "Type"
        case audioVideoProtocol = "Protocol"
        case videoCodec = "VideoCodec"
        case audioCodec = "AudioCodec"
        case context = "Context"
    }
}

struct JellyfinCodecProfile: Encodable {
    let type: String
    let codec: String
    let conditions: [JellyfinCodecCondition]
    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
        case conditions = "Conditions"
    }
}

struct JellyfinCodecCondition: Encodable {
    let condition: String
    let property: String
    let value: String
    let isRequired: Bool
    enum CodingKeys: String, CodingKey {
        case condition = "Condition"
        case property = "Property"
        case value = "Value"
        case isRequired = "IsRequired"
    }
}

struct JellyfinSubtitleProfile: Encodable {
    let format: String
    let method: String
    enum CodingKeys: String, CodingKey {
        case format = "Format"
        case method = "Method"
    }
}

// MARK: - PlaybackInfo Response

struct JellyfinPlaybackInfoResponse: Decodable, Sendable {
    let mediaSources: [JellyfinMediaSource]?
    let playSessionId: String?
    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }
}

struct JellyfinMediaSource: Decodable, Sendable {
    let id: String?
    let name: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let transcodingUrl: String?
    let mediaStreams: [JellyfinMediaStream]?
    let runTimeTicks: Int64?
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case transcodingUrl = "TranscodingUrl"
        case mediaStreams = "MediaStreams"
        case runTimeTicks = "RunTimeTicks"
    }
}

struct JellyfinMediaStream: Decodable, Sendable {
    let index: Int?
    let type: String?
    let language: String?
    let displayTitle: String?
    let codec: String?
    let profile: String?
    let width: Int?
    let height: Int?
    let bitRate: Int?
    let videoRange: String?
    let videoRangeType: String?
    let channels: Int?
    let isDefault: Bool?
    let isExternal: Bool?
    let deliveryUrl: String?
    enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case language = "Language"
        case displayTitle = "DisplayTitle"
        case codec = "Codec"
        case profile = "Profile"
        case width = "Width"
        case height = "Height"
        case bitRate = "BitRate"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case channels = "Channels"
        case isDefault = "IsDefault"
        case isExternal = "IsExternal"
        case deliveryUrl = "DeliveryUrl"
    }
}

// MARK: - Media Segments

struct JellyfinMediaSegmentsResponse: Decodable, Sendable {
    let items: [JellyfinMediaSegment]?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

struct JellyfinMediaSegment: Decodable, Sendable {
    let type: String?
    let startTicks: Int64?
    let endTicks: Int64?
    enum CodingKeys: String, CodingKey {
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }
    var startSeconds: Double { Double(startTicks ?? 0) / 10_000_000 }
    var endSeconds: Double { Double(endTicks ?? 0) / 10_000_000 }
}

// MARK: - Next Up

struct JellyfinNextUpResponse: Decodable, Sendable {
    let items: [JellyfinItem]?
    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}

// MARK: - Progress Reporting

struct JellyfinPlayingBody: Encodable {
    let itemId: String
    let playSessionId: String
    let mediaSourceId: String
    let positionTicks: Int64
    let canSeek: Bool
    let playMethod: String
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case mediaSourceId = "MediaSourceId"
        case positionTicks = "PositionTicks"
        case canSeek = "CanSeek"
        case playMethod = "PlayMethod"
    }
}

struct JellyfinProgressBody: Encodable {
    let itemId: String
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool
    let eventName: String
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case eventName = "EventName"
    }
}

struct JellyfinStoppedBody: Encodable {
    let itemId: String
    let playSessionId: String
    let positionTicks: Int64
    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId"
        case playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks"
    }
}
