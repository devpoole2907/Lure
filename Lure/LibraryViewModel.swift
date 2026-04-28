import Foundation
import Observation

struct LibrarySection: Identifiable {
    let title: String
    let indexLabel: String
    let items: [LibraryItem]
    var id: String { indexLabel }
}

@Observable
final class LibraryViewModel {
    private(set) var items: [LibraryItem] = []
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var error: String?
    private(set) var didLoadInitialSnapshot = false

    private let apiClient: SeerrAPIClient

    init(apiClient: SeerrAPIClient) {
        self.apiClient = apiClient
    }

    var sectionedItems: [LibrarySection] {
        let sorted = items.sorted { $0.title.lowercased() < $1.title.lowercased() }
        let grouped = Dictionary(grouping: sorted) { item in
            sectionLabel(for: item.title)
        }
        return grouped.keys.sorted().map { label in
            LibrarySection(title: label, indexLabel: label, items: grouped[label] ?? [])
        }
    }

    private func sectionLabel(for title: String) -> String {
        guard let scalar = title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.first else {
            return "#"
        }
        let label = String(scalar).uppercased()
        return label.range(of: "[A-Z]", options: .regularExpression) != nil ? label : "#"
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil

        if !didLoadInitialSnapshot, let cachedEntries = await LibrarySnapshotCache.shared.load(), !cachedEntries.isEmpty {
            items = cachedEntries
            didLoadInitialSnapshot = true
        }

        await refreshLibrary(showBlockingLoader: items.isEmpty)
        isLoading = false
    }

    func refresh() async {
        guard !isLoading else { return }
        await refreshLibrary(showBlockingLoader: false)
    }

    private func refreshLibrary(showBlockingLoader: Bool) async {
        if showBlockingLoader {
            isRefreshing = false
        } else {
            isRefreshing = true
        }
        defer { isRefreshing = false }

        do {
            let allEntries = try await fetchAllAvailableEntries()
            let refreshedItems = await resolveLibraryItems(from: allEntries)
            await applyRefreshedItems(refreshedItems)
            error = nil
            didLoadInitialSnapshot = true
            await LibrarySnapshotCache.shared.store(refreshedItems)
        } catch {
            if items.isEmpty {
                self.error = error.localizedDescription
            }
        }
    }

    private func fetchAllAvailableEntries() async throws -> [SeerrMediaEntry] {
        var allEntries: [SeerrMediaEntry] = []
        var skip = 0
        let pageSize = 250

        while true {
            let response = try await apiClient.getMedia(filter: "available", take: pageSize, skip: skip)
            allEntries.append(contentsOf: response.results)
            if response.results.count < pageSize { break }
            skip += pageSize
        }

        return allEntries
    }

    private func resolveLibraryItems(from entries: [SeerrMediaEntry]) async -> [LibraryItem] {
        let batchSize = 20
        var resolvedByEntryID: [Int: LibraryItem] = [:]

        for batchStart in stride(from: 0, to: entries.count, by: batchSize) {
            let batch = Array(entries[batchStart..<min(batchStart + batchSize, entries.count)])

            await withTaskGroup(of: (Int, LibraryItem?).self) { group in
                for entry in batch {
                    group.addTask { [apiClient] in
                        guard let tmdbId = entry.tmdbId, let mediaType = entry.mediaType else {
                            return (entry.id, entry.toLibraryItem())
                        }

                        if mediaType == "movie" {
                            if let detail = try? await apiClient.getMovieDetail(tmdbId: tmdbId) {
                                return (entry.id, detail.toLibraryItem())
                            }
                        } else if mediaType == "tv" {
                            if let detail = try? await apiClient.getTVDetail(tmdbId: tmdbId) {
                                return (entry.id, detail.toLibraryItem())
                            }
                        }

                        return (entry.id, entry.toLibraryItem())
                    }
                }

                for await (entryID, item) in group {
                    if let item {
                        resolvedByEntryID[entryID] = item
                    }
                }
            }
        }

        return entries.compactMap { resolvedByEntryID[$0.id] ?? $0.toLibraryItem() }
    }

    private func applyRefreshedItems(_ refreshedItems: [LibraryItem]) async {
        guard !items.isEmpty else {
            items = refreshedItems
            return
        }

        let existingIDs = Set(items.map(\.id))
        let refreshedIDs = Set(refreshedItems.map(\.id))

        let survivingItems = items.filter { refreshedIDs.contains($0.id) }
        if survivingItems != items {
            items = survivingItems
            await pauseBetweenDiffStages()
        }

        let refreshedExistingItems = refreshedItems.filter { existingIDs.contains($0.id) }
        if refreshedExistingItems != items {
            items = refreshedExistingItems
            await pauseBetweenDiffStages()
        }

        let newItemIDs = refreshedItems.lazy
            .map(\.id)
            .filter { !existingIDs.contains($0) }

        let MAX_STAGED = 10
        if newItemIDs.count > MAX_STAGED {
            items = refreshedItems
        } else {
            for newItemID in newItemIDs {
                let visibleIDs = Set(items.map(\.id))
                let nextItems = refreshedItems.filter { visibleIDs.contains($0.id) || $0.id == newItemID }
                if nextItems != items {
                    items = nextItems
                    await pauseBetweenDiffStages()
                }
            }
        }
    }

    private func pauseBetweenDiffStages() async {
        try? await Task.sleep(for: .milliseconds(140))
    }
}
