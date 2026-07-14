/// LureTopShelfProvider — TVTopShelfContentProvider for Lure.
///
/// Fetches "Continue Watching" (Resume) and "Next Up" items from the user's
/// Jellyfin server and presents them in two sections on the Apple TV home screen
/// Top Shelf when the Lure app is in the top row.
///
/// Deep-link scheme: lure://item/<jellyfinItemId>
/// The Lure app handles this in ContentView → LureRouter.

import TVServices

final class LureTopShelfProvider: TVTopShelfContentProvider {

    // MARK: - TVTopShelfContentProvider

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            let content = await buildContent()
            completionHandler(content)
        }
    }

    // MARK: - Private

    private func buildContent() async -> TVTopShelfContent? {
        guard let creds = TopShelfCredentialStore.load(),
              !creds.serverURL.isEmpty,
              !creds.token.isEmpty,
              !creds.userId.isEmpty
        else { return nil }

        var serverURL = creds.serverURL
        if serverURL.hasSuffix("/") { serverURL = String(serverURL.dropLast()) }

        async let resumeItems = fetchResumeItems(serverURL: serverURL, userId: creds.userId, token: creds.token)
        async let nextUpItems = fetchNextUpItems(serverURL: serverURL, userId: creds.userId, token: creds.token)

        let (resume, nextUp) = await (resumeItems, nextUpItems)

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !resume.isEmpty {
            let items = resume.compactMap { makeShelfItem(from: $0, serverURL: serverURL, token: creds.token) }
            if !items.isEmpty {
                let section = TVTopShelfItemCollection(items: items)
                section.title = "Continue Watching"
                sections.append(section)
            }
        }

        if !nextUp.isEmpty {
            let items = nextUp.compactMap { makeShelfItem(from: $0, serverURL: serverURL, token: creds.token) }
            if !items.isEmpty {
                let section = TVTopShelfItemCollection(items: items)
                section.title = "Next Up"
                sections.append(section)
            }
        }

        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    // MARK: - Shelf item construction

    private func makeShelfItem(
        from item: TopShelfJellyfinItem,
        serverURL: String,
        token: String
    ) -> TVTopShelfSectionedItem? {
        guard let itemId = item.id, !itemId.isEmpty else { return nil }

        let shelfItem = TVTopShelfSectionedItem(identifier: itemId)

        // Title: show series name + episode label for episodes, plain name otherwise.
        if let seriesName = item.seriesName, let ep = item.episodeLabel {
            shelfItem.title = "\(seriesName) — \(ep)"
        } else {
            shelfItem.title = item.name ?? "Untitled"
        }

        // Image: prefer thumb (landscape) for episodes, primary for movies.
        // Use the item's own id; for episodes also try the series id for a backdrop.
        let imageItemId = item.type?.lowercased() == "episode" ? (item.seriesId ?? itemId) : itemId
        if let imageURL = thumbImageURL(serverURL: serverURL, itemId: imageItemId, token: token, width: 1000) {
            shelfItem.setImageURL(imageURL, for: .screenScale2x)
        } else if let imageURL = primaryImageURL(serverURL: serverURL, itemId: imageItemId, token: token, width: 1000) {
            shelfItem.setImageURL(imageURL, for: .screenScale2x)
        }

        // Playback progress (0.0–1.0) from resume position.
        if let ticks = item.userData?.playbackPositionTicks,
           let totalTicks = item.runTimeTicks,
           totalTicks > 0 {
            let progress = Double(ticks) / Double(totalTicks)
            shelfItem.playbackProgress = max(0, min(1, progress))
        }

        // Deep-link URLs: opening the item detail is sufficient.
        let displayURL = URL(string: "lure://item/\(itemId)")
        let playURL = URL(string: "lure://play/\(itemId)")
        shelfItem.displayAction = TVTopShelfAction(url: displayURL ?? URL(string: "lure://discover")!)
        shelfItem.playAction = TVTopShelfAction(url: playURL ?? URL(string: "lure://discover")!)

        return shelfItem
    }

    // MARK: - Image URL helpers (standalone, no dependency on app code)

    private func thumbImageURL(serverURL: String, itemId: String, token: String, width: Int) -> URL? {
        guard var comps = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Thumb") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return comps.url
    }

    private func primaryImageURL(serverURL: String, itemId: String, token: String, width: Int) -> URL? {
        guard var comps = URLComponents(string: "\(serverURL)/Items/\(itemId)/Images/Primary") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(width)"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return comps.url
    }

    // MARK: - Network fetches

    private func fetchResumeItems(serverURL: String, userId: String, token: String) async -> [TopShelfJellyfinItem] {
        guard var comps = URLComponents(string: "\(serverURL)/Users/\(userId)/Items/Resume") else { return [] }
        comps.queryItems = [
            URLQueryItem(name: "MediaTypes", value: "Video"),
            URLQueryItem(name: "Limit", value: "10"),
            URLQueryItem(name: "Fields", value: "UserData,RunTimeTicks,SeriesId,SeriesName"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return await fetchItems(from: comps.url, token: token)
    }

    private func fetchNextUpItems(serverURL: String, userId: String, token: String) async -> [TopShelfJellyfinItem] {
        guard var comps = URLComponents(string: "\(serverURL)/Shows/NextUp") else { return [] }
        comps.queryItems = [
            URLQueryItem(name: "UserId", value: userId),
            URLQueryItem(name: "Limit", value: "10"),
            URLQueryItem(name: "Fields", value: "UserData,RunTimeTicks,SeriesId,SeriesName"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return await fetchItems(from: comps.url, token: token)
    }

    private func fetchItems(from url: URL?, token: String) async -> [TopShelfJellyfinItem] {
        guard let url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "MediaBrowser Client=\"Lure\", Device=\"Apple TV\", DeviceId=\"TopShelfExtension\", Version=\"1.0\", Token=\"\(token)\"",
            forHTTPHeaderField: "Authorization"
        )
        do {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return [] }
            let decoded = try JSONDecoder().decode(TopShelfItemsResponse.self, from: data)
            return decoded.items ?? []
        } catch {
            return []
        }
    }
}

// MARK: - Minimal local models (no dependency on app's JellyfinModels)

private struct TopShelfItemsResponse: Decodable {
    let items: [TopShelfJellyfinItem]?
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

private struct TopShelfJellyfinItem: Decodable {
    let id: String?
    let name: String?
    let type: String?
    let seriesId: String?
    let seriesName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let runTimeTicks: Int64?
    let userData: TopShelfUserData?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case seriesId = "SeriesId"
        case seriesName = "SeriesName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
    }

    var episodeLabel: String? {
        guard let s = parentIndexNumber, let e = indexNumber else { return nil }
        return "S\(s) E\(e)"
    }
}

private struct TopShelfUserData: Decodable {
    let playbackPositionTicks: Int64?
    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
    }
}
