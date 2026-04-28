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

    private let cacheURL: URL

    init() {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheURL = cachesDirectory.appendingPathComponent("library-snapshot.json")
    }

    func load() -> [LibraryItem]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode([LibraryItem].self, from: data)
    }

    func store(_ items: [LibraryItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
