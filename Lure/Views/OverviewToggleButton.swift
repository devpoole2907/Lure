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

#if DEBUG && os(iOS)
#Preview("Overview Toggle — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    ZStack {
        LinearGradient(
            colors: [.black, .indigo.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        OverviewToggleButton(title: "MORE") {}
    }
}
#endif
