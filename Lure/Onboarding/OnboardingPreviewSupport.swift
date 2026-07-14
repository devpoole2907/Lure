import SwiftData

#if DEBUG
enum OnboardingPreviewSupport {
    @MainActor
    static var modelContainer: ModelContainer {
        let schema = Schema([
            LureServerProfile.self,
            CachedLibraryItem.self,
            CachedRequestItem.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    static var invite: LureInvite {
        LureInvite(
            seerrURL: "https://requests.example.com",
            jellyfinURL: "https://watch.example.com",
            displayName: "Example Family",
            username: "viewer"
        )
    }

    @MainActor
    static func authViewModel() -> AuthViewModel {
        let viewModel = AuthViewModel()
        viewModel.serverURL = ""
        viewModel.username = ""
        viewModel.password = ""
        viewModel.error = nil
        return viewModel
    }
}
#endif
