import SwiftUI

/// The small MORE / LESS pill used to expand collapsed long-form text
/// (detail hero overviews, person biographies).
struct OverviewToggleButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        #if os(tvOS)
        .buttonStyle(TVHeroActionButtonStyle())
        #else
        .buttonStyle(.plain)
        #endif
    }
}
