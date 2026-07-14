import SwiftUI
import SwiftData

struct SetupWizardView: View {
    @Bindable var authViewModel: AuthViewModel
    /// Called when the user redeems an invite (pasted on the intro screen).
    /// The parent owns invite presentation so deep-link and pasted invites share
    /// one redemption flow.
    var onInvite: (LureInvite) -> Void

    @State private var welcomePath: [WelcomeStep] = []
    @State private var showInvitePaste = false

    var body: some View {
        NavigationStack(path: $welcomePath) {
            welcomeIntroScreen
                .navigationDestination(for: WelcomeStep.self) { step in
                    switch step {
                    case .services:
                        ServiceSelectionScreen(authViewModel: authViewModel)
                    }
                }
        }
        .sheet(isPresented: $showInvitePaste) {
            InvitePasteSheet { invite in
                showInvitePaste = false
                onInvite(invite)
            }
        }
    }

    private var welcomeIntroScreen: some View {
        VStack(spacing: welcomeIntroSpacing) {
            VStack(spacing: welcomeHeaderSpacing) {
                Image(systemName: "film.stack")
                    .font(welcomeIconFont)
                    .foregroundStyle(.tint)

                Text("Welcome to Lure")
                    .font(welcomeTitleFont)
                    .bold()

                Text("Request and discover media.")
                    .font(welcomeSubtitleFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: featureRowSpacing) {
                ForEach(LureServiceIdentity.allCases, id: \.self) { service in
                    featureRow(service)
                }
            }
            .padding(.horizontal, 8)

            Button {
                showInvitePaste = true
            } label: {
                Label("Have an invite link?", systemImage: "envelope.fill")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(onboardingContentPadding)
        .padding(.bottom, onboardingBottomPadding)
        .frame(maxWidth: onboardingContentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .prominentBottomButton("Get Started") {
            welcomePath.append(.services)
        }
    }

    private var welcomeIntroSpacing: CGFloat {
        #if os(tvOS)
        52
        #else
        32
        #endif
    }

    private var welcomeHeaderSpacing: CGFloat {
        #if os(tvOS)
        18
        #else
        12
        #endif
    }

    private var welcomeIconFont: Font {
        #if os(tvOS)
        .system(size: 88, weight: .semibold)
        #else
        .system(size: 56)
        #endif
    }

    private var welcomeTitleFont: Font {
        #if os(tvOS)
        .system(size: 64, weight: .bold)
        #else
        .largeTitle
        #endif
    }

    private var welcomeSubtitleFont: Font {
        #if os(tvOS)
        .title3
        #else
        .subheadline
        #endif
    }

    private var featureRowSpacing: CGFloat {
        #if os(tvOS)
        20
        #else
        16
        #endif
    }

    private var onboardingContentPadding: CGFloat {
        #if os(tvOS)
        90
        #elseif os(macOS)
        40
        #else
        32
        #endif
    }

    private var onboardingBottomPadding: CGFloat {
        #if os(tvOS)
        130
        #else
        0
        #endif
    }

    private var onboardingContentMaxWidth: CGFloat {
        #if os(tvOS)
        940
        #elseif os(macOS)
        480
        #else
        440
        #endif
    }

    private var featureIconFont: Font {
        #if os(tvOS)
        .system(size: 36, weight: .semibold)
        #else
        .title2
        #endif
    }

    private var featureTitleFont: Font {
        #if os(tvOS)
        .title3.weight(.semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }

    private var featureSubtitleFont: Font {
        #if os(tvOS)
        .body
        #else
        .caption
        #endif
    }

    private var featureIconWidth: CGFloat {
        #if os(tvOS)
        58
        #else
        36
        #endif
    }

    private var featureRowHorizontalPadding: CGFloat {
        #if os(tvOS)
        24
        #else
        0
        #endif
    }

    private var featureRowVerticalPadding: CGFloat {
        #if os(tvOS)
        20
        #elseif os(macOS)
        2
        #else
        0
        #endif
    }

    private var featureRowMinHeight: CGFloat? {
        #if os(tvOS)
        96
        #else
        nil
        #endif
    }

    private var featureRowCornerRadius: CGFloat {
        #if os(tvOS)
        24
        #else
        0
        #endif
    }

    @ViewBuilder
    private var featureRowBackground: some View {
        #if os(tvOS)
        RoundedRectangle(cornerRadius: featureRowCornerRadius)
            .fill(.regularMaterial)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func featureRow(_ service: LureServiceIdentity) -> some View {
        HStack(spacing: 14) {
            Image(systemName: service.systemImage)
                .font(featureIconFont)
                .foregroundStyle(service.brandColor)
                .frame(width: featureIconWidth)

            VStack(alignment: .leading, spacing: 4) {
                Text(service.displayName)
                    .font(featureTitleFont)
                Text(service.tagline)
                    .font(featureSubtitleFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, featureRowHorizontalPadding)
        .padding(.vertical, featureRowVerticalPadding)
        .frame(minHeight: featureRowMinHeight, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(featureRowBackground)
    }
}

enum WelcomeStep: Hashable {
    case services
}

private struct ServiceSelectionScreen: View {
    @Environment(JellyfinService.self) private var jellyfinService
    @Bindable var authViewModel: AuthViewModel
    @State private var showSeerrSetup = false
    @State private var showJellyfinSetup = false
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    private var isSeerrConfigured: Bool { authViewModel.isLoggedIn }
    private var isJellyfinConfigured: Bool { jellyfinService.hasCredentials }

    var body: some View {
        ScrollView {
            VStack(spacing: serviceContentSpacing) {
                VStack(spacing: 14) {
                    Text("Choose Your Services")
                        .font(serviceTitleFont)
                        .bold()
                        .multilineTextAlignment(.center)

                    Text("Set up the services you want to use, then continue into the app.")
                        .font(serviceSubtitleFont)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: setupRowSpacing) {
                    setupRow(
                        .seerr,
                        description: "Required — discover and request media",
                        isConfigured: isSeerrConfigured
                    ) { showSeerrSetup = true }

                    setupRow(
                        .jellyfin,
                        description: "Optional — adds in-app playback",
                        isConfigured: isJellyfinConfigured
                    ) { showJellyfinSetup = true }
                }
            }
            .padding(onboardingContentPadding)
            .padding(.bottom, onboardingBottomPadding)
            .frame(maxWidth: onboardingContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .navigationTitle("")
        #else
        .navigationTitle("Choose Services")
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .prominentBottomButton("Go", isDisabled: !isSeerrConfigured) {
            hasFinishedOnboarding = true
        }
        .sheet(isPresented: $showSeerrSetup) {
            SeerrSetupSheet(authViewModel: authViewModel)
        }
        .sheet(isPresented: $showJellyfinSetup) {
            JellyfinSetupSheet()
                .environment(jellyfinService)
        }
    }

    private var serviceContentSpacing: CGFloat {
        #if os(tvOS)
        48
        #else
        24
        #endif
    }

    private var setupRowSpacing: CGFloat {
        #if os(tvOS)
        24
        #else
        12
        #endif
    }

    private var serviceTitleFont: Font {
        #if os(tvOS)
        .system(size: 56, weight: .bold)
        #else
        .largeTitle
        #endif
    }

    private var serviceSubtitleFont: Font {
        #if os(tvOS)
        .title3
        #else
        .subheadline
        #endif
    }

    private var onboardingContentPadding: CGFloat {
        #if os(tvOS)
        90
        #elseif os(macOS)
        40
        #else
        32
        #endif
    }

    private var onboardingBottomPadding: CGFloat {
        #if os(tvOS)
        150
        #else
        0
        #endif
    }

    private var onboardingContentMaxWidth: CGFloat {
        #if os(tvOS)
        1040
        #elseif os(macOS)
        500
        #else
        440
        #endif
    }

    private var setupIconFont: Font {
        #if os(tvOS)
        .system(size: 42, weight: .semibold)
        #else
        .title2
        #endif
    }

    private var setupTitleFont: Font {
        #if os(tvOS)
        .title2.weight(.semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }

    private var setupDescriptionFont: Font {
        #if os(tvOS)
        .body
        #else
        .caption
        #endif
    }

    private var setupStatusFont: Font {
        #if os(tvOS)
        .system(size: 34, weight: .semibold)
        #else
        .title3
        #endif
    }

    private var setupIconWidth: CGFloat {
        #if os(tvOS)
        70
        #else
        36
        #endif
    }

    private var setupRowHorizontalPadding: CGFloat {
        #if os(tvOS)
        30
        #else
        16
        #endif
    }

    private var setupRowVerticalPadding: CGFloat {
        #if os(tvOS)
        26
        #else
        14
        #endif
    }

    private var setupRowMinHeight: CGFloat {
        #if os(tvOS)
        124
        #elseif os(macOS)
        64
        #else
        0
        #endif
    }

    @ViewBuilder
    private func setupRowBackground() -> some View {
        #if os(tvOS)
        RoundedRectangle(cornerRadius: 26)
            .fill(.regularMaterial)
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private func setupRow(
        _ service: LureServiceIdentity,
        description: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: service.systemImage)
                    .font(setupIconFont)
                    .foregroundStyle(service.brandColor)
                    .frame(width: setupIconWidth)

                VStack(alignment: .leading, spacing: 6) {
                    Text(service.displayName)
                        .font(setupTitleFont)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(setupDescriptionFont)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle")
                    .font(setupStatusFont)
                    .foregroundStyle(isConfigured ? Color.green : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, setupRowHorizontalPadding)
            .padding(.vertical, setupRowVerticalPadding)
            .frame(minHeight: setupRowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            #if os(macOS)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
            #elseif os(tvOS)
            .background(setupRowBackground())
            #else
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
    }
}

/// Paste box for an invite link sent over text/email. Accepts a `lure://invite`
/// (or legacy `lure://connect`) URL and hands a parsed `LureInvite` back.
private struct InvitePasteSheet: View {
    var onInvite: (LureInvite) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        #if os(macOS)
        AppSheetShell(
            title: "Enter Invite",
            confirmTitle: "Continue",
            isConfirmDisabled: isSubmitDisabled,
            onConfirm: submit
        ) {
            OnboardingMacSheetContent {
                Text("Paste the invite link you were sent. It sets up your servers automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingMacFieldGroup("Invite Link") {
                    TextField("lure://invite?...", text: $text, axis: .vertical)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                }

                OnboardingMacValidationError(error: error)
            }
        }
        #elseif os(tvOS)
        AppSheetShell(title: "Enter Invite") {
            OnboardingTVFormContent(width: 900) {
                Text("Paste the invite link you were sent. It sets up your servers automatically.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                OnboardingTVFieldGroup("Invite Link") {
                    TextField("lure://invite?...", text: $text, axis: .vertical)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                }

                OnboardingTVValidationError(error: error)

                OnboardingTVPrimaryButton(width: 320, isDisabled: isSubmitDisabled, action: submit) {
                    Text("Continue")
                }
            }
        }
        #else
        AppSheetShell(
            title: "Enter Invite",
            detents: [.medium, .large],
            dragIndicator: .visible
        ) {
            Form {
                Section {
                    Text("Paste the invite link you were sent. It sets up your servers automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Invite Link") {
                    TextField("lure://invite?…", text: $text, axis: .vertical)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button(action: submit) {
                        Text("Continue")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(isSubmitDisabled)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
        #endif
    }

    private var isSubmitDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        if let invite = LureInvite.parse(pasted: text) {
            dismiss()
            onInvite(invite)
        } else {
            error = "That doesn't look like a valid invite link."
        }
    }
}

#Preview("Welcome") {
    SetupWizardView(authViewModel: OnboardingPreviewSupport.authViewModel()) { _ in }
        .environment(JellyfinService())
}

#Preview("Choose Services") {
    ServiceSelectionScreen(authViewModel: OnboardingPreviewSupport.authViewModel())
        .environment(JellyfinService())
}

#Preview("Invite Link Sheet") {
    InvitePasteSheet { _ in }
}
