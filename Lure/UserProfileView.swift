import SwiftUI

struct UserProfileView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @State private var viewModel: UserProfileViewModel?
    @State private var cacheSize: String = ""
    @State private var showCacheClearedAlert = false

    var body: some View {
        Group {
            if let vm = viewModel {
                profileContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .lureNavigationTitle("Profile")
        .task {
            if viewModel == nil {
                let vm = UserProfileViewModel(apiClient: apiClient)
                viewModel = vm
                await vm.load(user: currentUser)
            }
        }
#if os(iOS) || os(visionOS)
        .toolbarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    private func profileContent(vm: UserProfileViewModel) -> some View {
        List {
            // Avatar and name
            Section {
                HStack(spacing: 16) {
                    AsyncImage(url: currentUser.avatarURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle().fill(.quaternary)
                            .overlay(Image(systemName: "person.fill").font(.title2).foregroundStyle(.secondary))
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentUser.displayName)
                            .font(.headline)
                        if let email = currentUser.email {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            )

            // Quota
            if let quota = vm.quota {
                Section {
                    if let movie = quota.movie {
                        quotaRow(label: "Movies", detail: movie)
                    }
                    if let tv = quota.tv {
                        quotaRow(label: "TV Shows", detail: tv)
                    }
                } header: {
                    Text("Request Quota")
                } footer: {
                    Text("How many requests you can make within the rolling time window set by your server admin.")
                }
            }

            // Stats
            Section("Stats") {
                HStack {
                    Text("Total Requests")
                    Spacer()
                    Text("\(currentUser.requestCount ?? 0)")
                        .foregroundStyle(.secondary)
                }
            }

            // Recent requests
            if !vm.recentRequests.isEmpty {
                Section("Recent Requests") {
                    ForEach(vm.recentRequests) { request in
                        HStack(spacing: 10) {
                            PosterImage(url: request.media?.posterURL, width: 36, height: 54, cornerRadius: 4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(request.displayTitle)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let status = request.requestStatus {
                                    Text(status.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(status.color)
                                }
                            }
                        }
                    }
                }
            }

            // Storage
            Section("Storage") {
                HStack {
                    Label("Image Cache", systemImage: "photo.on.rectangle")
                    Spacer()
                    Text(cacheSize.isEmpty ? "Calculating..." : cacheSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    Task {
                        await LureImageCache.shared.clear()
                        await refreshCacheSize()
                        showCacheClearedAlert = true
                    }
                } label: {
                    Label("Clear Image Cache", systemImage: "trash")
                }
            }
            .onAppear { Task { await refreshCacheSize() } }
            .alert("Cache Cleared", isPresented: $showCacheClearedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The image cache has been cleared.")
            }

            // Logout
            Section {
                Button(role: .destructive, action: onLogout) {
                    Label("Sign Out", systemImage: "arrow.right.square")
                }
                .glassEffect(.regular.interactive(), in: Capsule())
            }
        }
        #if !os(tvOS)
        .scrollContentBackground(.hidden)
        #endif
        .lureGradientBackground(.purple)
    }

    @ViewBuilder
    private func quotaRow(label: String, detail: SeerrQuotaDetail) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let limit = detail.limit, let remaining = detail.remaining, let days = detail.days {
                Text("\(remaining)/\(limit) remaining (\(days)d)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Unlimited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func refreshCacheSize() async {
        let bytes = await LureImageCache.shared.cacheSizeInBytes()
        let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        await MainActor.run { cacheSize = formatted }
    }
}
