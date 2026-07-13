import SwiftUI

struct DetailPosterHeroAction {
    let title: String
    let systemImage: String
    var isEnabled = true
    var isHighlighted = false
    let action: () -> Void
}
