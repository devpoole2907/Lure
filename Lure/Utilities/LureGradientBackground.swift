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