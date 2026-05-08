import SwiftUI

enum MoreDestination: Hashable {
    case profile
    case userManagement
    case manageIssues
    case settings
}

struct MoreView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @State private var path = [MoreDestination]()
    @State private var totalUserCount: Int = 0
    @State private var totalIssueCount: Int = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: MoreDestination.profile) {
                        moreRow(icon: "person.crop.circle.fill", color: .blue,
                                title: "Profile", subtitle: "Your account details and preferences")
                    }
                }

                if canAccessAdminSection {
                    Section("Administration") {
                        if canManageUsers {
                            NavigationLink(value: MoreDestination.userManagement) {
                                moreRow(icon: "person.2.fill", color: .indigo,
                                        title: "User Management",
                                        subtitle: totalUserCount > 0 ? "\(totalUserCount) user\(totalUserCount == 1 ? "" : "s")" : "Manage users and permissions")
                            }
                        }

                        if canManageOrViewIssues {
                            NavigationLink(value: MoreDestination.manageIssues) {
                                moreRow(icon: "exclamationmark.bubble.fill", color: .orange,
                                        title: "Manage Issues",
                                        subtitle: totalIssueCount > 0 ? "\(totalIssueCount) issue\(totalIssueCount == 1 ? "" : "s")" : "Review and respond to reported issues")
                            }
                        }
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
            .navigationTitle("More")
#if os(iOS) || os(visionOS)
            .toolbarTitleDisplayMode(.large)
#endif
            .task { await loadAdminCounts() }
            .navigationDestination(for: MoreDestination.self) { destination in
                switch destination {
                case .profile:
                    UserProfileView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
                        .moreDestinationTitleStyle()
                case .userManagement:
                    AdminUserManagementView(apiClient: apiClient)
                        .moreDestinationTitleStyle()
                case .manageIssues:
                    AdminIssueListView(apiClient: apiClient)
                        .moreDestinationTitleStyle()
                case .settings:
                    SettingsView(apiClient: apiClient, currentUser: currentUser, onLogout: onLogout)
                        .moreDestinationTitleStyle()
                }
            }
        }
    }

    private func loadAdminCounts() async {
        guard canAccessAdminSection else { return }

        if canManageUsers {
            let userResponse = try? await apiClient.getUsers(take: 1, skip: 0)
            if let userResponse {
                totalUserCount = userResponse.pageInfo.results ?? 0
            }
        }

        if canManageOrViewIssues {
            let issueResponse = try? await apiClient.getIssues(take: 1, skip: 0)
            if let issueResponse {
                totalIssueCount = issueResponse.pageInfo.results ?? 0
            }
        }
    }

    private var canManageUsers: Bool {
        currentUser.canManageUsers
    }

    private var canManageOrViewIssues: Bool {
        currentUser.canManageIssues || currentUser.canViewIssues
    }

    private var canAccessAdminSection: Bool {
        canManageUsers || canManageOrViewIssues
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
