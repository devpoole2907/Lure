import SwiftUI

/// Compact hero metadata item, such as content rating, availability status, or
/// file quality. The hero renders these as tight text rather than pills.
struct DetailBadge: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let color: Color
}

struct DetailHeroRatingItem: Identifiable, Hashable {
    let label: String
    let value: String
    let destination: URL?

    init(label: String, value: String, destination: URL? = nil) {
        self.label = label
        self.value = value
        self.destination = destination
    }

    var id: String {
        [label, value, destination?.absoluteString]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    var text: String {
        "\(label) \(value)"
    }
}
