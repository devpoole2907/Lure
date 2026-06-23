import SwiftUI

struct MovieDetailView: View {
    let tmdbId: Int
    let apiClient: SeerrAPIClient
    let initialTitle: String?
    let initialPosterURL: URL?
    let currentUser: SeerrUser?
    let onRequestUpdated: ((SeerrMediaRequest) -> Void)?

    @State private var vm: MovieDetailViewModel
    @State private var showRequestOptions = false
    @State private var showReportSheet = false
    @State private var selectedCastMember: SeerrCastMember?
    @State private var isModeratingRequest = false
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(PlayerCoordinator.self) private var playerCoordinator
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    init(
        tmdbId: Int,
        apiClient: SeerrAPIClient,
        jellyfinService: JellyfinService,
        initialTitle: String? = nil,
        initialPosterURL: URL? = nil,
        currentUser: SeerrUser? = nil,
        onRequestUpdated: ((SeerrMediaRequest) -> Void)? = nil
    ) {
        self.tmdbId = tmdbId
        self.apiClient = apiClient
        self.initialTitle = initialTitle
        self.initialPosterURL = initialPosterURL
        self.currentUser = currentUser
        self.onRequestUpdated = onRequestUpdated
        self._vm = State(initialValue: MovieDetailViewModel(tmdbId: tmdbId, apiClient: apiClient, jellyfinService: jellyfinService))
    }

