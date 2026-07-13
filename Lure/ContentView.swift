import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var servers: [LureServerProfile]
    @State private var authViewModel = AuthViewModel()
    @State private var isRestoringSession = true
    @State private var notificationCenter = InAppNotificationCenter()
    @State private var jellyfinService: JellyfinService
    @State private var playerCoordinator: PlayerCoordinator
    @State private var requestsCoordinator = RequestsCoordinator()
    @State private var router = LureRouter()
    @State private var showSignIn = false
    @State private var pendingInvite: LureInvite?
    @State private var inviteAwaitingConfirmation: LureInvite?
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    init() {
        let service = JellyfinService()
        _jellyfinService = State(wrappedValue: service)
        _playerCoordinator = State(wrappedValue: PlayerCoordinator(jellyfinService: service))
    }

    var body: some View {
        ZStack {
            Group {
                if isRestoringSession {
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Connecting...")
                            .foregroundStyle(.secondary)
                    }
                } else if !hasFinishedOnboarding {
                    SetupWizardView(authViewModel: authViewModel) { invite in
                        presentInvite(invite)
                    }
                    .environment(jellyfinService)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                } else if authViewModel.isLoggedIn, let client = authViewModel.apiClient, let user = authViewModel.currentUser {
                    LureTabView(
                        apiClient: client,
                        currentUser: user,
                        onLogout: {
                            // Drop straight back to onboarding (checked before the
                            // logged-in branch, so no expired-session flash), then
                            // tear down the session in the background. The swap is
                            // animated via `.animation(value: hasFinishedOnboarding)`.
                            hasFinishedOnboarding = false
                            router.reset()
                            Task {
                                await authViewModel.logout(profile: servers.first(where: \.isActive), modelContext: modelContext)
                                await jellyfinService.clearCredentials()
                            }
                        }
                    )
                    .playerPresentation()
                    .environment(notificationCenter)
                    .environment(jellyfinService)
                    .environment(playerCoordinator)
                    .environment(requestsCoordinator)
                    .environment(router)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    signInPrompt
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            // Drive the branch-swap animation off the value itself. `hasFinishedOnboarding`
            // is @AppStorage (UserDefaults-backed), so its change republishes outside any
            // synchronous `withAnimation` transaction — keying the animation here is what
            // actually animates sign out / reconfigure back to onboarding.
            // Suppressed while restoring so the initial session restore (which flips
            // isLoggedIn on launch) appears instantly instead of sliding in.
            .animation(isRestoringSession ? nil : .smooth, value: hasFinishedOnboarding)
            .animation(isRestoringSession ? nil : .smooth, value: authViewModel.isLoggedIn)
            .task {
                await restoreSession()
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .fullScreenCover(item: $pendingInvite) { invite in
                InviteRedemptionView(invite: invite, authViewModel: authViewModel) { jellyfinWarning in
                    pendingInvite = nil
                    if jellyfinWarning {
                        notificationCenter.show(
                            LureBannerItem(
                                title: "Playback not set up",
                                message: "You're signed in, but Jellyfin couldn't be connected. You can add it later in Settings.",
                                style: .info
                            )
                        )
                    }
                }
                .environment(jellyfinService)
            }
            .alert(
                "Connect to different servers?",
                isPresented: Binding(
                    get: { inviteAwaitingConfirmation != nil },
                    set: { if !$0 { inviteAwaitingConfirmation = nil } }
                ),
                presenting: inviteAwaitingConfirmation
            ) { invite in
                Button("Sign Out & Continue", role: .destructive) {
                    Task {
                        await authViewModel.logout(profile: servers.first(where: \.isActive), modelContext: modelContext)
                        await jellyfinService.clearCredentials()
                        router.reset()
                        inviteAwaitingConfirmation = nil
                        pendingInvite = invite
                    }
                }
                Button("Cancel", role: .cancel) {
                    inviteAwaitingConfirmation = nil
                }
            } message: { _ in
                Text("You're already signed in. Continuing will sign you out of your current servers and connect to the ones from this invite.")
            }

            // Banner overlay
            if let banner = notificationCenter.currentBanner {
                VStack {
                    LureNotificationBanner(item: banner) {
                        notificationCenter.dismiss()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Welcome Back")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your session has expired. Sign in again to pick up where you left off.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                hasFinishedOnboarding = false
            } label: {
                Label("Set up different servers", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .prominentBottomButton("Sign In") {
            showSignIn = true
        }
        .sheet(isPresented: $showSignIn) {
            SeerrSetupSheet(authViewModel: authViewModel) {
                showSignIn = false
            }
        }
    }

    private func restoreSession() async {
        async let jellyfinReload: Void = jellyfinService.reload()

        if let activeServer = servers.first(where: \.isActive) {
            let success = await authViewModel.restoreSession(from: activeServer)
            if success {
                activeServer.lastConnected = .now
                try? modelContext.save()
            }
        } else {
            await authViewModel.prepareSavedServerForLogin()
        }

        await jellyfinReload
        isRestoringSession = false
    }

    private func handleDeepLink(_ url: URL) {
        // Handle lure://invite?s=…&j=…&n=…&u=… (and legacy lure://connect?url=…).
        // Both resolve to a LureInvite and route into the one-shot redemption flow.
        if let invite = LureInvite.parse(url) {
            presentInvite(invite)
        } else {
            _ = router.route(url)
        }
    }

    /// Routes a parsed invite to redemption. If the user already finished setup,
    /// confirm first — redeeming an invite signs them out of their current servers.
    private func presentInvite(_ invite: LureInvite) {
        if hasFinishedOnboarding {
            inviteAwaitingConfirmation = invite
        } else {
            pendingInvite = invite
        }
    }
}
