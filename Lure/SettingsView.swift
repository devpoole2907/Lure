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
            }
        }
#if os(iOS) || os(visionOS)
        .listStyle(.insetGrouped)
#endif
        .navigationTitle("Settings")
    }
}