    var body: some View {
        Group {
            if let movie = vm.movie {
                scrollContent(movie)
                    .background { artBackground(url: displayPosterURL(for: movie)) }
                    .transition(.opacity)
            } else if vm.isLoading {
                loadingContent
                    .transition(.opacity)
            } else {
                ContentUnavailableView("Movie Not Found", systemImage: "film")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.movie?.id)
        .animation(.easeInOut(duration: 0.25), value: vm.ratings != nil)
        .animation(.easeInOut(duration: 0.25), value: vm.recommendations.count)
        .navigationTitle(vm.movie?.displayTitle ?? initialTitle ?? "Movie")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showReportSheet = true
                    } label: {
                        Label("Report an Issue", systemImage: "exclamationmark.triangle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportIssueSheet(
                mediaId: vm.movie?.mediaInfo?.id,
                mediaTitle: vm.movie?.displayTitle ?? initialTitle,
                apiClient: apiClient
            )
        }
        .errorAlert(item: Binding(
            get: { vm.error.map { ErrorAlertItem(title: "Error", message: $0) } },
            set: { _ in vm.error = nil }
        ))
        .sheet(item: $selectedCastMember) { member in
            CastPersonSheet(
                personId: member.id,
                fallbackName: member.name,
                fallbackProfileURL: member.profileURL,
                apiClient: apiClient
            )
        }
        .alert("Request Movie", isPresented: $showRequestOptions) {
            Button("Request HD") {
                Task { await vm.requestMovie(is4k: false) }
            }
            .disabled(vm.movie?.mediaInfo?.hasHDRequest == true || vm.isRequesting)
            Button("Request 4K") {
                Task { await vm.requestMovie(is4k: true) }
            }
            .disabled(vm.movie?.mediaInfo?.has4KRequest == true || vm.isRequesting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose the quality for this request.")
        }
        .task { await vm.load() }
        .onChange(of: vm.requestSuccess) { _, success in
            if success {
                let title = vm.movie?.displayTitle ?? initialTitle ?? "your request"
                notificationCenter.show(LureBannerItem(
                    title: "Request Submitted",
                    message: "We'll let you know when \(title) is ready to watch.",
                    style: .success
                ))
                requestsCoordinator.markStale()
            }
        }
        .onChange(of: vm.error) { _, error in
            if let error {
                notificationCenter.show(LureBannerItem(
                    title: "Request Failed",
                    message: error,
                    style: .error
                ))
            }
        }
    }

    // MARK: - Watch

    private func watchMovie(_ movie: SeerrMovieDetail) {
        guard let itemId = vm.playbackAvailability.playableItemId else { return }
        playerCoordinator.present(
            itemId: itemId,
            title: movie.displayTitle,
            tmdbId: tmdbId,
            releaseYear: movie.year.flatMap(Int.init),
            mediaType: "movie"
        )
    }

    // MARK: - Background

    @ViewBuilder
    private var loadingContent: some View {
        if let initialPosterURL {
            VStack(spacing: 18) {
                PosterImage(url: initialPosterURL, width: 160, height: 240, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                ProgressView("Loading...")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { artBackground(url: initialPosterURL) }
        } else {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func artBackground(url: URL?) -> some View {
        AsyncImage(
            url: url,
            transaction: Transaction(animation: .easeInOut(duration: 0.3))
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            case .failure, .empty:
                Rectangle().fill(Color.indigo.opacity(0.4))
            @unknown default:
                Rectangle().fill(Color.indigo.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(1.4)
        .blur(radius: 60)
        .saturation(1.6)
        .overlay(Color.black.opacity(0.55))
        .ignoresSafeArea()
    }

    // MARK: - Scroll Content

    private func scrollContent(_ movie: SeerrMovieDetail) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                heroSection(movie)
                cardsSection(movie)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await vm.load() }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Hero

    private func heroSection(_ movie: SeerrMovieDetail) -> some View {
        VStack(spacing: 14) {
            PosterImage(url: displayPosterURL(for: movie), width: 160, height: 240, cornerRadius: 16)
                .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

            VStack(spacing: 6) {
                Text(movie.displayTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let year = movie.year { Text(year) }
                    if let runtime = movie.runtime, runtime > 0 {
                        if movie.year != nil { Text("·") }
                        Text("\(runtime)m")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

                DetailBadgeSection(badges: movieBadges(movie))

                if let genres = movie.genres?.compactMap(\.name), !genres.isEmpty {
                    DetailGenreChips(genres: genres)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    private func displayPosterURL(for movie: SeerrMovieDetail) -> URL? {
        initialPosterURL ?? movie.posterURL
    }

    /// Content rating + availability status + (when in the Jellyfin library) the
    /// file's quality, combined into one colored, icon-prefixed badge row.
    private func movieBadges(_ movie: SeerrMovieDetail) -> [DetailBadge] {
        var badges: [DetailBadge] = []
        if let cert = movie.certificationText {
            badges.append(DetailBadge(icon: "shield", label: cert, color: .yellow))
        }
        if let status = movie.mediaInfo?.mediaStatus, status.isUserVisible {
            badges.append(DetailBadge(icon: status.systemImage, label: status.displayName, color: status.color))
        }
        if let quality = vm.mediaQuality {
            for badge in quality.badges {
                badges.append(DetailBadge(icon: badge.icon, label: badge.label, color: badge.tint))
            }
        }
        return badges
    }

    // MARK: - Cards Section

    @ViewBuilder
    private func cardsSection(_ movie: SeerrMovieDetail) -> some View {
        requestCard(movie)

        ratingsCard(vm.ratings, movie: movie)
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        if let overview = movie.overview, !overview.isEmpty {
            overviewCard(overview)
        }

        statsCard(movie)

        if let providers = movie.usWatchProviders, let named = namedProviders(providers) {
            watchProvidersCard(providers, named: named)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if let cast = movie.credits?.cast, !cast.isEmpty {
            castCard(Array(cast.prefix(20)))
        }

        if let url = movie.trailerURL {
            trailerCard(url)
        }

        let infoRows = movieInfoRows(movie)
        if !infoRows.isEmpty {
            rowsCard(header: "Info", icon: "info.circle", rows: infoRows)
        }
        if !vm.recommendations.isEmpty {
            MediaSliderView(title: "You Might Also Like", icon: "sparkles", items: vm.recommendations, apiClient: apiClient)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Request Card

    @ViewBuilder
    private func requestCard(_ movie: SeerrMovieDetail) -> some View {
        if movie.mediaInfo?.isAvailable == true {
            VStack(alignment: .leading, spacing: 10) {
                if vm.playbackAvailability.playableItemId != nil {
                    // In the Jellyfin library — the Watch button already conveys
                    // availability, so the separate "Available in Seerr" pill is redundant.
                    playbackButton(movie)
                } else {
                    HStack(spacing: 12) {
                        availabilityLabel("Available in Seerr", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.tint(Color.green.opacity(0.2)), in: RoundedRectangle(cornerRadius: 16))

                        playbackButton(movie)
                    }
                }

                if let message = playbackAvailabilityMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(message)
                        Spacer()
                        Button("Refresh") {
                            Task { await vm.refreshPlaybackAvailability() }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } else if let failedRequest = movie.mediaInfo?.mostRecentFailedRequest {
            failedRequestCard(failedRequest, mediaTitle: movie.displayTitle)
        } else {
            let pendingRequest = pendingRequest(for: movie)

            HStack(spacing: 12) {
                Button {
                    showRequestOptions = true
                } label: {
                    Group {
                        if vm.isRequesting {
                            ProgressView()
                        } else {
                            Label(movie.mediaInfo?.requestStatusLabel ?? "Request", systemImage: requestButtonIcon(for: movie))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                .disabled(vm.isRequesting || isModeratingRequest)

                if let pendingRequest, canModerateRequests {
                    moderationButton(title: "Approve", systemImage: "checkmark", tint: .green) {
                        await moderateRequest(
                            action: { try await apiClient.approveRequest(id: pendingRequest.id) },
                            successTitle: "Request Approved",
                            successMessage: "Approved \(movie.displayTitle)"
                        )
                    }

                    moderationButton(title: "Decline", systemImage: "xmark", tint: .orange) {
                        await moderateRequest(
                            action: { try await apiClient.declineRequest(id: pendingRequest.id) },
                            successTitle: "Request Declined",
                            successMessage: "Declined \(movie.displayTitle)"
                        )
                    }
                }
                
                if canModerateRequests {
                    Button {
                        if let url = URL(string: "trawl://seerr-issue") {
                            #if os(iOS)
                            UIApplication.shared.open(url)
                            #endif
                        }
                    } label: {
                        Label("Open in Trawl", systemImage: "arrow.up.forward.app")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func failedRequestCard(_ failedRequest: SeerrMediaRequest, mediaTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request Failed")
                        .font(.subheadline.weight(.semibold))
                    Text("Seerr couldn't process the previous request. Try again or check your Seerr server logs for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                if canModerateRequests {
                    Button {
                        Task {
                            await moderateRequest(
                                action: { try await apiClient.retryRequest(id: failedRequest.id) },
                                successTitle: "Retrying Request",
                                successMessage: "Retrying \(mediaTitle)"
                            )
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                    .disabled(isModeratingRequest)
                }

                Button {
                    showRequestOptions = true
                } label: {
                    Label("Request Again", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                .disabled(vm.isRequesting || isModeratingRequest)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.red.opacity(0.18)), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func playbackButton(_ movie: SeerrMovieDetail) -> some View {
        switch vm.playbackAvailability {
        case .checking:
            availabilityLabel("Checking", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.tint(Color.gray.opacity(0.16)), in: RoundedRectangle(cornerRadius: 16))
        case .playable:
            Button {
                watchMovie(movie)
            } label: {
                availabilityLabel(
                    vm.canResume ? "Continue Watching" : "Watch",
                    systemImage: vm.canResume ? "play.circle.fill" : "play.fill"
                )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
        default:
            availabilityLabel("Not in Jellyfin", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(.regular.tint(Color.orange.opacity(0.18)), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func availabilityLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
    }

    private var playbackAvailabilityMessage: String? {
        switch vm.playbackAvailability {
        case .unknown, .checking, .playable:
            nil
        case .missingInJellyfin:
            "Seerr/Radarr says this is available, but Jellyfin does not have a matching playable item."
        case .notConfigured:
            "Jellyfin playback is not configured."
        case .failed(let message):
            "Jellyfin lookup failed: \(message)"
        }
    }

    private func requestButtonIcon(for movie: SeerrMovieDetail) -> String {
        movie.mediaInfo?.isRequested == true ? "clock.fill" : "plus.circle.fill"
    }

    private var canModerateRequests: Bool {
        currentUser?.canManageRequests == true
    }

    private func pendingRequest(for movie: SeerrMovieDetail) -> SeerrMediaRequest? {
        movie.mediaInfo?.activeRequests.first { $0.requestStatus == .pending }
    }

    private func moderationButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Group {
                if isModeratingRequest {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .glassEffect(.regular.tint(tint.opacity(0.2)).interactive(), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(tint)
        .disabled(isModeratingRequest || vm.isRequesting)
    }

    private func moderateRequest(
        action: @escaping @Sendable () async throws -> SeerrMediaRequest,
        successTitle: String,
        successMessage: String
    ) async {
        isModeratingRequest = true
        defer { isModeratingRequest = false }

        do {
            let updatedRequest = try await action()
            onRequestUpdated?(updatedRequest)
            await vm.load()
            notificationCenter.show(LureBannerItem(
                title: successTitle,
                message: successMessage,
                style: .success
            ))
        } catch {
            notificationCenter.show(LureBannerItem(
                title: "Action Failed",
                message: error.localizedDescription,
                style: .error
            ))
        }
    }

    // MARK: - Overview Card

    private func overviewCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Overview", icon: "text.alignleft")
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Stats Card

    private func statsCard(_ movie: SeerrMovieDetail) -> some View {
        HStack(spacing: 0) {
            if let year = movie.year {
                statCell(value: year, label: "Year")
                cardDivider
            }
            if let runtime = movie.runtime, runtime > 0 {
                statCell(value: "\(runtime)m", label: "Runtime")
                cardDivider
            }
            statCell(
                value: movie.mediaInfo?.requestStatusLabel
                    ?? (movie.mediaInfo?.mediaStatus?.isUserVisible == true
                        ? movie.mediaInfo?.mediaStatus?.displayName ?? "Not Requested"
                        : "Not Requested"),
                label: "Status"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Watch Providers Card

    private func namedProviders(_ providers: SeerrWatchProviders) -> [SeerrWatchProvider]? {
        let named = providers.namedAvailabilityProviders
        return named.isEmpty ? nil : named
    }

    private func watchProvidersCard(_ providers: SeerrWatchProviders, named: [SeerrWatchProvider]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(providers.namedStreamingProviders.isEmpty ? "Available From" : "Streaming", icon: "play.tv")
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(named, id: \.stableID) { provider in
                        VStack(spacing: 4) {
                            AsyncImage(url: provider.logoURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                            Text(provider.providerName ?? "Unknown")
                                .font(.caption2)
                                .lineLimit(1)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .horizontalSoftEdges()
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Ratings Card

    @ViewBuilder
    private func ratingsCard(_ ratings: SeerrRatingsCombined?, movie: SeerrMovieDetail) -> some View {
        let imdbId = movie.imdbId ?? movie.externalIds?.imdbId
        let items: [(String, String)] = [
            ratings?.imdbRating.map { ("IMDb", String(format: "%.1f", $0)) },
            movie.voteAverage.flatMap { $0 > 0 ? ("TMDb", String(format: "%.0f%%", $0 * 10)) : nil },
            ratings?.criticsScore.map { ("RT", "\($0)%") },
            ratings?.audienceScore.map { ("Audience", "\($0)%") }
        ].compactMap { $0 }

        if !items.isEmpty {
            HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Group {
                    if item.0 == "IMDb", let imdbId, !imdbId.isEmpty,
                       let url = URL(string: "https://www.imdb.com/title/\(imdbId)/") {
                        Link(destination: url) {
                            VStack(spacing: 2) {
                                Text(item.1)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                HStack(spacing: 3) {
                                    Text(item.0)
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 8))
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        statCell(value: item.1, label: item.0)
                    }
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 { cardDivider }
            }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Cast Card

    private func castCard(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Cast", icon: "person.2")
                .padding(.horizontal, 14)
                .padding(.top, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(cast) { member in
                        Button {
                            selectedCastMember = member
                        } label: {
                            VStack(spacing: 4) {
                                AsyncImage(url: member.profileURL) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(.quaternary)
                                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())

                                Text(member.name ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(width: 70)
                                Text(member.character ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .horizontalSoftEdges()
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Trailer Card

    private func trailerCard(_ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Trailer")
                        .font(.subheadline.weight(.semibold))
                    Text("Opens YouTube")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Rows Data

    private func movieInfoRows(_ movie: SeerrMovieDetail) -> [(String, String, String)] {
        var rows: [(String, String, String)] = []
        if let availability = movie.releaseAvailabilityText {
            rows.append(("ticket", "Availability", availability))
        }
        if let status = movie.status {
            rows.append(("circle.fill", "Status", status))
        }
        if let studios = movie.productionCompanies, !studios.isEmpty {
            rows.append(("building.2", "Studio", studios.prefix(2).compactMap(\.name).joined(separator: ", ")))
        }
        if let budget = movie.budget, budget > 0 {
            rows.append(("dollarsign.circle", "Budget", "$\(budget / 1_000_000)M"))
        }
        if let revenue = movie.revenue, revenue > 0 {
            rows.append(("chart.bar.fill", "Revenue", "$\(revenue / 1_000_000)M"))
        }
        if let lang = movie.originalLanguage, !lang.isEmpty {
            rows.append(("globe", "Language", lang.uppercased()))
        }
        return rows
    }

    // MARK: - Shared Helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .foregroundStyle(.white)
    }

    private var cardDivider: some View {
        Rectangle().fill(.separator).frame(width: 0.5, height: 26)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func rowsCard(header: String, icon: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(header, icon: icon)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .center)
                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.2)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)

                if index < rows.count - 1 {
                    Divider().padding(.leading, 42)
                }
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}
