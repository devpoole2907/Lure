import SwiftUI
import SwiftData

/// One-shot setup screen reached by tapping a `lure://invite` link (or pasting
/// an invite). Shows the servers the invite will configure and asks for a single
/// sign-in. Seerr is required; Jellyfin is optional and soft-fails so playback
/// can be added later without blocking entry into the app.
struct InviteRedemptionView: View {
    let invite: LureInvite
    let authViewModel: AuthViewModel
    /// Called once setup succeeds. `jellyfinWarning` is true when an invite
    /// included Jellyfin but it couldn't be configured (Seerr still succeeded).
    var onFinished: (_ jellyfinWarning: Bool) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(JellyfinService.self) private var jellyfinService
    @State private var viewModel: InviteRedemptionViewModel
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    init(
        invite: LureInvite,
        authViewModel: AuthViewModel,
        onFinished: @escaping (_ jellyfinWarning: Bool) -> Void
    ) {
        self.invite = invite
        self.authViewModel = authViewModel
        self.onFinished = onFinished
        _viewModel = State(initialValue: InviteRedemptionViewModel(invite: invite))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("You're Invited")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .prominentBottomButton(
                    "Sign In",
                    isLoading: viewModel.isWorking,
                    isDisabled: !viewModel.canSubmit
                ) {
                    Task { await submit() }
                }
                #endif
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView {
            VStack(spacing: 24) {
                invitedHeader

                VStack(spacing: 18) {
                    macSection("This invite will set up") {
                        VStack(alignment: .leading, spacing: 12) {
                            serverRow(.seerr, url: invite.seerrURL)
                            if let jellyfinURL = invite.jellyfinURL, invite.hasJellyfin {
                                Divider()
                                serverRow(.jellyfin, url: jellyfinURL)
                            }
                        }
                    }

                    macSection("Sign In") {
                        VStack(spacing: 10) {
                            TextField("Username", text: $viewModel.username)
                                .autocorrectionDisabled()
                            SecureField("Password", text: $viewModel.password)
                        }
                        .textFieldStyle(.roundedBorder)
                    }

                    if invite.hasJellyfin {
                        macSection("Jellyfin") {
                            VStack(alignment: .leading, spacing: 12) {
                                Toggle("Use the same login for Jellyfin", isOn: $viewModel.useSameLoginForJellyfin)

                                if !viewModel.useSameLoginForJellyfin {
                                    VStack(spacing: 10) {
                                        TextField("Jellyfin Username", text: $viewModel.jellyfinUsername)
                                            .autocorrectionDisabled()
                                        SecureField("Jellyfin Password", text: $viewModel.jellyfinPassword)
                                    }
                                    .textFieldStyle(.roundedBorder)
                                }

                                Text("Most setups use one account for both. Turn this off if your Jellyfin sign-in is different.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    OnboardingMacValidationError(error: viewModel.error)

                    Button {
                        Task { await submit() }
                    } label: {
                        signInLabel
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .frame(width: 300)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.canSubmit)
                }
            }
            .padding(40)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
            Form {
                Section {
                    invitedHeader
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("This invite will set up") {
                    serverRow(.seerr, url: invite.seerrURL)
                    if let jellyfinURL = invite.jellyfinURL, invite.hasJellyfin {
                        serverRow(.jellyfin, url: jellyfinURL)
                    }
                }

                Section("Sign In") {
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

                if invite.hasJellyfin {
                    Section {
                        Toggle("Use the same login for Jellyfin", isOn: $viewModel.useSameLoginForJellyfin)
                    } footer: {
                        Text("Most setups use one account for both. Turn this off if your Jellyfin sign-in is different.")
                    }

                    if !viewModel.useSameLoginForJellyfin {
                        Section("Jellyfin Sign In") {
                            TextField("Jellyfin Username", text: $viewModel.jellyfinUsername)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .textContentType(.username)
                                #endif
                                .autocorrectionDisabled()
                            SecureField("Jellyfin Password", text: $viewModel.jellyfinPassword)
                                #if os(iOS)
                                .textContentType(.password)
                                #endif
                        }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
        #endif
    }

    private var invitedHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(invite.displayName ?? "Welcome to Lure")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            Text("You've been invited. Sign in with the username and password you were given to finish setup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var signInLabel: some View {
        HStack {
            if viewModel.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }
            Text("Sign In")
        }
    }

    #if os(macOS)
    private func macSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    #endif

    private func serverRow(_ identity: LureServiceIdentity, url: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: identity.systemImage)
                .font(.title3)
                .foregroundStyle(identity.brandColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(url)
                    #if os(macOS)
                    .font(.caption)
                    #else
                    .font(.caption2)
                    #endif
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func submit() async {
        let result = await viewModel.redeem(
            authViewModel: authViewModel,
            jellyfinService: jellyfinService,
            modelContext: modelContext
        )
        switch result {
        case .seerrFailed:
            break // error is surfaced inline via viewModel.error
        case .success(let jellyfinWarning):
            hasFinishedOnboarding = true
            onFinished(jellyfinWarning)
        }
    }
}

#Preview("Redeem Invite") {
    InviteRedemptionView(
        invite: OnboardingPreviewSupport.invite,
        authViewModel: OnboardingPreviewSupport.authViewModel()
    ) { _ in }
    .environment(JellyfinService())
    .modelContainer(OnboardingPreviewSupport.modelContainer)
}

@MainActor
@Observable
final class InviteRedemptionViewModel {
    let invite: LureInvite
    var username: String
    var password: String = ""
    var useSameLoginForJellyfin: Bool = true
    var jellyfinUsername: String = ""
    var jellyfinPassword: String = ""
    var isWorking: Bool = false
    var error: String?

    init(invite: LureInvite) {
        self.invite = invite
        self.username = invite.username ?? ""
    }

    enum RedeemResult {
        case seerrFailed
        case success(jellyfinWarning: Bool)
    }

    var canSubmit: Bool {
        guard !isWorking,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty
        else { return false }

        if invite.hasJellyfin && !useSameLoginForJellyfin {
            return !jellyfinUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !jellyfinPassword.isEmpty
        }
        return true
    }

    func redeem(
        authViewModel: AuthViewModel,
        jellyfinService: JellyfinService,
        modelContext: ModelContext
    ) async -> RedeemResult {
        error = nil
        isWorking = true
        defer { isWorking = false }

        // 1. Seerr — required.
        authViewModel.serverURL = invite.seerrURL
        authViewModel.username = username
        authViewModel.password = password
        let seerrOK = await authViewModel.connectAndLogin(modelContext: modelContext)
        guard seerrOK else {
            error = authViewModel.error ?? "Couldn't sign in to Seerr. Check your details and try again."
            return .seerrFailed
        }

        // 2. Jellyfin — optional, soft-fail.
        guard let jellyfinURL = invite.jellyfinURL, invite.hasJellyfin else {
            return .success(jellyfinWarning: false)
        }

        let jfUser = useSameLoginForJellyfin ? username : jellyfinUsername
        let jfPass = useSameLoginForJellyfin ? password : jellyfinPassword

        do {
            let creds = try await JellyfinSetupFormViewModel.authenticate(
                serverURL: jellyfinURL,
                username: jfUser,
                password: jfPass
            )
            try await creds.save()
            await jellyfinService.reload()
            return .success(jellyfinWarning: false)
        } catch {
            // Playback couldn't be configured, but Seerr is set up — let the
            // user into the app and surface a non-blocking warning.
            return .success(jellyfinWarning: true)
        }
    }
}
