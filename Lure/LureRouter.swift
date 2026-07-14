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
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()
    var requestsPath = NavigationPath()
    var morePath: [MoreDestination] = []
    var isProfilePresented = false

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
        searchPath = NavigationPath()
        libraryPath = NavigationPath()
        requestsPath = NavigationPath()
        morePath = []
        isProfilePresented = false
        pendingJellyfinItemId = nil
        pendingJellyfinItemAutoPlay = false
    }

    func openMedia(_ destination: MediaDestination) {
        switch selectedTab {
        case .discover:
            discoverPath.append(destination)
        case .search:
            searchPath.append(destination)
        case .library:
            libraryPath.append(destination)
        case .requests:
            requestsPath.append(destination)
        case .profile, .settings, .more:
            selectedTab = .discover
            discoverPath.append(destination)
        }
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
            searchPath = NavigationPath()
        case "library":
            selectedTab = .library
            libraryPath = NavigationPath()
        case "requests":
            selectedTab = .requests
            requestsPath = NavigationPath()
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
            isProfilePresented = true
            #else
            selectedTab = .more
            morePath = [.profile]
            #endif
        case "more/profile":
            #if os(macOS)
            isProfilePresented = true
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
