import Observation
import SwiftUI

enum LureTab: Hashable, Codable, Sendable {
    case discover
    case search
    case library
    case requests
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

    func reset() {
        selectedTab = .discover
        discoverPath = NavigationPath()
        morePath = []
    }

    @discardableResult
    func route(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "lure" else { return false }
        let routeParts = ([url.host].compactMap { $0 } + Array(url.pathComponents.dropFirst()))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        let route = routeParts.joined(separator: "/")

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
            selectedTab = .more
            morePath = [.settings]
        case "more/settings":
            selectedTab = .more
            morePath = [.settings]
        case "profile":
            selectedTab = .more
            morePath = [.profile]
        case "more/profile":
            selectedTab = .more
            morePath = [.profile]
        default:
            return false
        }
        return true
    }
}
