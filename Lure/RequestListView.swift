import SwiftUI
import SwiftData

struct RequestListView: View {
    let apiClient: SeerrAPIClient
    let currentUser: SeerrUser?

    @State private var vm: RequestListViewModel
    @State private var searchText = ""
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    init(apiClient: SeerrAPIClient, currentUser: SeerrUser?) {
        self.apiClient = apiClient
        self.currentUser = currentUser
        self._vm = State(initialValue: RequestListViewModel(apiClient: apiClient))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Requests")
                #if os(macOS)
                .navigationSubtitle(subtitleText)
                #endif
#if os(iOS) || os(visionOS)
                .toolbarTitleDisplayMode(.large)
#endif
                .toolbar { toolbarContent }
                #if os(iOS) || os(visionOS)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Title, requester, status"
                )
                #else
                .searchable(text: $searchText, prompt: "Title, requester, status")
                #endif
                .autocorrectionDisabled()
                .refreshable { await vm.loadRequests() }
                .task {
                    vm.setModelContext(modelContext)
                    await vm.loadRequestsIfNeeded()
                }
                .animation(.default, value: displayedRequests.map(\.id))
                .onChange(of: requestsCoordinator.lastChange) { _, _ in
                    Task { await vm.loadRequests() }
                }
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
                        MovieDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
                    } else {
                        TVDetailView(tmdbId: dest.tmdbId, apiClient: apiClient, jellyfinService: jellyfinService, initialTitle: dest.title, initialPosterURL: dest.posterURL)
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
            } else if displayedRequests.isEmpty {
                Section {
                    if isSearchingRequests {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView {
                            Label("No Requests", systemImage: "tray")
                        } description: {
                            Text("No requests match the current filter.")
                        }
                    }
                }
            } else {
                ForEach(displayedRequests) { request in
                    requestRow(request)
                }
                if vm.hasMore && !isSearchingRequests {
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
            #if !os(tvOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                trailingActions(for: request)
            }
            .swipeActions(edge: .leading) {
                leadingActions(for: request)
            }
            #endif
        } else {
            RequestItemContent(request: request, resolvedTitle: resolvedTitle, resolvedPosterURL: resolvedPosterURL)
                #if !os(tvOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    trailingActions(for: request)
                }
                .swipeActions(edge: .leading) {
                    leadingActions(for: request)
                }
                #endif
        }
    }

    @ViewBuilder
    private func trailingActions(for request: SeerrMediaRequest) -> some View {
        if canModerateRequests {
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

            Button {
                if let url = URL(string: "trawl://seerr-issue") {
                    openExternalURL(url)
                }
            } label: {
                Label("Trawl", systemImage: "arrow.up.forward.app")
            }
            .tint(.purple)
        }
    }

    @ViewBuilder
    private func leadingActions(for request: SeerrMediaRequest) -> some View {
        if canModerateRequests {
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
        if isSearchingRequests {
            let count = displayedRequests.count
            return count == 1 ? "1 match" : "\(count) matches"
        }
        let count = vm.totalCount > 0 ? vm.totalCount : vm.sortedRequests.count
        return count == 1 ? "1 request" : "\(count) requests"
    }

    private var isSearchingRequests: Bool {
        !normalizedSearchText.isEmpty
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedRequests: [SeerrMediaRequest] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return vm.sortedRequests }

        return vm.sortedRequests.filter { request in
            requestSearchTokens(for: request).contains { token in
                token.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private func requestSearchTokens(for request: SeerrMediaRequest) -> [String] {
        var tokens = [
            vm.resolvedTitle(for: request),
            request.qualityLabel
        ]

        if let type = request.type {
            tokens.append(type)
            tokens.append(type.capitalized)
        }
        if let user = request.requestedBy {
            tokens.append(user.displayName)
            if let email = user.email {
                tokens.append(email)
            }
        }
        if let requestStatus = request.requestStatus {
            tokens.append(requestStatus.displayName)
        }
        if let mediaStatus = request.media?.mediaStatus {
            tokens.append(mediaStatus.displayName)
        }

        return tokens
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

    private var canModerateRequests: Bool {
        currentUser?.canManageRequests == true
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
                    if let status = effectiveStatus {
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

            if let status = effectiveStatus {
                Image(systemName: status.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.color)
            }
        }
        .padding(.vertical, 2)
    }

    /// Promotes the request's media status (e.g. Processing, Available) over
    /// the bare RequestStatus once Radarr/Sonarr has picked the request up.
    /// Only kicks in for approved requests so we don't override Pending /
    /// Declined / Failed states.
    private var effectiveStatus: RequestRowStatus? {
        if request.requestStatus == .approved,
           let mediaStatus = request.media?.mediaStatus,
           mediaStatus.isUserVisible,
           mediaStatus != .pending {
            return .media(mediaStatus)
        }
        if let status = request.requestStatus {
            return .request(status)
        }
        return nil
    }

    private enum RequestRowStatus {
        case request(LureConstants.RequestStatus)
        case media(LureConstants.MediaStatus)

        var displayName: String {
            switch self {
            case .request(let status): status.displayName
            case .media(let status): status.displayName
            }
        }

        var color: Color {
            switch self {
            case .request(let status): status.color
            case .media(let status): status.color
            }
        }

        var systemImage: String {
            switch self {
            case .request(let status):
                switch status {
                case .pending:   "clock"
                case .approved:  "checkmark.circle"
                case .declined:  "xmark.circle"
                case .failed:    "exclamationmark.circle"
                case .completed: "checkmark.circle.fill"
                }
            case .media(let status):
                status.systemImage
            }
        }
    }
}
