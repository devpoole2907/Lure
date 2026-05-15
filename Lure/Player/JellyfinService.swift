import Foundation
import Observation

/// Owns the single `JellyfinAPIClient` for the app and caches Jellyfin item-id
/// lookups so detail views and the player don't each re-scan the library.
///
/// Inject via `.environment(jellyfinService)` from the root and consume from
/// view-models / views with `@Environment(JellyfinService.self)`.
@Observable
@MainActor
final class JellyfinService {
    private(set) var client: JellyfinAPIClient?
    private(set) var hasCredentials: Bool = false

    private enum CachedLookup {
        case found(String)
        case missing
    }
    private var lookupCache: [String: CachedLookup] = [:]

    /// Read the current credentials from the keychain and (re)build the client.
    func reload() async {
        guard let creds = await JellyfinCredentials.load() else {
            client = nil
            hasCredentials = false
            lookupCache.removeAll()
            return
        }
        client = JellyfinAPIClient(credentials: creds)
        hasCredentials = true
        lookupCache.removeAll()
    }

    /// Wipe credentials from the keychain and forget the client. Call on logout.
    func clearCredentials() async {
        await JellyfinCredentials.delete()
        client = nil
        hasCredentials = false
        lookupCache.removeAll()
    }

    /// Discard cached id lookups (e.g. after a library refresh or manual retry).
    func invalidateLookups() {
        lookupCache.removeAll()
    }

    // MARK: - Convenience

    func resumeItems(limit: Int = 20) async -> [JellyfinItem] {
        guard let client else { return [] }
        return (try? await client.getResumeItems(limit: limit)) ?? []
    }

    func allLibraryItems() async -> [JellyfinItem] {
        guard let client else { return [] }
        return (try? await client.getAllLibraryItems()) ?? []
    }

    /// Cached `findItemId`. Returns nil when the item isn't in the library.
    func findItemId(
        serviceUrl: String?,
        tmdbId: Int,
        mediaType: String,
        title: String?,
        releaseYear: Int?
    ) async throws -> String? {
        guard let client else { return nil }
        let key = cacheKey(tmdbId: tmdbId, mediaType: mediaType, serviceUrl: serviceUrl)
        if let cached = lookupCache[key] {
            switch cached {
            case .found(let id): return id
            case .missing: return nil
            }
        }
        let result = try await client.findItemId(
            serviceUrl: serviceUrl,
            tmdbId: tmdbId,
            mediaType: mediaType,
            title: title,
            releaseYear: releaseYear
        )
        lookupCache[key] = result.map(CachedLookup.found) ?? .missing
        return result
    }

    func resolvePlaybackAvailability(
        tmdbId: Int,
        mediaType: String,
        title: String,
        releaseYear: Int?,
        serviceUrl: String? = nil
    ) async -> PlaybackAvailability {
        guard hasCredentials else { return .notConfigured }
        do {
            if let itemId = try await findItemId(
                serviceUrl: serviceUrl,
                tmdbId: tmdbId,
                mediaType: mediaType,
                title: title,
                releaseYear: releaseYear
            ) {
                return .playable(itemId: itemId)
            } else {
                return .missingInJellyfin
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func cacheKey(tmdbId: Int, mediaType: String, serviceUrl: String?) -> String {
        "\(mediaType)-\(tmdbId)-\(serviceUrl ?? "")"
    }
}
