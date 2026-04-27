import Foundation
import SwiftData

@Model
final class LureServerProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var serverURL: String          // e.g. "http://192.168.1.50:5055"
    var isActive: Bool
    var dateAdded: Date
    var lastConnected: Date?
    var apnsWorkerURL: String?

    init(displayName: String, serverURL: String) {
        self.id = UUID()
        self.displayName = displayName
        self.serverURL = serverURL
        self.isActive = true
        self.dateAdded = .now
    }

    /// Keychain key for the session cookie
    var sessionCookieKey: String { "lure_\(id.uuidString)_session" }

    /// Normalized base URL (no trailing slash)
    var baseURL: String {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }
}
