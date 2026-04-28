import Foundation

/// Core Seerr HTTP client. Manages session cookies and provides typed API methods.
actor SeerrAPIClient {
    let baseURL: String
    private let session: URLSession
    private var sessionCookie: String?

    init(baseURL: String, sessionCookie: String? = nil) {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        self.baseURL = url
        self.sessionCookie = sessionCookie

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Auth

    /// Authenticate via Jellyfin credentials. Returns user and stores session cookie.
    func loginJellyfin(username: String, password: String) async throws -> SeerrUser {
        let body: [String: String] = ["username": username, "password": password]
        let (data, response) = try await postRaw("/api/v1/auth/jellyfin", jsonBody: body)

        // Extract session cookie from Set-Cookie header
        if let setCookie = response.value(forHTTPHeaderField: "Set-Cookie") {
            sessionCookie = extractSessionCookie(from: setCookie)
        }

        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw LureError.invalidCredentials
            }
            throw LureError.serverError(statusCode: response.statusCode, message: String(data: data, encoding: .utf8))
        }

        return try decode(SeerrUser.self, from: data)
    }

    /// Get the currently authenticated user.
    func getCurrentUser() async throws -> SeerrUser {
        try await get("/api/v1/auth/me")
    }

    /// Log out and clear the session.
    func logout() async throws {
        _ = try? await postVoid("/api/v1/auth/logout", jsonBody: [:] as [String: String])
        sessionCookie = nil
    }

    /// Get the current session cookie for persistence.
    func getSessionCookie() -> String? { sessionCookie }

    /// Set a session cookie (restored from keychain).
    func setSessionCookie(_ cookie: String) { sessionCookie = cookie }

    // MARK: - Public Settings (no auth required)

    func getPublicSettings() async throws -> SeerrPublicSettings {
        try await get("/api/v1/settings/public")
    }

    // MARK: - Discover

    func getDiscoverTrending(page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/discover/trending", params: ["page": String(page)])
    }

    func getDiscoverMovies(page: Int = 1, genre: Int? = nil, sortBy: String? = nil) async throws -> SeerrDiscoverResponse {
        var params: [String: String] = ["page": String(page)]
        if let genre { params["genre"] = String(genre) }
        if let sortBy { params["sortBy"] = sortBy }
        return try await get("/api/v1/discover/movies", params: params)
    }

    func getDiscoverTV(page: Int = 1, genre: Int? = nil, sortBy: String? = nil) async throws -> SeerrDiscoverResponse {
        var params: [String: String] = ["page": String(page)]
        if let genre { params["genre"] = String(genre) }
        if let sortBy { params["sortBy"] = sortBy }
        return try await get("/api/v1/discover/tv", params: params)
    }

    func getDiscoverMoviesUpcoming(page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/discover/movies/upcoming", params: ["page": String(page)])
    }

    func getDiscoverSliders() async throws -> [SeerrDiscoverSlider] {
        try await get("/api/v1/settings/discover")
    }

    // MARK: - Search

    func search(query: String, page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/search", params: ["query": query, "page": String(page)])
    }

    // MARK: - Movie Detail

    func getMovieDetail(tmdbId: Int) async throws -> SeerrMovieDetail {
        try await get("/api/v1/movie/\(tmdbId)")
    }

    func getMovieRatings(tmdbId: Int) async throws -> SeerrRatingsCombined {
        try await get("/api/v1/movie/\(tmdbId)/ratingscombined")
    }

    func getMovieRecommendations(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/movie/\(tmdbId)/recommendations", params: ["page": String(page)])
    }

    func getMovieSimilar(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/movie/\(tmdbId)/similar", params: ["page": String(page)])
    }

    // MARK: - TV Detail

    func getTVDetail(tmdbId: Int) async throws -> SeerrTVDetail {
        try await get("/api/v1/tv/\(tmdbId)")
    }

    func getTVRatings(tmdbId: Int) async throws -> SeerrRatingsCombined {
        try await get("/api/v1/tv/\(tmdbId)/ratings")
    }

    func getTVRecommendations(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/tv/\(tmdbId)/recommendations", params: ["page": String(page)])
    }

    func getTVSimilar(tmdbId: Int, page: Int = 1) async throws -> SeerrDiscoverResponse {
        try await get("/api/v1/tv/\(tmdbId)/similar", params: ["page": String(page)])
    }

    // MARK: - Person

    func getPersonDetail(personId: Int) async throws -> SeerrPersonDetail {
        try await get("/api/v1/person/\(personId)")
    }

    func getPersonCombinedCredits(personId: Int) async throws -> SeerrPersonCombinedCredits {
        try await get("/api/v1/person/\(personId)/combined_credits")
    }

    // MARK: - Collection

    func getCollectionDetail(collectionId: Int) async throws -> SeerrCollection {
        try await get("/api/v1/collection/\(collectionId)")
    }

    // MARK: - Requests

    func createRequest(_ body: SeerrCreateRequestBody) async throws -> SeerrMediaRequest {
        try await post("/api/v1/request", body: body)
    }

    func getRequests(take: Int = 20, skip: Int = 0, filter: String = "all", mediaType: String = "all", sort: String = "added", sortDirection: String = "desc") async throws -> SeerrRequestListResponse {
        try await get("/api/v1/request", params: [
            "take": String(take),
            "skip": String(skip),
            "filter": filter,
            "sort": sort,
            "sortDirection": sortDirection,
            "mediaType": mediaType
        ])
    }

    func getRequestCount() async throws -> SeerrRequestCount {
        try await get("/api/v1/request/count")
    }

    func approveRequest(id: Int) async throws -> SeerrMediaRequest {
        try await post("/api/v1/request/\(id)/approve", body: [String: String]())
    }

    func declineRequest(id: Int) async throws -> SeerrMediaRequest {
        try await post("/api/v1/request/\(id)/decline", body: [String: String]())
    }

    func retryRequest(id: Int) async throws -> SeerrMediaRequest {
        try await post("/api/v1/request/\(id)/retry", body: [String: String]())
    }

    func deleteRequest(id: Int) async throws {
        try await deleteHTTP("/api/v1/request/\(id)")
    }

    // MARK: - User

    func getUserQuota(userId: Int) async throws -> SeerrUserQuota {
        try await get("/api/v1/user/\(userId)/quota")
    }

    func getUserRequests(userId: Int, take: Int = 20, skip: Int = 0) async throws -> SeerrRequestListResponse {
        try await get("/api/v1/user/\(userId)/requests", params: [
            "take": String(take), "skip": String(skip)
        ])
    }

    func getUsers(take: Int = 20, skip: Int = 0) async throws -> SeerrUserListResponse {
        try await get("/api/v1/user", params: [
            "take": String(take),
            "skip": String(skip)
        ])
    }

    func updateUser(id: Int, permissions: Int) async throws -> SeerrUser {
        try await put("/api/v1/user/\(id)", body: SeerrUpdateUserBody(permissions: permissions))
    }

    func deleteUser(id: Int) async throws -> SeerrUser {
        try await delete("/api/v1/user/\(id)")
    }

    func importUsersFromJellyfin(jellyfinUserIds: [String]? = nil) async throws -> [SeerrUser] {
        if let jellyfinUserIds, !jellyfinUserIds.isEmpty {
            return try await post(
                "/api/v1/user/import-from-jellyfin",
                body: SeerrImportJellyfinUsersBody(jellyfinUserIds: jellyfinUserIds)
            )
        }
        return try await post("/api/v1/user/import-from-jellyfin", body: EmptyRequestBody())
    }

    // MARK: - Media Library

    func getMedia(filter: String = "available", take: Int = 20, skip: Int = 0) async throws -> SeerrMediaListResponse {
        let params: [String: String] = [
            "take": String(take),
            "skip": String(skip),
            "filter": filter
        ]
        return try await get("/api/v1/media", params: params)
    }

    // MARK: - Issues

    func createIssue(_ body: SeerrCreateIssueBody) async throws -> SeerrIssueResponse {
        try await post("/api/v1/issue", body: body)
    }

    func getIssues(take: Int = 20, skip: Int = 0, sort: String = "createdAt", filter: String = "open") async throws -> SeerrIssueListResponse {
        try await get("/api/v1/issue", params: [
            "take": String(take),
            "skip": String(skip),
            "sort": sort,
            "filter": filter
        ])
    }

    func getIssue(id: Int) async throws -> SeerrIssue {
        try await get("/api/v1/issue/\(id)")
    }

    func getIssueComments(issueId: Int) async throws -> [SeerrIssueComment] {
        let request = try buildRequest(path: "/api/v1/issue/\(issueId)/comment", method: "GET")
        let data = try await performData(request)

        if let comments = try? JSONDecoder().decode([SeerrIssueComment].self, from: data) {
            return comments
        }

        if let issue = try? JSONDecoder().decode(SeerrIssue.self, from: data) {
            return issue.comments ?? []
        }

        throw LureError.invalidResponse
    }

    func replyToIssue(issueId: Int, message: String) async throws -> SeerrIssue {
        try await post("/api/v1/issue/\(issueId)/comment", body: SeerrIssueCommentBody(message: message))
    }

    func resolveIssue(issueId: Int) async throws -> SeerrIssue {
        try await post("/api/v1/issue/\(issueId)/resolved", body: EmptyRequestBody())
    }

    func reopenIssue(issueId: Int) async throws -> SeerrIssue {
        try await post("/api/v1/issue/\(issueId)/open", body: EmptyRequestBody())
    }

    // MARK: - Genres

    func getMovieGenres() async throws -> [SeerrGenre] {
        try await get("/api/v1/genres/movie")
    }

    func getTVGenres() async throws -> [SeerrGenre] {
        try await get("/api/v1/genres/tv")
    }

    // MARK: - HTTP Infrastructure

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        let request = try buildRequest(path: path, method: "GET", queryParams: params)
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var request = try buildRequest(path: path, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func postVoid<B: Encodable>(_ path: String, jsonBody: B) async throws {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(jsonBody)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            throw LureError.invalidResponse
        }
    }

    private func postRaw(_ path: String, jsonBody: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = try buildRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LureError.invalidResponse }
        return (data, http)
    }

    private func deleteHTTP(_ path: String) async throws {
        let request = try buildRequest(path: path, method: "DELETE")
        _ = try await performData(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "DELETE")
        return try await perform(request)
    }

    private func buildRequest(path: String, method: String, queryParams: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(string: "\(baseURL)\(path)") else {
            throw LureError.invalidResponse
        }
        if !queryParams.isEmpty {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw LureError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let cookie = sessionCookie {
            request.setValue("connect.sid=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await performData(request)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LureError.decodingError(error)
        }
    }

    private func performData(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LureError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw LureError.invalidResponse }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw LureError.notAuthenticated
        }

        guard (200..<400).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw LureError.serverError(statusCode: http.statusCode, message: body)
        }

        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LureError.decodingError(error)
        }
    }

    private func extractSessionCookie(from header: String) -> String? {
        // Set-Cookie: connect.sid=s%3A...; Path=/; ...
        for part in header.components(separatedBy: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("connect.sid=") {
                return String(trimmed.dropFirst("connect.sid=".count))
            }
        }
        return nil
    }
}
