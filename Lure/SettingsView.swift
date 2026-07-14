import SwiftUI
import SwiftData

struct SettingsView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LureServerProfile> { $0.isActive }) private var activeProfiles: [LureServerProfile]

    var body: some View {
        List {
            Section("Server") {
                LabeledContent("URL", value: apiClient.baseURL)
            }

            Section("Account") {
                LabeledContent("Username", value: currentUser.displayName)
                if let email = currentUser.email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
            }

            Section("Playback") {
                NavigationLink {
                    JellyfinSetupView()
                } label: {
                    Label("Jellyfin Playback", systemImage: "play.tv")
                }
            }

            Section {
                Button(role: .destructive) {
                    onLogout()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("About") {
                LabeledContent("App", value: "Lure")
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    LabeledContent("Version", value: version)
                }
                NavigationLink {
                    LicensesView()
                } label: {
                    Label("Open Source Licenses", systemImage: "doc.text")
                }
            }
        }
#if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
#endif
        .lureNavigationTitle("Settings")
    }
}

#if DEBUG && os(iOS)
#Preview("Settings — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        SettingsView(
            apiClient: PreviewSupport.apiClient,
            currentUser: PreviewSupport.regularUser,
            onLogout: {}
        )
    }
    .environment(PreviewSupport.jellyfinService)
    .modelContainer(OnboardingPreviewSupport.modelContainer)
}
#endif

#if os(macOS)
@MainActor
@Observable
final class MacSettingsPresenter {
    var isPresented = false

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }
}

struct MacSettingsSheet: View {
    let apiClient: SeerrAPIClient?
    let currentUser: SeerrUser?
    let onLogout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: MacSettingsPane? = .account
    @State private var showLicenses = false

    var body: some View {
        NavigationSplitView {
            List(MacSettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            selectedPaneContent
                .navigationTitle((selection ?? .account).title)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: 820, height: 560)
        .sheet(isPresented: $showLicenses) {
            NavigationStack {
                LicensesView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showLicenses = false }
                        }
                    }
            }
            .frame(width: 620, height: 560)
        }
    }

    @ViewBuilder
    private var selectedPaneContent: some View {
        switch selection ?? .account {
        case .account:
            MacSettingsAccountPane(
                apiClient: apiClient,
                currentUser: currentUser,
                onLogout: {
                    dismiss()
                    onLogout()
                }
            )
        case .server:
            MacSettingsServerPane(apiClient: apiClient, currentUser: currentUser)
        case .playback:
            MacSettingsPlaybackPane()
        case .storage:
            MacSettingsStoragePane()
        case .about:
            MacSettingsAboutPane(showLicenses: { showLicenses = true })
        }
    }
}

private enum MacSettingsPane: String, CaseIterable, Identifiable {
    case account
    case server
    case playback
    case storage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .server: "Server"
        case .playback: "Playback"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .server: "server.rack"
        case .playback: "play.circle"
        case .storage: "externaldrive"
        case .about: "info.circle"
        }
    }
}

private struct MacSettingsAccountPane: View {
    let apiClient: SeerrAPIClient?
    let currentUser: SeerrUser?
    let onLogout: () -> Void

    var body: some View {
        MacSettingsForm {
            Section("Account") {
                LabeledContent("Name", value: currentUser?.displayName ?? "Not signed in")
                if let email = currentUser?.email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
                LabeledContent("Role", value: currentUser?.canManageRequests == true ? "Request manager" : "User")
                LabeledContent("Total Requests", value: "\(currentUser?.requestCount ?? 0)")
            }

            Section {
                LabeledContent("Seerr Server", value: apiClient?.baseURL ?? "Not configured")
                Button(role: .destructive, action: onLogout) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(currentUser == nil)
            } header: {
                Text("Session")
            } footer: {
                Text("Signing out returns Lure to setup and clears Jellyfin playback credentials on this device.")
            }
        }
    }
}

