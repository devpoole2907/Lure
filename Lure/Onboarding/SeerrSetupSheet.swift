import SwiftUI
import SwiftData

/// Single-screen Seerr connection form, presented as a sheet during onboarding.
/// Drives the shared `AuthViewModel` (Seerr login uses Jellyfin credentials via
/// `loginJellyfin`). Mirrors Trawl's `SeerrConnectionFormView` paradigm.
struct SeerrSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var authViewModel: AuthViewModel
    var onComplete: (() -> Void)? = nil

    private var canSubmit: Bool {
        !authViewModel.serverURL.isEmpty
            && !authViewModel.username.isEmpty
            && !authViewModel.password.isEmpty
            && !authViewModel.isAuthenticating
    }

    var body: some View {
        #if os(macOS)
        AppSheetShell(
            title: "Add Seerr",
            confirmTitle: "Sign In",
            isConfirmDisabled: !canSubmit,
            isConfirmLoading: authViewModel.isAuthenticating,
            onConfirm: submit
        ) {
            SeerrConnectionForm(
                authViewModel: authViewModel,
                showsSubmitButton: false,
                onComplete: onComplete
            )
        }
        #elseif os(tvOS)
        AppSheetShell(title: "Add Seerr") {
            SeerrConnectionForm(authViewModel: authViewModel, onComplete: onComplete)
        }
        #else
        AppSheetShell(
            title: "Add Seerr",
            detents: [.large],
            dragIndicator: .visible
        ) {
            SeerrConnectionForm(authViewModel: authViewModel, onComplete: onComplete)
        }
        #endif
    }

    private func submit() {
        Task {
            let success = await authViewModel.connectAndLogin(modelContext: modelContext)
            if success {
                onComplete?()
                dismiss()
            }
        }
    }
}

private struct SeerrConnectionForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var authViewModel: AuthViewModel
    var showsSubmitButton = true
    var onComplete: (() -> Void)?

    private var canSubmit: Bool {
        !authViewModel.serverURL.isEmpty
            && !authViewModel.username.isEmpty
            && !authViewModel.password.isEmpty
            && !authViewModel.isAuthenticating
    }

    var body: some View {
        #if os(macOS)
        OnboardingMacSheetContent {
            Text("Connect Lure to your Seerr instance. Sign in with the username and password you were given.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingMacFieldGroup("Server") {
                ServerURLField(
                    url: $authViewModel.serverURL,
                    title: "Seerr URL (e.g. https://requests.example.com)"
                )
            }

            if let settings = authViewModel.publicSettings {
                LabeledContent("Connected Server", value: settings.applicationTitle ?? "Seerr")
                    .font(.callout)
            }

            OnboardingMacFieldGroup("Credentials") {
                TextField("Username", text: $authViewModel.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $authViewModel.password)
            }

            OnboardingMacValidationError(error: authViewModel.error)

            if showsSubmitButton {
                HStack {
                    Spacer()
                    Button(action: submit) {
                        submitLabel
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
        }
        .tint(LureServiceIdentity.seerr.brandColor)
        #elseif os(tvOS)
        OnboardingTVFormContent {
            Text("Connect Lure to your Seerr instance. Sign in with the username and password you were given.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingTVFieldGroup("Server") {
                ServerURLField(
                    url: $authViewModel.serverURL,
                    title: "Seerr URL (e.g. https://requests.example.com)"
                )
            }

            if let settings = authViewModel.publicSettings {
                LabeledContent("Connected Server", value: settings.applicationTitle ?? "Seerr")
                    .font(.title3)
            }

            OnboardingTVFieldGroup("Credentials") {
                TextField("Username", text: $authViewModel.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $authViewModel.password)
            }

            OnboardingTVValidationError(error: authViewModel.error)

            if showsSubmitButton {
                OnboardingTVPrimaryButton(isDisabled: !canSubmit, action: submit) {
                    submitLabel
                }
            }
        }
        .tint(LureServiceIdentity.seerr.brandColor)
        #else
        Form {
            Section {
                Text("Connect Lure to your Seerr instance. Sign in with the username and password you were given.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Server") {
                ServerURLField(
                    url: $authViewModel.serverURL,
                    title: "Seerr URL (e.g. https://requests.example.com)"
                )
            }

            if let settings = authViewModel.publicSettings {
                Section("Connected Server") {
                    LabeledContent("App", value: settings.applicationTitle ?? "Seerr")
                }
            }

            Section("Credentials") {
                TextField("Username", text: $authViewModel.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $authViewModel.password)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
            }

            if let error = authViewModel.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button(action: submit) {
                    submitLabel
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(!canSubmit)
            }
        }
        .tint(LureServiceIdentity.seerr.brandColor)
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        #endif
    }

    private var submitLabel: some View {
        HStack {
            if authViewModel.isAuthenticating {
                ProgressView()
                    .padding(.trailing, 4)
                Text("Connecting…")
            } else {
                Text("Sign In")
            }
        }
    }

    private func submit() {
        Task {
            let success = await authViewModel.connectAndLogin(modelContext: modelContext)
            if success {
                onComplete?()
                dismiss()
            }
        }
    }
}

#Preview("Add Seerr") {
    SeerrSetupSheet(authViewModel: OnboardingPreviewSupport.authViewModel())
        .modelContainer(OnboardingPreviewSupport.modelContainer)
}

#if DEBUG && os(iOS)
#Preview("Add Seerr — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    SeerrSetupSheet(authViewModel: OnboardingPreviewSupport.authViewModel())
        .modelContainer(OnboardingPreviewSupport.modelContainer)
}
#endif
