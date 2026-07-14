import SwiftUI

#if os(macOS)
struct OnboardingMacSheetContent<Content: View>: View {
    var width: CGFloat = 440
    let content: Content

    init(width: CGFloat = 440, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            content
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .frame(width: width, alignment: .leading)
    }
}

struct OnboardingMacFieldGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout)
                .bold()

            content
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingMacValidationError: View {
    let error: String?

    var body: some View {
        if let error {
            Label {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
#endif

#if os(tvOS)
struct OnboardingTVFormContent<Content: View>: View {
    var width: CGFloat = 980
    let content: Content

    init(width: CGFloat = 980, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                content
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 64)
            .frame(maxWidth: width, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollClipDisabled()
        .background(.black.opacity(0.001))
    }
}

struct OnboardingTVFieldGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            content
                .font(.title3)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OnboardingTVPrimaryButton<Label: View>: View {
    var width: CGFloat = 340
    var isDisabled = false
    let action: @MainActor () -> Void
    let label: Label

    init(
        width: CGFloat = 340,
        isDisabled: Bool = false,
        action: @escaping @MainActor () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.width = width
        self.isDisabled = isDisabled
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.title3.weight(.semibold))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.48) : Color.black)
                .frame(width: width, height: 68)
                .background(
                    isDisabled ? Color.white.opacity(0.12) : Color.white,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct OnboardingTVValidationError: View {
    let error: String?

    var body: some View {
        if let error {
            Label {
                Text(error)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct OnboardingTVSection<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            content
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
