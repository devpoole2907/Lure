import SwiftUI

/// Single-screen Jellyfin connection form, presented as a sheet during
/// onboarding. Authenticates with `JellyfinAPIClient.authenticate` and stores
/// credentials via `JellyfinService`. Mirrors Trawl's `JellyfinConnectionFormView`.
struct JellyfinSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinService.self) private var jellyfinService
    @State private var viewModel = JellyfinSetupFormViewModel()
    var onComplete: (() -> Void)? = nil

    var body: some View {
        #if os(macOS)
        AppSheetShell(
            title: "Add Jellyfin",
            confirmTitle: "Sign In",
            isConfirmDisabled: !viewModel.canConnect,
            isConfirmLoading: viewModel.isAuthenticating,
            onConfirm: submit
        ) {
            JellyfinConnectionForm(
                viewModel: viewModel,
                showsSubmitButton: false,
                onComplete: onComplete
            )
        }
        #else
        AppSheetShell(
            title: "Add Jellyfin",
            detents: [.large],
            dragIndicator: .visible
        ) {
            JellyfinConnectionForm(viewModel: viewModel, onComplete: onComplete)
        }
        #endif
    }

    private func submit() {
        Task {
            let success = await viewModel.connect(jellyfinService: jellyfinService)
            if success {
                onComplete?()
                dismiss()
            }
        }
    }
}

private struct JellyfinConnectionForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(JellyfinService.self) private var jellyfinService
    @Bindable var viewModel: JellyfinSetupFormViewModel
    var showsSubmitButton = true
    var onComplete: (() -> Void)?

    var body: some View {
        #if os(macOS)
        OnboardingMacSheetContent {
            Text("Connect to your Jellyfin server to watch your library directly in Lure. This is optional — you can add it later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingMacFieldGroup("Server") {
                ServerURLField(
                    url: $viewModel.hostURL,
                    title: "Jellyfin URL (e.g. https://watch.example.com)"
                )
            }

            OnboardingMacFieldGroup("Credentials") {
                TextField("Username", text: $viewModel.username)
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
            }

            OnboardingMacValidationError(error: viewModel.error)

            if showsSubmitButton {
                HStack {
                    Spacer()
                    Button(action: submit) {
                        submitLabel
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canConnect)
                }
            }
        }
        .tint(LureServiceIdentity.jellyfin.brandColor)
        #else
        Form {
            Section {
                Text("Connect to your Jellyfin server to watch your library directly in Lure. This is optional — you can add it later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Server") {
                ServerURLField(
                    url: $viewModel.hostURL,
                    title: "Jellyfin URL (e.g. https://watch.example.com)"
                )
            }

            Section("Credentials") {
                TextField("Username", text: $viewModel.username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .textContentType(.username)
                    #endif
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
            }

            ValidationErrorSection(error: viewModel.error)

            Section {
                Button(action: submit) {
                    submitLabel
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(!viewModel.canConnect)
            }
        }
        .tint(LureServiceIdentity.jellyfin.brandColor)
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        #endif
    }

    private var submitLabel: some View {
        HStack {
            if viewModel.isAuthenticating {
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
            let success = await viewModel.connect(jellyfinService: jellyfinService)
            if success {
                onComplete?()
                dismiss()
            }
        }
    }
}

@MainActor
@Observable
final class JellyfinSetupFormViewModel {
    var hostURL: String = ""
    var username: String = ""
    var password: String = ""
    var isAuthenticating: Bool = false
    var error: String?

    var canConnect: Bool {
        !isAuthenticating
            && !hostURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    /// Authenticate and store credentials. Returns true on success.
    func connect(jellyfinService: JellyfinService) async -> Bool {
        error = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let creds = try await JellyfinSetupFormViewModel.authenticate(
                serverURL: hostURL,
                username: username,
                password: password
            )
            try await creds.save()
            await jellyfinService.reload()
            return true
        } catch JellyfinError.unauthorized {
            error = "Incorrect username or password."
            return false
        } catch JellyfinError.badURL {
            error = "Invalid server URL."
            return false
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Shared authentication step (also used by invite redemption).
    static func authenticate(
        serverURL: String,
        username: String,
        password: String
    ) async throws -> JellyfinCredentials {
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url = String(url.dropLast()) }

        return try await JellyfinAPIClient.authenticate(
            serverURL: url,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}

#Preview("Add Jellyfin") {
    JellyfinSetupSheet()
        .environment(JellyfinService())
}
