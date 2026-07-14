import SwiftUI

struct LureGradientBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [color.opacity(0.18), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            RadialGradient(
                colors: [color.opacity(0.14), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 260
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    func lureGradientBackground(_ color: Color) -> some View {
        background(LureGradientBackground(color: color))
    }
}

#if DEBUG && os(iOS)
#Preview("Lure Gradient Background — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    VStack(spacing: 14) {
        Image(systemName: "film.stack")
            .font(.system(size: 60, weight: .semibold))
            .foregroundStyle(.indigo)

        Text("Discover something new")
            .font(.largeTitle.bold())

        Text("Browse your library and request what to watch next.")
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .lureGradientBackground(.indigo)
}
#endif
