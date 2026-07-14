import Observation
import SwiftUI

enum LureTab: Hashable, Codable, Sendable {
    case discover
    case search
    case library
    case requests
    case profile
    case settings
    case more
}

/// App-level navigation state.
///
/// Today this owns tab selection and the first migrated tab paths. Keeping it at
/// the app edge gives deep links, platform-specific shells, and future tvOS focus
/// roots one place to route without reaching into individual screens.
@MainActor
@Observable
final class LureRouter {
    var selectedTab: LureTab = .discover
    var discoverPath = NavigationPath()
    var morePath: [MoreDestination] = []

    /// Set when a `lure://item/<jellyfinId>` or `lure://play/<jellyfinId>` deep
    /// link arrives (e.g. from the tvOS Top Shelf). Consumers such as
    /// `DiscoverView` observe this, look up the item, navigate to its detail,
    /// and then clear the value.
    var pendingJellyfinItemId: String? = nil

    /// Set alongside `pendingJellyfinItemId` when the intent is immediate
    /// playback (`lure://play/<id>`).
    var pendingJellyfinItemAutoPlay: Bool = false

    func reset() {
        selectedTab = .discover
        discoverPath = NavigationPath()
        morePath = []
        pendingJellyfinItemId = nil
        pendingJellyfinItemAutoPlay = false
    }

    @discardableResult
    func route(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "lure" else { return false }
        let routeParts = ([url.host].compactMap { $0 } + Array(url.pathComponents.dropFirst()))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        let route = routeParts.joined(separator: "/")

        // lure://item/<jellyfinItemId> — open item detail (from Top Shelf displayAction)
        // lure://play/<jellyfinItemId>  — open item detail with auto-play intent
        if routeParts.count == 2 && (routeParts[0] == "item" || routeParts[0] == "play") {
            let jellyfinId = routeParts[1]
            selectedTab = .discover
            discoverPath = NavigationPath()
            pendingJellyfinItemId = jellyfinId
            pendingJellyfinItemAutoPlay = routeParts[0] == "play"
            return true
        }

        switch route {
        case "discover", "":
            selectedTab = .discover
            discoverPath = NavigationPath()
        case "search":
            selectedTab = .search
        case "library":
            selectedTab = .library
        case "requests":
            selectedTab = .requests
        case "more":
            selectedTab = .more
            morePath = []
        case "settings":
            #if os(macOS)
            selectedTab = .settings
            #else
            selectedTab = .more
            morePath = [.settings]
            #endif
        case "more/settings":
            #if os(macOS)
            selectedTab = .settings
            #else
            selectedTab = .more
            morePath = [.settings]
            #endif
        case "profile":
            #if os(macOS)
            selectedTab = .profile
            #else
            selectedTab = .more
            morePath = [.profile]
            #endif
        case "more/profile":
            #if os(macOS)
            selectedTab = .profile
            #else
            selectedTab = .more
            morePath = [.profile]
            #endif
        default:
            return false
        }
        return true
    }
}
