import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct JellyfinCredentials: Codable, Sendable {
    var serverURL: String
    var token: String
    var userId: String
    var displayName: String

    private static let keychainKey = "LureJellyfinCredentials"

    /// Stable per-device, per-vendor identifier used in the Jellyfin
    /// Authorization header. Avoids the iCloud-backup propagation that a
    /// UserDefaults-stored UUID would suffer (same id appearing on multiple
    /// devices and causing Jellyfin session collisions).
    static var deviceId: String {
        #if canImport(UIKit)
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return id
        }
        #endif
        // identifierForVendor only nil when device hasn't been unlocked since
        // boot — exceedingly rare for foreground app code. Fall back to a
        // per-process UUID so we never persist (and never sync) an id.
        return fallbackDeviceId
    }

    private static let fallbackDeviceId: String = UUID().uuidString

    static func load() async -> JellyfinCredentials? {
        guard let json = await LureKeychain.shared.read(key: keychainKey),
              let data = json.data(using: .utf8),
              let creds = try? JSONDecoder().decode(JellyfinCredentials.self, from: data)
        else { return nil }
        return creds
    }

    func save() async throws {
        let data = try JSONEncoder().encode(self)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try await LureKeychain.shared.save(key: Self.keychainKey, value: json)
    }

    static func delete() async {
        try? await LureKeychain.shared.delete(key: keychainKey)
    }
}
