import SwiftUI

/// Branding for the two services Lure connects to. Mirrors Trawl's
/// `ServiceIdentity` paradigm so onboarding rows look and feel the same.
enum LureServiceIdentity: String, CaseIterable {
    case seerr
    case jellyfin

    var displayName: String {
        switch self {
        case .seerr: "Seerr"
        case .jellyfin: "Jellyfin"
        }
    }

    var brandColor: Color {
        switch self {
        case .seerr: .pink
        case .jellyfin: .indigo
        }
    }

    /// Filled glyph — use for rows, badges, and service-identity contexts.
    var systemImage: String {
        switch self {
        case .seerr: "eye.fill"
        case .jellyfin: "server.rack"
        }
    }

    /// One-line description shown under the service name in onboarding.
    var tagline: String {
        switch self {
        case .seerr: "Discover and request movies and TV shows"
        case .jellyfin: "Watch your media library directly"
        }
    }
}
