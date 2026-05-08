import Foundation
import Observation

@Observable
final class CollectionsViewModel {
    private(set) var collections: [SeerrCollection] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private let apiClient: SeerrAPIClient

    // Popular TMDb collection IDs, displayed in this order.
    static let curatedIds: [Int] = [
        10,      // Star Wars
        1241,    // Harry Potter
        119,     // Lord of the Rings
        9485,    // Fast & Furious
        645,     // James Bond
        87359,   // Mission: Impossible
        404609,  // John Wick
        2150,    // Indiana Jones
        735,     // Pirates of the Caribbean
        263,     // Back to the Future
        748,     // The Dark Knight
        131635,  // The Hunger Games
        9696,    // Terminator
        115762,  // The Matrix
        9072,    // Jurassic Park
        701,     // Transformers
        230,     // Alien
        8945,    // Shrek
        33514,   // Toy Story
        131792,  // Despicable Me
        1942,    // Die Hard
        2836,    // Jason Bourne
        456,     // The Godfather
        422,     // Blade
        423,     // Ocean's
    ]

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        let fetched = await Self.loadCollections(using: apiClient)

        if fetched.isEmpty {
            error = "Could not load any collections. Check your server connection."
        }

        collections = fetched
        isLoading = false
    }

    func refresh() async {
        collections = []
        await load()
    }

    static func loadCollections(using apiClient: SeerrAPIClient) async -> [SeerrCollection] {
        let ids = Self.curatedIds
        var fetched: [SeerrCollection] = []

        await withTaskGroup(of: SeerrCollection?.self) { group in
            for id in ids {
                group.addTask { [apiClient] in
                    try? await apiClient.getCollectionDetail(collectionId: id)
                }
            }

            for await result in group {
                if let collection = result {
                    fetched.append(collection)
                }
            }
        }

        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        return fetched.sorted {
            (order[$0.id ?? Int.max, default: Int.max]) < (order[$1.id ?? Int.max, default: Int.max])
        }
    }
}
