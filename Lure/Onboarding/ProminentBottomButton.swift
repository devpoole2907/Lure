import SwiftUI

/// Prominent glass capsule button pinned to the bottom safe area. Matches
/// Trawl's onboarding call-to-action paradigm.
struct ProminentBottomButton: View {
    let title: LocalizedStringKey
    var systemImage: String? = nil
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                #if os(macOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .controlSize(.large)
        .fontWeight(.medium)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        #if os(macOS)
        .frame(width: 300)
        .padding(.horizontal, 24)
        .frame(height: 44)
        .padding(.top, 8)
        .padding(.bottom, 34)
        #else
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

extension View {
    func prominentBottomButton(
        _ title: LocalizedStringKey,
        systemImage: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
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
