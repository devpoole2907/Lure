import SwiftUI

struct RequestListView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser?

    @State private var vm: RequestListViewModel
    @Environment(InAppNotificationCenter.self) private var notificationCenter

    init(apiClient: SeerrAPIClient, currentUser: SeerrUser?) {
        self.apiClient = apiClient
        self.currentUser = currentUser
        self._vm = State(initialValue: RequestListViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Requests")
                .navigationSubtitle(subtitleText)
#if os(iOS) || os(visionOS)
                .toolbarTitleDisplayMode(.large)
#endif
                .toolbar { toolbarContent }
                .refreshable { await vm.loadRequests() }
                .task { await vm.loadRequestsIfNeeded() }
                .animation(.default, value: vm.sortedRequests.map(\.id))
                .onChange(of: vm.actionSuccessMessage) { _, message in
                    if let message {
                        notificationCenter.show(LureBannerItem(
                            title: "Action Complete",
                            message: message,
                            style: .success
                        ))
                        vm.clearActionMessage()
                    }
                }
                .onChange(of: vm.error) { _, error in
                    if let error {
                        notificationCenter.show(LureBannerItem(
                            title: "Action Failed",
                            message: error,
                            style: .error
                        ))
                        vm.clearError()
                    }
                }
                .navigationDestination(for: MediaDestination.self) { dest in
                    if dest.mediaType == "movie" {
                        MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                    } else {
                        TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                    }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        List {
            if vm.isLoading && vm.sortedRequests.isEmpty {
                Section {
                    ProgressView("Loading requests...")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if vm.sortedRequests.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Requests", systemImage: "tray")
                    } description: {
                        Text("No requests match the current filter.")
                    }
                }
            } else {
                ForEach(vm.sortedRequests) { request in
                    requestRow(request)
                }
                if vm.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await vm.loadMore() }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Row

    @ViewBuilder
    private func requestRow(_ request: SeerrMediaRequest) -> some View {
        let resolvedTitle = vm.resolvedTitle(for: request)
        let resolvedPosterURL = vm.resolvedPosterURL(for: request)

        if let tmdbId = request.media?.tmdbId, let type = request.type {
            NavigationLink(value: MediaDestination(mediaType: type, tmdbId: tmdbId, title: resolvedTitle, posterURL: resolvedPosterURL)) {
                RequestItemContent(request: request, resolvedTitle: resolvedTitle, resolvedPosterURL: resolvedPosterURL)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                trailingActions(for: request)
            }
            .swipeActions(edge: .leading) {
                leadingActions(for: request)
            }
        } else {
            RequestItemContent(request: request, resolvedTitle: resolvedTitle, resolvedPosterURL: resolvedPosterURL)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    trailingActions(for: request)
                }
                .swipeActions(edge: .leading) {
                    leadingActions(for: request)
                }
        }
    }

    @ViewBuilder
    private func trailingActions(for request: SeerrMediaRequest) -> some View {
        if currentUser?.isAdmin == true {
            Button(role: .destructive) {
                Task { await vm.deleteRequest(request) }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            if request.requestStatus == .pending {
                Button {
                    Task { await vm.declineRequest(request) }
                } label: {
                    Label("Decline", systemImage: "xmark")
                }
                .tint(.orange)
            }
        }
    }

    @ViewBuilder
    private func leadingActions(for request: SeerrMediaRequest) -> some View {
        if currentUser?.isAdmin == true {
            if request.requestStatus == .pending {
                Button {
                    Task { await vm.approveRequest(request) }
                } label: {
                    Label("Approve", systemImage: "checkmark")
                }
                .tint(.green)
            }

            if request.requestStatus == .failed {
                Button {
                    Task { await vm.retryRequest(request) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(.blue)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Menu {
                ForEach(RequestFilter.allCases) { filter in
                    Button {
                        vm.selectedFilter = filter
                        Task { await vm.loadRequests() }
                    } label: {
                        if vm.selectedFilter == filter {
                            Label(filter.rawValue, systemImage: "checkmark")
                        } else {
                            Text(filter.rawValue)
                        }
                    }
                }
            } label: {
                Label("Filter", systemImage: filterIcon(for: vm.selectedFilter))
            }

            Menu {
                ForEach(RequestMediaType.allCases) { type in
                    Button {
                        vm.selectedMediaType = type
                        Task { await vm.loadRequests() }
                    } label: {
                        if vm.selectedMediaType == type {
                            Label(type.rawValue, systemImage: "checkmark")
                        } else {
                            Text(type.rawValue)
                        }
                    }
                }
            } label: {
                Label("Media Type", systemImage: mediaTypeIcon(for: vm.selectedMediaType))
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(RequestSortOrder.allCases) { order in
                    Button {
                        withAnimation { vm.sortOrder = order }
                    } label: {
                        if vm.sortOrder == order {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Text(order.rawValue)
                        }
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Helpers

    private var subtitleText: String {
        let count = vm.totalCount > 0 ? vm.totalCount : vm.sortedRequests.count
        return count == 1 ? "1 request" : "\(count) requests"
    }

    private func filterIcon(for filter: RequestFilter) -> String {
        switch filter {
        case .all:        "line.3.horizontal.decrease.circle"
        case .pending:    "clock"
        case .approved:   "checkmark.circle"
        case .processing: "arrow.down.circle"
        case .available:  "checkmark.circle.fill"
        case .failed:     "exclamationmark.circle"
        }
    }

    private func mediaTypeIcon(for type: RequestMediaType) -> String {
        switch type {
        case .all:   "square.stack.3d.up"
        case .movie: "film"
        case .tv:    "tv"
        }
    }
}

// MARK: - Row Content

private struct RequestItemContent: View {
    let request: SeerrMediaRequest
    let resolvedTitle: String
    let resolvedPosterURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: resolvedPosterURL, width: 50, height: 75, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(resolvedTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let type = request.type {
                        Text(type.capitalized)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(request.qualityLabel)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                    if let status = request.requestStatus {
                        Text("· \(status.displayName)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(status.color)
                    }
                }

                if let user = request.requestedBy {
                    Text("by \(user.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let seasons = request.seasons, !seasons.isEmpty {
                    Text("Seasons: \(seasons.map { String($0.seasonNumber) }.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let status = request.requestStatus {
                Image(systemName: statusIcon(for: status))
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.vertical, 2)
    }

    private func statusIcon(for status: LureConstants.RequestStatus) -> String {
        switch status {
        case .pending:   "clock"
        case .approved:  "checkmark.circle"
        case .declined:  "xmark.circle"
        case .failed:    "exclamationmark.circle"
        case .completed: "checkmark.circle.fill"
        }
    }
}
