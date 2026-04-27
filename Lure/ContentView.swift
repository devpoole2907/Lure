import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var servers: [LureServerProfile]
    @State private var authViewModel = AuthViewModel()
    @State private var isRestoringSession = true
    @State private var notificationCenter = InAppNotificationCenter()

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
                } else if authViewModel.isLoggedIn, let client = authViewModel.apiClient, let user = authViewModel.currentUser {
                    LureTabView(
                        apiClient: client,
                        currentUser: user,
                        onLogout: {
                            Task {
                                await authViewModel.logout(profile: servers.first(where: \.isActive), modelContext: modelContext)
                            }
                        }
                    )
                    .environment(notificationCenter)
                } else {
                    LoginView(authViewModel: authViewModel)
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

    private func restoreSession() async {
        if let activeServer = servers.first(where: \.isActive) {
            let success = await authViewModel.restoreSession(from: activeServer)
            if success {
                activeServer.lastConnected = .now
                try? modelContext.save()
            }
        }
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