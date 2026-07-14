import SwiftUI

#if os(tvOS)

/// Shared focus treatment for the already-styled tvOS hero action buttons
/// (detail heroes and the Discover carousel hero). Scales on focus without the
/// default bordered card plate that `.buttonStyle(.card)` would wrap around an
/// already-drawn capsule/circle label.
struct TVHeroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVHeroActionButtonBody(configuration: configuration)
    }

    private struct TVHeroActionButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? 1.1 : 1.0)
                .brightness(isFocused ? 0.06 : 0)
                .shadow(color: isFocused ? .black.opacity(0.55) : .clear, radius: 20, y: 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isFocused)
        }
    }
}

/// White capsule label for the primary hero action ("Play", "Details").
struct TVHeroCapsuleLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .frame(height: 52)
            .frame(minWidth: 180)
            .background(.white, in: Capsule())
    }
}

/// Circular glass icon label for secondary hero actions (favorite toggle,
/// carousel chevron). The single source of truth for this control's metrics —
/// every tvOS hero must render it identically.
struct TVHeroCircleIconLabel: View {
    let systemImage: String
    var isHighlighted = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background {
                Circle()
                    .fill(isHighlighted ? Color.green : Color.clear)
                    .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isHighlighted)
            }
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(isHighlighted ? .white.opacity(0.55) : .white.opacity(0.18), lineWidth: 0.8)
            }
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: isHighlighted)
    }
}

#endif
