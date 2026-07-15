import SwiftUI
#if DEBUG
import SwiftData
#endif

enum MoreDestination: Hashable {
    case profile
    case settings
}

struct MoreView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(LureRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.morePath) {
            List {
                Section {
                    NavigationLink(value: MoreDestination.profile) {
                        moreRow(icon: "person.crop.circle.fill", color: .blue,
                                title: "Profile", subtitle: "Your account details and preferences")
                    }
                }

                Section {
                    NavigationLink(value: MoreDestination.settings) {
                        moreRow(icon: "gearshape.fill", color: .secondary,
                                title: "Settings", subtitle: "App and server configuration")
                    }
                }
            }
#if os(iOS) || os(visionOS)
            .listStyle(.insetGrouped)
#endif
            .lureNavigationTitle("More")
#if os(iOS) || os(visionOS)
            .toolbarTitleDisplayMode(.large)
#endif
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .profile:
                    UserProfileSheet(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
                        .moreDestinationTitleStyle()
                case .settings:
                    SettingsView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
                        .moreDestinationTitleStyle()
                }
            }
        }
    }

    private func moreRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension View {
    @ViewBuilder
    func moreDestinationTitleStyle() -> some View {
#if os(iOS) || os(visionOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

#if DEBUG && os(iOS)
#Preview("More — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    MoreView(
        apiClient: PreviewSupport.apiClient,
        currentUser: PreviewSupport.regularUser,
        onLogout: {}
    )
    .environment(PreviewSupport.router(tab: .more))
    .environment(PreviewSupport.jellyfinService)
    .modelContainer(OnboardingPreviewSupport.modelContainer)
}
#endif
