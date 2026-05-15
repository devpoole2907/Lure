import Foundation

enum PlaybackAvailability: Equatable {
    case unknown
    case checking
    case playable(itemId: String)
    case missingInJellyfin
    case notConfigured
    case failed(String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var playableItemId: String? {
        if case .playable(let itemId) = self { return itemId }
        return nil
    }
}
