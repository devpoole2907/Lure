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
    @State private var showSignIn = false
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
                    SetupWizardView(authViewModel: authViewModel)
                        .environment(jellyfinService)
                } else if authViewModel.isLoggedIn, let client = authViewModel.apiClient, let user = authViewModel.currentUser {
                    LureTabView(
                        apiClient: client,
                        currentUser: user,
                        onLogout: {
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
                } else {
                    signInPrompt
                }
            }
            .task {
                await restoreSession()
            }
            .onOpenURL { url in
                handleDeepLink(url)
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
        ContentUnavailableView {
            Label("Sign In", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("Your Seerr session has expired. Sign in again to continue.")
        } actions: {
            Button("Sign In") {
                showSignIn = true
            }
            .buttonStyle(.borderedProminent)

            Button("Reconfigure Services") {
                hasFinishedOnboarding = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showSignIn) {
            LoginView(authViewModel: authViewModel, isModal: true) {
                showSignIn = false
            }
            .environment(jellyfinService)
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
        // Handle lure://connect?url=http://192.168.1.50:5055
        guard url.scheme == "lure", url.host == "connect" else { return }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let serverURL = components.queryItems?.first(where: { $0.name == "url" })?.value {
            authViewModel.serverURL = serverURL
        }
    }
}
