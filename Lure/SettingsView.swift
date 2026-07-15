import SwiftUI
import SwiftData

// MARK: - Shared settings sections
//
// Settings is organized identically on every platform — Servers (Seerr +
// Jellyfin), Storage, About — with account details and sign-out living in
// the profile screen instead. macOS hosts these sections in its paned
// settings sheet; other platforms stack them in a single pushed list.

private struct SettingsSeerrSection: View {
    let apiClient: SeerrAPIClient?
    let currentUser: SeerrUser?

    var body: some View {
        Section {
            LabeledContent("Server", value: apiClient?.baseURL ?? "Not configured")
            LabeledContent("Signed In As", value: currentUser?.displayName ?? "Not signed in")
        } header: {
            Text("Seerr")
        } footer: {
            Text("Lure uses Seerr for discovery, requests, approvals, and request history. To connect to a different Seerr server, sign out and run setup again or open a new invite link.")
        }
    }
}

private struct SettingsJellyfinSection: View {
    @Environment(JellyfinService.self) private var jellyfinService
    @State private var credentials: JellyfinCredentials?
    #if os(macOS)
    @State private var showJellyfinSetup = false
    #endif

    var body: some View {
        Section {
            LabeledContent("Status", value: credentials == nil ? "Not configured" : "Connected")
            if let credentials {
                LabeledContent("Server", value: credentials.serverURL)
                LabeledContent("Account", value: credentials.displayName)
            }
            #if os(macOS)
            Button(credentials == nil ? "Set Up Jellyfin..." : "Manage Jellyfin...") {
                showJellyfinSetup = true
            }
            #else
            NavigationLink {
                JellyfinSetupView()
            } label: {
                Label(credentials == nil ? "Set Up Jellyfin" : "Manage Jellyfin", systemImage: "play.tv")
            }
            #endif
        } header: {
            Text("Jellyfin")
        } footer: {
            Text("Jellyfin enables playback, resume progress, quality badges, and favorite syncing for media already in your library.")
        }
        .task {
            credentials = await JellyfinCredentials.load()
        }
        #if os(macOS)
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
        #endif
    }
}

private struct SettingsStorageSection: View {
    @State private var cacheSize = ""
    @State private var isClearingCache = false
    @State private var cacheMessage: String?

    var body: some View {
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

/// On macOS the licenses open in a sheet driven by the settings window, so
/// the pane passes `showLicenses`; elsewhere it's nil and a NavigationLink
/// pushes them.
private struct SettingsAboutSection: View {
    var showLicenses: (() -> Void)? = nil

    var body: some View {
        Section("Application") {
            LabeledContent("Name", value: "Lure")
            LabeledContent("Version", value: appVersion)
            if let buildNumber {
                LabeledContent("Build", value: buildNumber)
            }
        }

        Section("Legal") {
            if let showLicenses {
                Button {
                    showLicenses()
                } label: {
                    Label("Open Source Licenses", systemImage: "doc.text")
                }
            } else {
                NavigationLink {
                    LicensesView()
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

// MARK: - iOS/iPadOS/tvOS settings (pushed from the More tab)

struct SettingsView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    var body: some View {
        List {
            SettingsSeerrSection(apiClient: apiClient, currentUser: currentUser)
            SettingsJellyfinSection()
            SettingsStorageSection()
            SettingsAboutSection()
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

// MARK: - macOS settings sheet

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
    @State private var selection: MacSettingsPane? = .servers
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
                .navigationTitle((selection ?? .servers).title)
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
        switch selection ?? .servers {
        case .servers:
            MacSettingsForm {
                SettingsSeerrSection(apiClient: apiClient, currentUser: currentUser)
                SettingsJellyfinSection()
            }
        case .storage:
            MacSettingsForm {
                SettingsStorageSection()
            }
        case .about:
            MacSettingsForm {
                SettingsAboutSection(showLicenses: { showLicenses = true })
            }
        }
    }
}

private enum MacSettingsPane: String, CaseIterable, Identifiable {
    case servers
    case storage
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .servers: "Servers"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .servers: "server.rack"
        case .storage: "externaldrive"
        case .about: "info.circle"
        }
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
