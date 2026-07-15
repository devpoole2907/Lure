import SwiftUI

#if os(tvOS)

/// Shared focus treatment for the already-styled tvOS hero action buttons
/// (detail heroes and the Discover carousel hero), without the default
/// bordered card plate that `.buttonStyle(.card)` would wrap around an
/// already-drawn capsule/circle label. The system highlight effect provides
/// the native scale, shadow, specular shimmer, and remote-tracking tilt.
struct TVHeroActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Every label this style wraps is capsule-shaped; without an explicit
        // content shape the highlight renders against rectangular bounds.
        configuration.label
            .contentShape(Capsule())
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight)
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
/// every tvOS hero must render it identically. A Capsule renders as a circle
/// at the resting 52×52 size, and stretches into a pill while `expandedText`
/// is non-nil (the transient "Added" confirmation).
struct TVHeroCircleIconLabel: View {
    let systemImage: String
    var isHighlighted = false
    var expandedText: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
            if let expandedText {
                Text(expandedText)
                    .font(.headline.weight(.semibold))
                    .fixedSize()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, expandedText != nil ? 24 : 0)
        .frame(minWidth: 52)
        .frame(height: 52)
        .background {
            Capsule()
                .fill(isHighlighted ? Color.green : Color.clear)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isHighlighted)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(isHighlighted ? .white.opacity(0.55) : .white.opacity(0.18), lineWidth: 0.8)
        }
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: isHighlighted)
    }
}

#endif
