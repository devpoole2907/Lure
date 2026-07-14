import SwiftUI

struct JellyfinSetupView: View {
    @Environment(JellyfinService.self) private var jellyfinService
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var credentials: JellyfinCredentials?
    @State private var showDisconnectConfirm = false
#if DEBUG
    private let loadsSavedCredentials: Bool

    init(loadsSavedCredentials: Bool = true) {
        self.loadsSavedCredentials = loadsSavedCredentials
    }
#endif

    var body: some View {
        List {
            if let credentials {
                Section("Connected Account") {
                    LabeledContent("Server", value: credentials.serverURL)
                    LabeledContent("Account", value: credentials.displayName)
                }
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Remove Account", systemImage: "trash")
                    }
                }
            } else {
                Section("Server URL") {
                    TextField("https://jellyfin.example.com", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button {
                        Task { await authenticate() }
                    } label: {
                        HStack {
                            if isAuthenticating {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Connecting…")
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || isAuthenticating)
                }
            }
        }
        .lureNavigationTitle("Jellyfin Playback")
#if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
#endif
        .task {
            #if DEBUG
            if loadsSavedCredentials {
                credentials = await JellyfinCredentials.load()
            }
            #else
            credentials = await JellyfinCredentials.load()
            #endif
        }
        .confirmationDialog(
            "Remove Jellyfin Account",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                Task {
                    await jellyfinService.clearCredentials()
                    credentials = nil
                }
            }
        } message: {
            Text("You will need to sign in again to watch content.")
        }
    }

    private func authenticate() async {
        errorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url = String(url.dropLast()) }

        do {
            let creds = try await JellyfinAPIClient.authenticate(
                serverURL: url,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            try await creds.save()
            credentials = creds
            await jellyfinService.reload()
        } catch JellyfinError.unauthorized {
            errorMessage = "Incorrect username or password."
        } catch JellyfinError.badURL {
            errorMessage = "Invalid server URL."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG && os(iOS)
#Preview("Jellyfin Playback Setup — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        JellyfinSetupView(loadsSavedCredentials: false)
    }
    .environment(PreviewSupport.jellyfinService)
}
#endif
