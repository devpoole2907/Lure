import SwiftUI

/// Compact hero metadata item, such as content rating, availability status, or
/// file quality. The hero renders these as tight text rather than pills.
struct DetailBadge: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let color: Color
}
