import SwiftUI

struct TVDetailView: View {
    let tmdbId: Int
    let apiClient: SeerrAPIClient
    let initialTitle: String?
    let initialPosterURL: URL?
    let currentUser: SeerrUser?
    let onRequestUpdated: ((SeerrMediaRequest) -> Void)?

    @State private var vm: TVDetailViewModel
    @State private var showRequestSheet = false
    @State private var showReportSheet = false
    @State private var selectedCastMember: SeerrCastMember?
    @State private var isModeratingRequest = false
    @State private var showEpisodePicker = false
    @State private var heroVerticalOffset: CGFloat = 0
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
        self._vm = State(initialValue: TVDetailViewModel(tmdbId: tmdbId, apiClient: apiClient, jellyfinService: jellyfinService))
    }

    var body: some View {
        Group {
            if let show = vm.show {
                scrollContent(show)
                    .background { artBackground(url: displayPosterURL(for: show)) }
                    .transition(.opacity)
            } else if vm.isLoading {
                loadingContent
                    .transition(.opacity)
            } else {
                ContentUnavailableView("Show Not Found", systemImage: "tv")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.show?.id)
        .animation(.easeInOut(duration: 0.25), value: vm.ratings != nil)
        .animation(.easeInOut(duration: 0.25), value: vm.recommendations.count)
        .navigationTitle(vm.show?.displayTitle ?? initialTitle ?? "TV Show")
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
                mediaId: vm.show?.mediaInfo?.id,
                mediaTitle: vm.show?.displayTitle ?? initialTitle,
                apiClient: apiClient
            )
        }
        .errorAlert(item: Binding(
            get: { vm.error.map { ErrorAlertItem(title: "Error", message: $0) } },
            set: { _ in vm.error = nil }
        ))
        .sheet(isPresented: $showRequestSheet) {
            TVRequestSheet(viewModel: vm)
        }
        .sheet(item: $selectedCastMember) { member in
            CastPersonSheet(
                personId: member.id,
                fallbackName: member.name,
                fallbackProfileURL: member.profileURL,
                apiClient: apiClient
            )
        }
        .task { await vm.load() }
        .onChange(of: vm.requestSuccess) { _, success in
            if success {
                let title = vm.show?.displayTitle ?? initialTitle ?? "your request"
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
        .sheet(isPresented: $showEpisodePicker) {
            if let show = vm.show {
                EpisodePickerView(
                    tmdbId: tmdbId,
                    seriesTitle: show.displayTitle,
                    serviceUrl: nil,
                    jellyfinSeriesId: vm.playbackAvailability.playableItemId
                ) { episodeId, episodeLabel, title in
                    showEpisodePicker = false
                    playerCoordinator.present(
                        itemId: episodeId,
                        title: title,
                        episodeLabel: episodeLabel,
                        mediaType: "tv"
                    )
                }
            }
        }
    }

    // MARK: - Watch

    private func playEpisodeFromShelf(_ episode: JellyfinItem?) {
        guard let episode, episode.id != nil else {
            showEpisodePicker = true
            return
        }

        playerCoordinator.presentResume(episode)
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
                Rectangle().fill(Color.purple.opacity(0.4))
            @unknown default:
                Rectangle().fill(Color.purple.opacity(0.4))
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

    private func scrollContent(_ show: SeerrTVDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .center, spacing: 20) {
                heroSection(show)

                VStack(alignment: .center, spacing: 20) {
                    cardsSection(show)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 44)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
#if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, newValue in
            heroVerticalOffset = max(-newValue, 0)
        }
        .refreshable { await vm.load() }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Hero

    private func heroSection(_ show: SeerrTVDetail) -> some View {
        DetailPosterHeroView(
            title: show.displayTitle,
            posterURL: heroPosterURL(for: show),
            mediaTypeLabel: "TV Show",
            year: show.year,
            rating: show.voteAverage,
            badges: [],
            genres: [],
            verticalOffset: heroVerticalOffset,
            primaryAction: heroAction(for: show)
        )
    }

    private func heroAction(for show: SeerrTVDetail) -> DetailPosterHeroAction {
        if show.mediaInfo?.isAvailable == true {
            return DetailPosterHeroAction(
                title: "Play",
                systemImage: "play.fill",
                isEnabled: vm.playbackAvailability.playableItemId != nil
            ) {
                showEpisodePicker = true
            }
        }

        return DetailPosterHeroAction(
            title: "Request",
            systemImage: requestButtonIcon(for: show),
            isEnabled: !vm.isRequesting && !isModeratingRequest
        ) {
            showRequestSheet = true
        }
    }

    private func displayPosterURL(for show: SeerrTVDetail) -> URL? {
        initialPosterURL ?? show.posterURL
    }

    /// The hero is full-bleed, so prefer the original-resolution poster from the
    /// loaded show; only fall back to the low-res list thumbnail before it lands.
    private func heroPosterURL(for show: SeerrTVDetail) -> URL? {
        show.heroPosterURL ?? initialPosterURL
    }

    // MARK: - Cards Section

    @ViewBuilder
    private func cardsSection(_ show: SeerrTVDetail) -> some View {
        requestCard(show)

        if show.mediaInfo?.isAvailable == true, !show.requestableSeasons.isEmpty {
            TVSeasonEpisodeShelf(
                show: show,
                jellyfinClient: vm.jellyfinClient,
                jellyfinSeriesId: vm.playbackAvailability.playableItemId,
                onPlayEpisode: playEpisodeFromShelf,
                onOpenEpisodePicker: { showEpisodePicker = true }
            )
        }

        if let overview = show.overview, !overview.isEmpty {
            overviewCard(overview)
        }

        statsCard(show)

        if let providers = show.usWatchProviders, let named = namedProviders(providers) {
            watchProvidersCard(providers, named: named)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if let genres = show.genres, !genres.isEmpty {
            genreChips(genres.compactMap(\.name))
        }

        if let ratings = vm.ratings, ratings.hasAnyScore {
            ratingsCard(ratings)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if let cast = show.credits?.cast, !cast.isEmpty {
            castCard(Array(cast.prefix(20)))
        }

        if let url = show.trailerURL {
            trailerCard(url)
        }

        let infoRows = showInfoRows(show)
        if !infoRows.isEmpty {
            rowsCard(header: "Info", icon: "info.circle", rows: infoRows)
        }

        if !vm.recommendations.isEmpty {
            MediaSliderView(title: "You Might Also Like", icon: "sparkles", items: vm.recommendations, apiClient: apiClient)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: - Request Card

    /// Play / Request now live in the hero, so this card only surfaces what the hero
    /// can't: Jellyfin availability diagnostics, failed-request recovery, and the
    /// moderator-only approve / decline / open-in-Trawl actions.
    @ViewBuilder
    private func requestCard(_ show: SeerrTVDetail) -> some View {
        if show.mediaInfo?.isAvailable == true {
            if let message = playbackAvailabilityMessage {
                availabilityDiagnostic(message)
            }
        } else if let failedRequest = show.mediaInfo?.mostRecentFailedRequest {
            failedRequestCard(failedRequest, mediaTitle: show.displayTitle)
        } else if canModerateRequests {
            let pendingRequest = pendingRequest(for: show)

            HStack(spacing: 12) {
                if let pendingRequest {
                    moderationButton(title: "Approve", systemImage: "checkmark", tint: .green) {
                        await moderateRequest(
                            action: { try await apiClient.approveRequest(id: pendingRequest.id) },
                            successTitle: "Request Approved",
                            successMessage: "Approved \(show.displayTitle)"
                        )
                    }

                    moderationButton(title: "Decline", systemImage: "xmark", tint: .orange) {
                        await moderateRequest(
                            action: { try await apiClient.declineRequest(id: pendingRequest.id) },
                            successTitle: "Request Declined",
                            successMessage: "Declined \(show.displayTitle)"
                        )
                    }
                }

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

    private func availabilityDiagnostic(_ message: String) -> some View {
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Color.orange.opacity(0.16)), in: RoundedRectangle(cornerRadius: 16))
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
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                    .disabled(isModeratingRequest)
                }

                Button {
                    showRequestSheet = true
                } label: {
                    Label("Request Again", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14))
                .disabled(isModeratingRequest)
            }
        }
        .padding(14)
        .glassEffect(.regular.tint(Color.red.opacity(0.18)), in: RoundedRectangle(cornerRadius: 16))
    }

    private var playbackAvailabilityMessage: String? {
        switch vm.playbackAvailability {
        case .unknown, .checking, .playable:
            nil
        case .missingInJellyfin:
            "Seerr says this is available, but Jellyfin does not have a matching playable series."
        case .notConfigured:
            "Jellyfin playback is not configured."
        case .failed(let message):
            "Jellyfin lookup failed: \(message)"
        }
    }

    private func requestButtonIcon(for show: SeerrTVDetail) -> String {
        show.mediaInfo?.isRequested == true ? "clock.fill" : "plus.circle.fill"
    }

    private var canModerateRequests: Bool {
        currentUser?.canManageRequests == true
    }

    private func pendingRequest(for show: SeerrTVDetail) -> SeerrMediaRequest? {
        show.mediaInfo?.activeRequests.first { $0.requestStatus == .pending }
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
        .disabled(isModeratingRequest)
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

    private func statsCard(_ show: SeerrTVDetail) -> some View {
        HStack(spacing: 0) {
            if let year = show.year {
                statCell(value: year, label: "Year")
                cardDivider
            }
            if let seasons = show.numberOfSeasons {
                statCell(value: "\(seasons)", label: seasons == 1 ? "Season" : "Seasons")
                cardDivider
            }
            statCell(
                value: shortShowStatus(show.status)
                    ?? show.mediaInfo?.requestStatusLabel
                    ?? (show.mediaInfo?.mediaStatus?.isUserVisible == true
                        ? show.mediaInfo?.mediaStatus?.displayName ?? "Not Requested"
                        : "Not Requested"),
                label: "Series Status"
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

                            Text(provider.providerName ?? "")
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

    // MARK: - Genre Chips

    private func genreChips(_ genres: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres.prefix(8), id: \.self) { genre in
                    Text(genre)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: Capsule())
                }
            }
            .padding(.horizontal, 4)
        }
        .horizontalSoftEdges()
        .frame(maxWidth: .infinity)
    }

    private func shortShowStatus(_ status: String?) -> String? {
        switch status {
        case "Returning Series":
            return "Ongoing"
        case "Planned":
            return "Planned"
        case "Ended":
            return "Ended"
        case "Canceled":
            return "Canceled"
        default:
            return status
        }
    }

    // MARK: - Ratings Card

    private func ratingsCard(_ ratings: SeerrRatingsCombined) -> some View {
        let items: [(String, String)] = [
            ratings.imdbRating.map { ("IMDb", String(format: "%.1f", $0)) },
            ratings.tmdbRating.map { ("TMDb", String(format: "%.0f%%", $0 * 10)) },
            ratings.criticsScore.map { ("RT", "\($0)%") },
            ratings.audienceScore.map { ("Audience", "\($0)%") }
        ].compactMap { $0 }

        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                statCell(value: item.1, label: item.0)
                if index < items.count - 1 { cardDivider }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
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
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Info Rows Data

    private func showInfoRows(_ show: SeerrTVDetail) -> [(String, String, String)] {
        var rows: [(String, String, String)] = []
        if let type = show.type {
            rows.append(("list.bullet", "Type", type))
        }
        if let network = show.networks?.first?.name {
            rows.append(("antenna.radiowaves.left.and.right", "Network", network))
        }
        if let episodes = show.numberOfEpisodes {
            rows.append(("play.rectangle.on.rectangle", "Episodes", "\(episodes)"))
        }
        if let runtime = show.episodeRunTime?.first, runtime > 0 {
            rows.append(("clock", "Runtime", "\(runtime)m / episode"))
        }
        if let lang = show.originalLanguage, !lang.isEmpty {
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

// MARK: - TV Request Sheet

struct TVRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    var viewModel: TVDetailViewModel
    @State private var requestIn4K = false

    private var seasons: [SeerrTVSeason] {
        viewModel.show?.requestableSeasons ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        actionPill("Select All", systemImage: "checkmark.circle") {
                            viewModel.selectAllSeasons(is4k: requestIn4K)
                        }

                        actionPill("Clear", systemImage: "xmark.circle") {
                            viewModel.deselectAllSeasons()
                        }

                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Select Seasons")
                }

                Section {
                    ForEach(seasons) { season in
                        let unavailable = viewModel.isSeasonUnavailableForRequest(season.seasonNumber, is4k: requestIn4K)

                        Button {
                            if !unavailable { viewModel.toggleSeason(season.seasonNumber) }
                        } label: {
                            HStack {
                                Image(systemName: viewModel.selectedSeasons.contains(season.seasonNumber) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(unavailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))

                                Text(season.name ?? "Season \(season.seasonNumber)")
                                    .foregroundStyle(unavailable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                                Spacer()

                                if unavailable {
                                    Text(viewModel.unavailableSeasonReason(season.seasonNumber, is4k: requestIn4K) ?? "Unavailable")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(unavailable)
                    }
                }

                Section("Options") {
                    Toggle(isOn: $requestIn4K) {
                        Label("Request in 4K", systemImage: "sparkles.tv")
                    }
                }
            }
            .navigationTitle("Request Seasons")
#if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Request") {
                        Task {
                            await viewModel.requestShow(is4k: requestIn4K)
                            if viewModel.requestSuccess { dismiss() }
                        }
                    }
                    .disabled(viewModel.selectedSeasons.isEmpty || viewModel.isRequesting)
                }
            }
        }
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
#endif
        .onChange(of: requestIn4K) { _, is4k in
            viewModel.filterSelectedSeasons(for: is4k)
        }
    }

    private func actionPill(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
