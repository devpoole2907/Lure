import Foundation

struct LibraryItem: Identifiable, Codable, Sendable, Equatable, Hashable {
    let mediaType: String
    let tmdbId: Int
    let title: String
    let year: String?
    let voteAverage: Double?
    let posterURL: URL?
    let isAvailable: Bool

    var id: String { "\(mediaType)-\(tmdbId)" }
}

actor LibrarySnapshotCache {
    static let shared = LibrarySnapshotCache()

    private let cachesDirectory: URL

    init() {
        cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    private func cacheURL(for serverBaseURL: String) -> URL {
        let key = serverBaseURL
            .replacingOccurrences(of: "://", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cachesDirectory.appendingPathComponent("library-snapshot-\(key).json")
    }

    func load(serverBaseURL: String) -> [LibraryItem]? {
        guard let data = try? Data(contentsOf: cacheURL(for: serverBaseURL)) else { return nil }
        return try? JSONDecoder().decode([LibraryItem].self, from: data)
    }

    func store(_ items: [LibraryItem], serverBaseURL: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: cacheURL(for: serverBaseURL), options: .atomic)
    }
}
