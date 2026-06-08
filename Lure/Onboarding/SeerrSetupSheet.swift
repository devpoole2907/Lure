import SwiftUI
import SwiftData

/// Single-screen Seerr connection form, presented as a sheet during onboarding.
/// Drives the shared `AuthViewModel` (Seerr login uses Jellyfin credentials via
/// `loginJellyfin`). Mirrors Trawl's `SeerrConnectionFormView` paradigm.
struct SeerrSetupSheet: View {
    @Bindable var authViewModel: AuthViewModel
    var onComplete: (() -> Void)? = nil

    var body: some View {
        AppSheetShell(
            title: "Add Seerr",
            detents: [.large],
            dragIndicator: .visible
        ) {
            SeerrConnectionForm(authViewModel: authViewModel, onComplete: onComplete)
        }
    }
}

private struct SeerrConnectionForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var authViewModel: AuthViewModel
    var onComplete: (() -> Void)?

    private var canSubmit: Bool {
        !authViewModel.serverURL.isEmpty
            && !authViewModel.username.isEmpty
            && !authViewModel.password.isEmpty
            && !authViewModel.isAuthenticating
    }

    var body: some View {
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
                Button {
                    Task {
                        let success = await authViewModel.connectAndLogin(modelContext: modelContext)
                        if success {
                            onComplete?()
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if authViewModel.isAuthenticating {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Connecting…")
                        } else {
                            Text("Sign In")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(!canSubmit)
            }
        }
        .tint(LureServiceIdentity.seerr.brandColor)
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
    }
}
