import Foundation

actor SearchBrowseGenresCache {
    static let shared = SearchBrowseGenresCache()

    private var cachedGenres: [SearchGenreTile]?

    func genres() -> [SearchGenreTile]? {
        cachedGenres
    }

    func store(_ genres: [SearchGenreTile]) {
        cachedGenres = genres
    }
}
