/// TopShelfCredentialStore — lightweight, standalone credential store shared
/// between the main Lure app and the LureTopShelf extension via App Group
/// UserDefaults. The extension cannot use LureKeychain (which uses the app's
/// primary keychain service) but can read from a shared defaults suite that
/// the app writes whenever credentials change.
///
/// - Thread safety: all methods are nonisolated; call from any context.
/// - The store intentionally uses Foundation only (no AppKit/UIKit/TVKit) so it
///   compiles for every platform the project targets.

import Foundation

struct TopShelfCredentials: Codable, Sendable {
    var serverURL: String
    var token: String
    var userId: String
}

enum TopShelfCredentialStore {
    // Keep in sync with the value registered in the developer portal and
    // set in Lure.entitlements / LureTopShelf.entitlements.
    static let appGroupID = "group.com.poole.james.Lure"

    private static let defaultsKey = "lure.topShelf.credentials"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Write credentials so the Top Shelf extension can read them.
    /// Call this every time JellyfinCredentials are saved (login / refresh).
    static func save(_ credentials: TopShelfCredentials) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Clear the stored credentials (called on Jellyfin sign-out).
    static func clear() {
        defaults?.removeObject(forKey: defaultsKey)
    }

    /// Read previously saved credentials. Returns nil when not configured.
    static func load() -> TopShelfCredentials? {
        guard let defaults,
              let data = defaults.data(forKey: defaultsKey),
              let creds = try? JSONDecoder().decode(TopShelfCredentials.self, from: data)
        else { return nil }
        return creds
    }
}
