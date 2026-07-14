import SwiftUI

/// Prominent glass capsule button pinned to the bottom safe area. Matches
/// Trawl's onboarding call-to-action paradigm.
struct ProminentBottomButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isLoading = false
    var isDisabled = false
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            label
                #if os(macOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        #if os(tvOS)
        // tvOS: render the button content as a plain capsule with a custom
        // focus-scale effect. Applying .card on top of .glassProminent adds a
        // second bordered plate — use a single chrome layer instead.
        .font(.title3.weight(.semibold))
        .frame(width: 440)
        .frame(height: 72)
        .padding(.horizontal, 90)
        .padding(.top, 24)
        .padding(.bottom, 64)
        .buttonStyle(TVProminentCapsuleButtonStyle())
        #elseif os(macOS)
        .controlSize(.large)
        .fontWeight(.medium)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .frame(width: 300)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .padding(.top, 8)
        .padding(.bottom, 34)
        #else
        .controlSize(.large)
        .fontWeight(.medium)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .buttonSizing(.flexible)
        .scenePadding(.horizontal)
        #endif
        .disabled(isDisabled || isLoading)
    }

    @ViewBuilder
    private var label: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

#if os(tvOS)
/// Single-chrome capsule button style for tvOS onboarding CTAs.
/// Draws a white-filled capsule and applies scale/brightness on focus
/// without the double-border that `.card` would add around an existing label.
private struct TVProminentCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TVProminentCapsuleBody(configuration: configuration)
    }

    private struct TVProminentCapsuleBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? Color.black : Color.white.opacity(0.48))
                .frame(maxWidth: .infinity)
                .background(
                    isEnabled ? Color.white : Color.white.opacity(0.14),
                    in: Capsule()
                )
                .scaleEffect(isFocused ? 1.06 : 1.0)
                .brightness(isFocused ? 0.08 : 0)
                .shadow(color: isFocused ? .black.opacity(0.45) : .clear, radius: 20, y: 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isFocused)
        }
    }
}
#endif

extension View {
    func prominentBottomButton(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        safeAreaInset(edge: .bottom) {
            ProminentBottomButton(
                title: title,
                systemImage: systemImage,
                isLoading: isLoading,
                isDisabled: isDisabled,
                action: action
            )
        }
    }
}

#Preview("Prominent Button") {
    VStack {
        Spacer()
    }
    .prominentBottomButton("Get Started") {}
}

#if DEBUG && os(iOS)
#Preview("Prominent Button — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    VStack {
        Image(systemName: "film.stack")
            .font(.system(size: 56))
            .foregroundStyle(.tint)
        Text("Welcome to Lure")
            .font(.largeTitle.bold())
        Spacer()
    }
    .padding(.top, 80)
    .prominentBottomButton("Get Started", systemImage: "arrow.right") {}
}
#endif
