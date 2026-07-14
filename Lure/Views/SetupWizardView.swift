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
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Welcome to Lure")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Request and discover media.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
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
        .frame(maxWidth: onboardingContentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .prominentBottomButton("Get Started") {
            welcomePath.append(.services)
        }
    }

    private var onboardingContentPadding: CGFloat {
        #if os(macOS)
        40
        #else
        32
        #endif
    }

    private var onboardingContentMaxWidth: CGFloat {
        #if os(macOS)
        480
        #else
        440
        #endif
    }

    @ViewBuilder
    private func featureRow(_ service: LureServiceIdentity) -> some View {
        HStack(spacing: 14) {
            Image(systemName: service.systemImage)
                .font(.title2)
                .foregroundStyle(service.brandColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(service.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .padding(.vertical, 2)
        #endif
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
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Choose Your Services")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Set up the services you want to use, then continue into the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
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
            .frame(maxWidth: onboardingContentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Choose Services")
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

    private var onboardingContentPadding: CGFloat {
        #if os(macOS)
        40
        #else
        32
        #endif
    }

    private var onboardingContentMaxWidth: CGFloat {
        #if os(macOS)
        500
        #else
        440
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
            HStack(spacing: 14) {
                Image(systemName: service.systemImage)
                    .font(.title2)
                    .foregroundStyle(service.brandColor)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isConfigured ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isConfigured ? Color.green : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            #if os(macOS)
            .frame(minHeight: 64)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
            #else
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
            #endif
        }
        .buttonStyle(.plain)
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
