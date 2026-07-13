import Foundation
#if canImport(UIKit)
import UIKit
#endif

actor JellyfinAPIClient {
    let serverURL: String
    private let token: String
    let userId: String
    let deviceId: String
    private let session: URLSession

    init(credentials: JellyfinCredentials) {
        var url = credentials.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        self.serverURL = url
        self.token = credentials.token
        self.userId = credentials.userId
        self.deviceId = JellyfinCredentials.deviceId
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    static func authenticate(serverURL: String, username: String, password: String) async throws -> JellyfinCredentials {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        let deviceId = JellyfinCredentials.deviceId
        let deviceName = Self.currentDeviceName
        guard let endpoint = URL(string: "\(url)/Users/AuthenticateByName") else {
            throw JellyfinError.badURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "MediaBrowser Client=\"Lure\", Device=\"\(deviceName)\", DeviceId=\"\(deviceId)\", Version=\"1.0\"",
            forHTTPHeaderField: "Authorization"
        )
        let body = JellyfinAuthRequest(username: username, pw: password)
        request.httpBody = try JSONEncoder().encode(body)
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let tempSession = URLSession(configuration: config)
        let (data, response) = try await tempSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        if http.statusCode == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw JellyfinError.serverError(http.statusCode) }
        let auth = try JSONDecoder().decode(JellyfinAuthResponse.self, from: data)
        guard let token = auth.accessToken, let userId = auth.user?.id else {
            throw JellyfinError.invalidResponse
        }
        return JellyfinCredentials(
            serverURL: url,
            token: token,
            userId: userId,
            displayName: auth.user?.name ?? username
        )
    }

    // MARK: - Items

    func getItem(itemId: String) async throws -> JellyfinItem {
        let response: JellyfinItemsResponse = try await get(
            "/Users/\(userId)/Items",
            params: ["Ids": itemId, "Fields": "UserData,RunTimeTicks,SeriesId,SeriesName,ProviderIds,ProductionYear"]
        )
        guard let item = response.items?.first else { throw JellyfinError.itemNotFound }
        return item
    }

    func findItemId(
        serviceUrl: String?,
        tmdbId: Int,
        mediaType: String,
        title: String? = nil,
        releaseYear: Int? = nil
    ) async throws -> String? {
        if let serviceUrl, let id = Self.extractJellyfinId(from: serviceUrl) {
            return id
        }
        return try await searchByTmdbId(tmdbId, mediaType: mediaType, title: title, releaseYear: releaseYear)
    }

    func searchByTmdbId(
        _ tmdbId: Int,
        mediaType: String,
        title: String? = nil,
        releaseYear: Int? = nil
    ) async throws -> String? {
        let type = mediaType == "tv" ? "Series" : "Movie"
        if let title, !title.isEmpty {
            let response: JellyfinItemsResponse = try await get(
                "/Users/\(userId)/Items",
                params: [
                    "IncludeItemTypes": type,
                    "Recursive": "true",
                    "CollapseBoxSetItems": "false",
                    "SearchTerm": title,
                    "Fields": "Id,Name,ProviderIds,ProductionYear",
                    "Limit": "50"
                ]
            )
            if let match = logAndFindBestMatch(
                response.items ?? [],
                tmdbId: tmdbId,
                mediaType: mediaType,
                title: title,
                releaseYear: releaseYear,
                source: "title search"
            ) {
                return match
            }
        }

        let pageSize = 200
        let maxPages = 50
        var startIndex = 0
        for page in 0..<maxPages {
            let response: JellyfinItemsResponse = try await get(
                "/Users/\(userId)/Items",
                params: [
                    "IncludeItemTypes": type,
                    "Recursive": "true",
                    "CollapseBoxSetItems": "false",
                    "HasTmdbId": "true",
                    "Fields": "Id,Name,ProviderIds,ProductionYear",
                    "StartIndex": "\(startIndex)",
                    "Limit": "\(pageSize)",
                    "EnableTotalRecordCount": "true"
                ]
            )
            let items = response.items ?? []
            if let match = logAndFindBestMatch(
                items,
                tmdbId: tmdbId,
                mediaType: mediaType,
                title: title,
                releaseYear: releaseYear,
                source: "page \(page + 1)"
            ) {
                return match
            }
            guard !items.isEmpty else { return nil }
            startIndex += items.count
            if let total = response.totalRecordCount, startIndex >= total {
                return nil
            }
        }
        #if DEBUG
        print("[JellyfinAPIClient] searchByTmdbId hit max page cap (\(maxPages) pages, \(maxPages * pageSize) items) for tmdbId=\(tmdbId)")
        #endif
        return nil
    }

    private func logAndFindBestMatch(
        _ items: [JellyfinItem],
        tmdbId: Int,
        mediaType: String,
        title: String?,
        releaseYear: Int?,
        source: String
    ) -> String? {
        #if DEBUG
        print("[JellyfinAPIClient] Jellyfin lookup \(source) tmdbId=\(tmdbId) mediaType=\(mediaType) title=\(title ?? "nil") year=\(releaseYear.map(String.init) ?? "nil") count=\(items.count)")
        for item in items.prefix(20) {
            print("[JellyfinAPIClient] Jellyfin candidate id=\(item.id ?? "nil") name=\(item.name ?? "nil") type=\(item.type ?? "nil") year=\(item.productionYear.map(String.init) ?? "nil") providerTmdb=\(item.tmdbId.map(String.init) ?? "nil")")
        }
        #endif
        if let match = items.first(where: { $0.tmdbId == tmdbId })?.id {
            return match
        }
        guard let title, !title.isEmpty else { return nil }
        let normalizedTitle = Self.normalizedTitle(title)
        let titleMatches = items.filter { item in
            guard let name = item.name else { return false }
            return Self.normalizedTitle(name) == normalizedTitle
        }
        if let releaseYear {
            return titleMatches.first(where: { $0.productionYear == releaseYear })?.id
        }
        return titleMatches.count == 1 ? titleMatches.first?.id : nil
    }

    private static func normalizedTitle(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    func getSeasons(seriesId: String) async throws -> [JellyfinSeason] {
        let response: JellyfinSeasonsResponse = try await get(
            "/Shows/\(seriesId)/Seasons",
            params: ["UserId": userId, "Fields": "ChildCount"]
        )
        return (response.items ?? []).filter { ($0.indexNumber ?? 0) > 0 }
    }

    func getEpisodes(seriesId: String, seasonId: String) async throws -> [JellyfinItem] {
        let response: JellyfinEpisodesResponse = try await get(
            "/Shows/\(seriesId)/Episodes",
            params: ["SeasonId": seasonId, "UserId": userId, "Fields": "UserData,Overview,RunTimeTicks"]
        )
        return response.items ?? []
    }

    /// Page through every movie + series in the user's Jellyfin library.
    /// Used to back the Library tab when Jellyfin is configured. Capped to
    /// avoid runaway loops on a misbehaving server (50 pages × 200 items).
    func getAllLibraryItems(pageSize: Int = 200) async throws -> [JellyfinItem] {
        let maxPages = 50
        var collected: [JellyfinItem] = []
        var startIndex = 0
        for _ in 0..<maxPages {
            let response: JellyfinItemsResponse = try await get(
                "/Users/\(userId)/Items",
                params: [
                    "IncludeItemTypes": "Movie,Series",
                    "Recursive": "true",
                    "CollapseBoxSetItems": "false",
                    "Fields": "Id,Name,Type,ProductionYear,ProviderIds,DateCreated,CommunityRating",
                    "SortBy": "SortName",
                    "SortOrder": "Ascending",
                    "StartIndex": "\(startIndex)",
                    "Limit": "\(pageSize)",
                    "EnableTotalRecordCount": "true"
                ]
            )
            let items = response.items ?? []
            collected.append(contentsOf: items)
            if items.isEmpty { break }
            startIndex += items.count
            if let total = response.totalRecordCount, startIndex >= total { break }
        }
        return collected
    }

    /// Lightweight search across the user's Jellyfin library for movies + series.
    /// Results carry id/name/year/poster + (when available) `Tmdb` provider id
    /// so we can route taps through the existing MediaDestination flow.
    func searchItems(term: String, limit: Int = 50) async throws -> [JellyfinItem] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response: JellyfinItemsResponse = try await get(
            "/Users/\(userId)/Items",
            params: [
                "SearchTerm": trimmed,
                "IncludeItemTypes": "Movie,Series",
                "Recursive": "true",
                "Fields": "Id,Name,Type,ProductionYear,ProviderIds",
                "Limit": "\(limit)",
                "EnableTotalRecordCount": "false"
            ]
        )
        return response.items ?? []
    }

    func getResumeItems(limit: Int = 20) async throws -> [JellyfinItem] {
        let response: JellyfinItemsResponse = try await get(
            "/Users/\(userId)/Items/Resume",
            params: [
                "MediaTypes": "Video",
                "Limit": "\(limit)",
                "Fields": "UserData,RunTimeTicks,SeriesId,SeriesName,ProviderIds,ProductionYear"
            ]
        )
        return response.items ?? []
    }

    nonisolated func primaryImageURL(itemId: String, width: Int = 400) -> URL? {
        var components = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Primary")
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return components?.url
    }

    nonisolated func thumbImageURL(itemId: String, width: Int = 500) -> URL? {
        var components = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Thumb")
        components?.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return components?.url
    }

    func getNextUp(seriesId: String) async throws -> JellyfinItem? {
        let response: JellyfinNextUpResponse = try await get(
            "/Shows/NextUp",
            params: ["UserId": userId, "SeriesId": seriesId, "Limit": "1", "Fields": "UserData"]
        )
        return response.items?.first
    }

    func markPlayed(itemId: String) async throws {
        try await postEmpty("/Users/\(userId)/PlayedItems/\(itemId)")
    }

    // MARK: - Playback

    func getPlaybackInfo(itemId: String, startPositionSeconds: Double = 0) async throws -> JellyfinPlaybackInfoResponse {
        let startTicks = startPositionSeconds > 0 ? Int64(startPositionSeconds * 10_000_000) : nil
        let body = JellyfinPlaybackInfoBody(
            deviceProfile: .aetherEngine,
            userId: userId,
            maxStreamingBitrate: 200_000_000,
            startTimeTicks: startTicks,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            allowVideoStreamCopy: true,
            allowAudioStreamCopy: true,
            autoOpenLiveStream: true
        )
        var request = try buildRequest(path: "/Items/\(itemId)/PlaybackInfo", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    nonisolated func streamURL(
        itemId: String,
        mediaSourceId: String,
        playSessionId: String,
        isStatic: Bool,
        container: String?,
        useContainerExtension: Bool = true
    ) -> URL? {
        let ext = container?.isEmpty == false ? container! : "mp4"
        let streamPath = useContainerExtension ? "stream.\(ext)" : "stream"

        var components = URLComponents(string: "\(serverURL)/Videos/\(itemId)/\(streamPath)")
        var queryItems = [
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "MediaSourceId", value: mediaSourceId),
            URLQueryItem(name: "PlaySessionId", value: playSessionId)
        ]
        if isStatic {
            queryItems.append(URLQueryItem(name: "Static", value: "true"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    nonisolated func transcodingURL(path: String) -> URL? {
        serverRelativeURL(path: path)
    }

    nonisolated func serverRelativeURL(path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL = URL(string: serverURL),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        else { return nil }

        let parsedPath = URLComponents(string: path)
        let incomingPath = parsedPath?.path.isEmpty == false ? parsedPath?.path ?? path : path
        let basePath = baseURL.path

        if incomingPath.hasPrefix("/") {
            let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
            if normalizedBase.isEmpty || incomingPath == normalizedBase || incomingPath.hasPrefix("\(normalizedBase)/") {
                components.path = incomingPath
            } else {
                components.path = "\(normalizedBase)/\(incomingPath.drop { $0 == "/" })"
            }
        } else {
            let normalizedBase = basePath.hasSuffix("/") ? basePath : "\(basePath)/"
            components.path = "\(normalizedBase)\(incomingPath)"
        }
        components.query = parsedPath?.percentEncodedQuery
        components.fragment = parsedPath?.percentEncodedFragment
        return components.url
    }

    func playbackURLDiagnostics(_ url: URL) async {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "nil"
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<\(data.count) binary bytes>"
            print("[JellyfinAPIClient] playback preflight status=\(status) contentType=\(contentType) bytes=\(data.count) url=\(url.absoluteString)")
            if !(200...299).contains(status) {
                print("[JellyfinAPIClient] playback preflight body=\(preview)")
            }
        } catch {
            print("[JellyfinAPIClient] playback preflight failed url=\(url.absoluteString) error=\(error.localizedDescription)")
        }
    }

    // MARK: - Media Segments

    func getMediaSegments(itemId: String) async throws -> [JellyfinMediaSegment] {
        do {
            let response: JellyfinMediaSegmentsResponse = try await get("/Items/\(itemId)/MediaSegments")
            return response.items ?? []
        } catch {
            return []
        }
    }

    // MARK: - Progress Reporting (fire-and-forget)

    func reportPlaybackStart(itemId: String, playSessionId: String, mediaSourceId: String, positionSeconds: Double, playMethod: String) async {
        let body = JellyfinPlayingBody(
            itemId: itemId,
            playSessionId: playSessionId,
            mediaSourceId: mediaSourceId,
            positionTicks: Int64(positionSeconds * 10_000_000),
            canSeek: true,
            playMethod: playMethod
        )
        try? await postVoid("/Sessions/Playing", body: body)
    }

    func reportProgress(itemId: String, playSessionId: String, positionSeconds: Double, isPaused: Bool, eventName: String = "TimeUpdate") async {
        let body = JellyfinProgressBody(
            itemId: itemId,
            playSessionId: playSessionId,
            positionTicks: Int64(positionSeconds * 10_000_000),
            isPaused: isPaused,
            eventName: eventName
        )
        try? await postVoid("/Sessions/Playing/Progress", body: body)
    }

    func reportStopped(itemId: String, playSessionId: String, positionSeconds: Double) async {
        let body = JellyfinStoppedBody(
            itemId: itemId,
            playSessionId: playSessionId,
            positionTicks: Int64(positionSeconds * 10_000_000)
        )
        try? await postVoid("/Sessions/Playing/Stopped", body: body)
    }

    // MARK: - HTTP Infrastructure

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", queryParams: params)
        return try await perform(request)
    }

    private func postVoid<B: Encodable>(_ path: String, body: B) async throws {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        try await performVoid(request)
    }

    private func postEmpty(_ path: String) async throws {
        let request = try buildRequest(path: path, method: "POST")
        try await performVoid(request)
    }

    private func performVoid(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        if http.statusCode == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw JellyfinError.serverError(http.statusCode) }
    }

    private func buildRequest(path: String, method: String, queryParams: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(string: "\(serverURL)\(path)") else {
            throw JellyfinError.badURL
        }
        var items = [URLQueryItem(name: "api_key", value: token)]
        for (k, v) in queryParams { items.append(URLQueryItem(name: k, value: v)) }
        components.queryItems = items
        guard let url = components.url else { throw JellyfinError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "MediaBrowser Client=\"Lure\", Device=\"\(Self.currentDeviceName)\", DeviceId=\"\(deviceId)\", Version=\"1.0\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        return request
    }

    nonisolated private static var currentDeviceName: String {
        #if os(tvOS)
        "Apple TV"
        #elseif os(visionOS)
        "Apple Vision"
        #elseif targetEnvironment(macCatalyst)
        "Mac"
        #elseif os(iOS)
        "iPhone"
        #else
        "Mac"
        #endif
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JellyfinError.invalidResponse }
        if http.statusCode == 401 { throw JellyfinError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw JellyfinError.serverError(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JellyfinError.decodingFailed(error)
        }
    }

    // MARK: - Helpers

    private static func extractJellyfinId(from urlString: String) -> String? {
        // serviceUrl format: http://host/web/#!/details?id=ITEM_ID&serverId=...
        // Normalize the fragment-based URL by replacing #!/ with ?
        let normalized = urlString
            .replacingOccurrences(of: "#!/", with: "?")
            .replacingOccurrences(of: "#!", with: "?")
        guard let url = URL(string: normalized),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first(where: { $0.name == "id" })?.value
    }
}

// MARK: - Error

enum JellyfinError: LocalizedError {
    case badURL
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingFailed(Error)
    case itemNotFound
    case noCredentials
    case noPlayableSource

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid server URL."
        case .invalidResponse: "Invalid response from Jellyfin."
        case .unauthorized: "Incorrect username or password."
        case .serverError(let code): "Jellyfin server error (\(code))."
        case .decodingFailed: "Failed to parse Jellyfin response."
        case .itemNotFound: "Item not found in your Jellyfin library."
        case .noCredentials: "Jellyfin is not configured. Go to Settings → Playback."
        case .noPlayableSource: "No playable source found for this item."
        }
    }
}
