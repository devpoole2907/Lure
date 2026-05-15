import SwiftUI
import SwiftData

struct SetupWizardView: View {
    @Bindable var authViewModel: AuthViewModel
    @State private var welcomePath: [WelcomeStep] = []
    
    var body: some View {
        NavigationStack(path: $welcomePath) {
            welcomeIntroScreen
                .navigationDestination(for: WelcomeStep.self) { step in
                    switch step {
                    case .services:
                        ServiceSelectionScreen(authViewModel: authViewModel, welcomePath: $welcomePath)
                    }
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
                featureRow(icon: "arrow.down.circle.fill", color: .blue,
                           title: "Seerr",
                           description: "Discover and request movies and TV shows")
                featureRow(icon: "play.tv.fill", color: .purple,
                           title: "Jellyfin",
                           description: "Watch your media library directly")
            }
            .padding(.horizontal, 8)

            NavigationLink(value: WelcomeStep.services) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .padding(32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum WelcomeStep: Hashable {
    case services
}

private struct ServiceSelectionScreen: View {
    @Environment(JellyfinService.self) private var jellyfinService
    @Bindable var authViewModel: AuthViewModel
    @Binding var welcomePath: [WelcomeStep]
    @State private var showSeerrSetup = false
    @State private var showJellyfinSetup = false
    @AppStorage("hasFinishedOnboarding") private var hasFinishedOnboarding = false

    var isSeerrConfigured: Bool {
        authViewModel.isLoggedIn
    }

    var hasJellyfinConfigured: Bool {
        jellyfinService.hasCredentials
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Choose Your Services")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Set up the services you want to use, then continue into the app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                setupRow(
                    icon: "arrow.down.circle.fill",
                    color: .blue,
                    title: "Seerr",
                    description: "Required — discover and request media",
                    isConfigured: isSeerrConfigured
                ) {
                    showSeerrSetup = true
                }

                setupRow(
                    icon: "play.tv.fill",
                    color: .purple,
                    title: "Jellyfin",
                    description: "Optional — adds in-app playback",
                    isConfigured: hasJellyfinConfigured
                ) {
                    showJellyfinSetup = true
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button("Go") {
                    hasFinishedOnboarding = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isSeerrConfigured)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular.interactive(), in: Capsule())

                Button("Back") {
                    welcomePath.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Choose Services")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showSeerrSetup) {
            LoginView(authViewModel: authViewModel, isModal: true) {
                showSeerrSetup = false
            }
        }
        .sheet(isPresented: $showJellyfinSetup) {
            NavigationStack {
                JellyfinSetupView()
                    .environment(jellyfinService)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showJellyfinSetup = false
                            }
                        }
                    }
            }
        }
    }

    private func setupRow(
        icon: String,
        color: Color,
        title: String,
        description: String,
        isConfigured: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
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
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
