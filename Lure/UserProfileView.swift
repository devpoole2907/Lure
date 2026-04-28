import SwiftUI
import SwiftData

struct UserProfileView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser
    let onLogout: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LureServerProfile> { $0.isActive }) private var activeProfiles: [LureServerProfile]

    @State private var viewModel: UserProfileViewModel?
    @State private var apnsWorkerURL: String = ""
    @State private var cacheSize: String = ""
    @State private var showCacheClearedAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    profileContent(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Profile")
            .task {
                if viewModel == nil {
                    let vm = UserProfileViewModel(apiClient: apiClient)
                    viewModel = vm
                    await vm.load(user: currentUser)
                }
            }
            .toolbarTitleDisplayMode(.large)
        }
    }

    @ViewBuilder
    private func profileContent(vm: UserProfileViewModel) -> some View {
        List {
            if currentUser.isAdmin {
                Section {
                    AdminDashboardCard(requestCount: vm.requestCountSummary, apiClient: apiClient)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

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
                        if currentUser.isAdmin {
                            Text("Admin")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
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
                Section("Quota") {
                    if let movie = quota.movie {
                        quotaRow(label: "Movies", detail: movie)
                    }
                    if let tv = quota.tv {
                        quotaRow(label: "TV Shows", detail: tv)
                    }
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

            if currentUser.isAdmin {
                Section("Administration") {
                    NavigationLink {
                        AdminUserManagementView(apiClient: apiClient)
                    } label: {
                        Label("User Management", systemImage: "person.2.badge.gearshape")
                    }
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

            // Admin Setup
            if currentUser.isAdmin {
                Section("Push Notifications (Admin)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cloudflare Worker URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("https://lure-apns-worker.../push", text: $apnsWorkerURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { saveWorkerURL() }
                        
                        if !apnsWorkerURL.isEmpty {
                            let serverURL = activeProfiles.first?.serverURL ?? ""
                            let hash = NotificationManager.hashServerURL(serverURL)
                            let webhookURL = "\(apnsWorkerURL)?serverId=\(hash)"
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overseerr Webhook URL:")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(webhookURL)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .textSelection(.enabled)
                                Text("Paste this into Overseerr -> Settings -> Notifications -> Webhook")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .onAppear {
                    if let profile = activeProfiles.first, let url = profile.apnsWorkerURL {
                        apnsWorkerURL = url
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
        .scrollContentBackground(.hidden)
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

    private func saveWorkerURL() {
        if let profile = activeProfiles.first {
            let trimmed = apnsWorkerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.apnsWorkerURL = trimmed.isEmpty ? nil : trimmed
            try? modelContext.save()
            
            // Re-register local device
            if let workerUrl = profile.apnsWorkerURL {
                NotificationManager.shared.register(workerURL: workerUrl, serverURL: profile.serverURL, username: currentUser.displayName)
            }
        }
    }
}