private struct MacSettingsServerPane: View {
    let apiClient: SeerrAPIClient?
    let currentUser: SeerrUser?

    var body: some View {
        MacSettingsForm {
            Section {
                LabeledContent("Server", value: apiClient?.baseURL ?? "Not configured")
                LabeledContent("Signed In As", value: currentUser?.displayName ?? "Not signed in")
            } header: {
                Text("Seerr")
            } footer: {
                Text("Lure uses Seerr for discovery, requests, approvals, and request history.")
            }

            Section("Changing Servers") {
                Text("To connect Lure to a different Seerr server, sign out and run setup again or open a new invite link.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacSettingsPlaybackPane: View {
    @Environment(JellyfinService.self) private var jellyfinService
    @State private var credentials: JellyfinCredentials?
    @State private var showJellyfinSetup = false

    var body: some View {
        MacSettingsForm {
            Section {
                LabeledContent("Status", value: credentials == nil ? "Not configured" : "Connected")
                if let credentials {
                    LabeledContent("Server", value: credentials.serverURL)
                    LabeledContent("Account", value: credentials.displayName)
                }
                Button(credentials == nil ? "Set Up Jellyfin..." : "Manage Jellyfin...") {
                    showJellyfinSetup = true
                }
            } header: {
                Text("Jellyfin")
            } footer: {
                Text("Jellyfin enables playback, resume progress, quality badges, and favorite syncing for media already in your library.")
            }
        }
        .task {
            credentials = await JellyfinCredentials.load()
        }
        .sheet(isPresented: $showJellyfinSetup, onDismiss: {
            Task { credentials = await JellyfinCredentials.load() }
        }) {
            NavigationStack {
                JellyfinSetupView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showJellyfinSetup = false }
                        }
                    }
            }
            .environment(jellyfinService)
            .frame(width: 520, height: 520)
        }
    }
}

private struct MacSettingsStoragePane: View {
    @State private var cacheSize = ""
    @State private var isClearingCache = false
    @State private var cacheMessage: String?

    var body: some View {
        MacSettingsForm {
            Section {
                LabeledContent("Image Cache", value: cacheSize.isEmpty ? "Calculating..." : cacheSize)
                Button(role: .destructive) {
                    Task { await clearImageCache() }
                } label: {
                    Label(isClearingCache ? "Clearing..." : "Clear Image Cache", systemImage: "trash")
                }
                .disabled(isClearingCache)
                if let cacheMessage {
                    Text(cacheMessage)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Images")
            } footer: {
                Text("Cached artwork makes posters, backdrops, and profile images load faster. Clearing it does not remove account data.")
            }
        }
        .task { await refreshCacheSize() }
    }

    @MainActor
    private func refreshCacheSize() async {
        let bytes = await LureImageCache.shared.cacheSizeInBytes()
        cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor
    private func clearImageCache() async {
        isClearingCache = true
        cacheMessage = nil
        await LureImageCache.shared.clear()
        await refreshCacheSize()
        cacheMessage = "Image cache cleared."
        isClearingCache = false
    }
}

private struct MacSettingsAboutPane: View {
    let showLicenses: () -> Void

    var body: some View {
        MacSettingsForm {
            Section("Application") {
                LabeledContent("Name", value: "Lure")
                LabeledContent("Version", value: appVersion)
                if let buildNumber {
                    LabeledContent("Build", value: buildNumber)
                }
            }

            Section("Legal") {
                Button {
                    showLicenses()
                } label: {
                    Label("Open Source Licenses", systemImage: "doc.text")
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }
}

private struct MacSettingsForm<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }
}

#Preview("Mac Settings") {
    MacSettingsSheet(
        apiClient: PreviewSupport.apiClient,
        currentUser: PreviewSupport.regularUser,
        onLogout: {}
    )
    .environment(PreviewSupport.jellyfinService)
}
#endif
