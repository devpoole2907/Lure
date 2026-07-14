#if os(macOS)
import SwiftUI

struct MacUserProfileSheet: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: UserProfileViewModel

    init(apiClient: SeerrAPIClient, currentUser: SeerrUser, onLogout: @escaping () -> Void) {
        self.apiClient = apiClient
        self.currentUser = currentUser
        self.onLogout = onLogout
        self._viewModel = State(initialValue: UserProfileViewModel(apiClient: apiClient))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Profile")
                    .font(.title2.bold())
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                Form {
                    Section {
                        HStack(spacing: 14) {
                            AsyncImage(url: currentUser.avatarURL) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(.quaternary)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(currentUser.displayName)
                                    .font(.headline)

                                if let accountName {
                                    Text(accountName)
                                        .foregroundStyle(.secondary)
                                }

                                if let email = currentUser.email, !email.isEmpty {
                                    Text(email)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Text(currentUser.permissionLevelLabel)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    Section("Requests") {
                        LabeledContent("Total Requests", value: "\(currentUser.requestCount ?? 0)")

                        if let movieQuota = viewModel.quota?.movie {
                            LabeledContent("Movie Quota", value: quotaDescription(movieQuota))
                        }

                        if let televisionQuota = viewModel.quota?.tv {
                            LabeledContent("TV Show Quota", value: quotaDescription(televisionQuota))
                        }

                        if viewModel.isLoading {
                            HStack {
                                Text("Loading request details…")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        } else if let error = viewModel.error {
                            Label("Request details unavailable", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .help(error)
                        }
                    }

                    if !viewModel.recentRequests.isEmpty {
                        Section("Recent Requests") {
                            ForEach(viewModel.recentRequests) { request in
                                HStack(spacing: 10) {
                                    PosterImage(
                                        url: request.media?.posterURL,
                                        width: 32,
                                        height: 48,
                                        cornerRadius: 4
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(request.displayTitle)
                                            .lineLimit(1)

                                        if let status = request.requestStatus {
                                            Text(status.displayName)
                                                .font(.caption)
                                                .foregroundStyle(status.color)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }

            Divider()

            HStack {
                Button(role: .destructive, action: signOut) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }

                Spacer()

                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 680)
        .background(.regularMaterial)
        .task {
            await viewModel.load(user: currentUser)
        }
    }

    private var accountName: String? {
        guard let username = currentUser.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              username.caseInsensitiveCompare(currentUser.displayName) != .orderedSame else {
            return nil
        }
        return "@\(username)"
    }

    private func quotaDescription(_ detail: SeerrQuotaDetail) -> String {
        guard let limit = detail.limit,
              let remaining = detail.remaining,
              let days = detail.days else {
            return "Unlimited"
        }
        return "\(remaining) of \(limit) remaining · \(days)-day window"
    }

    private func signOut() {
        dismiss()
        onLogout()
    }
}
#endif
