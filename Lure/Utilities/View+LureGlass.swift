import SwiftUI

extension View {
    func lureCard(radius: CGFloat = 16) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
    }

    func lureCardInteractive(radius: CGFloat = 14) -> some View {
        glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius))
    }

    func lureButtonGlass() -> some View {
        glassEffect(.regular.interactive(), in: Capsule())
    }
}