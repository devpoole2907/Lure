import SwiftUI

// MARK: - Previews

#if DEBUG
/// A lightweight stand-in for `TVDetailView` that renders the full scroll layout
/// without requiring a live VM or network call. Mirrors the same hero + cards structure
/// with the canned `SeerrTVDetail.previewShow` fixture.
private struct TVDetailPreviewSurface: View {
    let show: SeerrTVDetail

    @State private var heroVerticalOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: previewStackAlignment, spacing: 20) {
                heroSection
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: [.top, .horizontal])
        #else
        .ignoresSafeArea(edges: .top)
        #endif
        .background { artBackground }
        .environment(\.colorScheme, .dark)
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, newValue in
            heroVerticalOffset = max(-newValue, 0)
        }
    }

    private var previewStackAlignment: HorizontalAlignment {
        #if os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var previewContentAlignment: HorizontalAlignment {
        #if os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var previewFrameAlignment: Alignment {
        #if os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var previewContentMaxWidth: CGFloat {
        #if os(tvOS)
        .infinity
        #else
        720
        #endif
    }

    private var previewHorizontalPadding: CGFloat {
        #if os(tvOS)
        90
        #else
        16
        #endif
    }

    private var heroSection: some View {
        DetailPosterHeroView(
            title: show.displayTitle,
            artworkURL: nil,
            logoURL: nil,
            mediaTypeLabel: "TV Show",
            year: show.year,
            runtime: heroMetadataDetail(for: show),
            rating: nil,
            overview: show.overview,
            badges: showBadges,
            genres: show.genres?.compactMap(\.name) ?? [],
            ratingItems: PreviewSupport.sampleRatingItems,
            verticalOffset: heroVerticalOffset,
            primaryAction: show.hasPlayableContent
                ? PreviewSupport.playAction
                : PreviewSupport.requestAction,
            secondaryAction: PreviewSupport.addToFavoritesAction
        )
    }

    private var showBadges: [DetailBadge] {
        var badges: [DetailBadge] = []
        if let rating = show.contentRatingText {
            badges.append(DetailBadge(icon: "shield", label: rating, color: .yellow))
        }
        return badges
    }

    private func heroMetadataDetail(for show: SeerrTVDetail) -> String? {
        var components: [String] = []
        if let seasons = show.numberOfSeasons {
            components.append("\(seasons) \(seasons == 1 ? "Season" : "Seasons")")
        }
        if let status = shortShowStatus(show.status) {
            components.append(status)
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func shortShowStatus(_ status: String?) -> String? {
        switch status {
        case "Returning Series": return "Ongoing"
        case "Planned": return "Planned"
        case "Ended": return "Ended"
        case "Canceled": return "Canceled"
        default: return status
        }
    }

    private var artBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.black, .purple.opacity(0.45), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .ignoresSafeArea()
    }
}

#Preview("TV Detail — Partially Available") {
    TVDetailPreviewSurface(show: .previewShow)
}

#Preview("TV Detail — Loading") {
    ProgressView("Loading…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
#endif

#if DEBUG && os(iOS)
#Preview("TV Detail — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    TVDetailPreviewSurface(show: .previewShow)
}
#endif

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
    @State private var selectedCastMember: CastPersonRoute?
    @State private var pendingCastCreditDestination: MediaDestination?
    @State private var isModeratingRequest = false
    @State private var showEpisodePicker = false
    @State private var selectedEpisodeDetail: EpisodeDetailRoute?
    @State private var heroVerticalOffset: CGFloat = 0
    @State private var showNavTitle = false
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(PlayerCoordinator.self) private var playerCoordinator
    @Environment(RequestsCoordinator.self) private var requestsCoordinator
    @Environment(LureRouter.self) private var router

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
                    .background { artBackground(url: heroArtworkURL(for: show)) }
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
        .lureNavigationTitle(showNavTitle ? (vm.show?.displayTitle ?? initialTitle ?? "TV Show") : "")
        .onPreferenceChange(HeroTitleBottomKey.self) { maxY in
            // Ignore the default sentinel emitted when the hero is recycled off-screen
            // (LazyVStack) so the title stays put once we've scrolled well past it.
            guard maxY != .greatestFiniteMagnitude else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showNavTitle = maxY < heroTitleRevealThreshold
            }
        }
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
#endif
        #if !os(tvOS)
        // tvOS toolbar items can't receive Siri Remote focus; Report an Issue
        // lives inline at the bottom of the content there instead.
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
        #endif
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
        .sheet(item: $selectedCastMember, onDismiss: completeCastCreditNavigation) { route in
            CastPersonSheet(
                personId: route.personId,
                fallbackName: route.fallbackName,
                fallbackProfileURL: route.fallbackProfileURL,
                apiClient: apiClient,
                onSelectMedia: queueCastCreditNavigation
            )
        }
        #if os(tvOS)
        // Cast opens via the shared shelf's value-based NavigationLink. Using
        // navigationDestination(item:) here corrupts the stack order when the
        // pushed person view itself pushes value-based MediaDestinations.
        .navigationDestination(for: CastPersonRoute.self) { route in
            CastPersonSheet(
                personId: route.personId,
                fallbackName: route.fallbackName,
                fallbackProfileURL: route.fallbackProfileURL,
                apiClient: apiClient,
                presentation: .detail
            )
        }
        #endif
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
        #if os(tvOS)
        // Value-based (episode cards are NavigationLinks on tvOS) — the episode
        // page pushes value-based CastPersonRoutes, and mixing item-based pushes
        // with value pushes corrupts the stack order.
        .navigationDestination(for: EpisodeDetailRoute.self) { route in
            EpisodeDetailView(
                route: route,
                jellyfinClient: vm.jellyfinClient
            ) { episode in
                playerCoordinator.presentResume(episode)
            }
        }
        #else
        .navigationDestination(item: $selectedEpisodeDetail) { route in
            EpisodeDetailView(
                route: route,
                jellyfinClient: vm.jellyfinClient
            ) { episode in
                playerCoordinator.presentResume(episode)
            }
        }
        #endif
    }

    // MARK: - Watch

    private func playEpisodeFromShelf(_ episode: JellyfinItem?) {
        guard let episode, episode.id != nil else {
            showEpisodePicker = true
            return
        }

        playerCoordinator.presentResume(episode)
    }

    private func openEpisodeDetail(_ episode: JellyfinItem?) {
        guard let show = vm.show,
              let episode,
              let itemId = episode.id else {
            return
        }

        selectedEpisodeDetail = EpisodeDetailRoute(
            itemId: itemId,
            seriesTitle: show.displayTitle,
            episodeTitle: episode.name ?? "Episode",
            episodeLabel: episode.detailedEpisodeLabel ?? episode.episodeLabel
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
            LazyVStack(alignment: detailStackAlignment, spacing: 20) {
                heroSection(show)

                VStack(alignment: detailContentHorizontalAlignment, spacing: 20) {
                    cardsSection(show)
                }
                .padding(.horizontal, detailContentHorizontalPadding)
                .padding(.bottom, 44)
                .frame(maxWidth: detailContentMaxWidth, alignment: detailFrameAlignment)
                .frame(maxWidth: .infinity)
            }
        }
        #if os(tvOS)
        .ignoresSafeArea(edges: [.top, .horizontal])
        #else
        .ignoresSafeArea(edges: .top)
        #endif
#if os(iOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
#if os(macOS)
        .scrollEdgeEffectStyle(.soft, for: .all)
#endif
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y + $0.contentInsets.top
        } action: { _, newValue in
            heroVerticalOffset = max(-newValue, 0)
        }
        .refreshable { await vm.load() }
        .environment(\.colorScheme, .dark)
    }

    private var detailStackAlignment: HorizontalAlignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailContentHorizontalAlignment: HorizontalAlignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailFrameAlignment: Alignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var detailContentMaxWidth: CGFloat {
        #if os(macOS)
        .infinity
        #elseif os(tvOS)
        .infinity
        #else
        720
        #endif
    }

    private var detailContentHorizontalPadding: CGFloat {
        #if os(macOS)
        44
        #elseif os(tvOS)
        // Match the tvOS safe area (~90pt)
        90
        #else
        16
        #endif
    }

    // MARK: - Hero

    private func heroSection(_ show: SeerrTVDetail) -> some View {
        DetailPosterHeroView(
            title: show.displayTitle,
            artworkURL: heroArtworkURL(for: show),
            logoURL: vm.heroArtwork?.logoURL,
            mediaTypeLabel: "TV Show",
            year: show.year,
            runtime: heroMetadataDetail(for: show),
            rating: nil,
            overview: show.overview,
            badges: showBadges(show),
            genres: show.genres?.compactMap(\.name) ?? [],
            ratingItems: heroRatingItems(for: show),
            verticalOffset: heroVerticalOffset,
            primaryAction: heroAction(for: show),
            secondaryAction: favoriteAction(for: show)
        )
    }

    private func heroAction(for show: SeerrTVDetail) -> DetailPosterHeroAction {
        if show.hasPlayableContent {
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

    private func favoriteAction(for show: SeerrTVDetail) -> DetailPosterHeroAction {
        DetailPosterHeroAction(
            title: vm.isFavorite ? "Remove from Favorites" : "Add to Favorites",
            systemImage: vm.isFavorite ? "checkmark" : "plus",
            isEnabled: vm.playbackAvailability.playableItemId != nil,
            isHighlighted: vm.isFavorite
        ) {
            toggleFavorite(title: show.displayTitle)
        }
    }

    private func toggleFavorite(title: String) {
        Task { @MainActor in
            do {
                let isFavorite = try await vm.togglePlayableItemFavorite()
                notificationCenter.show(LureBannerItem(
                    title: isFavorite ? "Added to Favorites" : "Removed from Favorites",
                    message: title,
                    style: isFavorite ? .success : .info
                ))
            } catch {
                notificationCenter.show(LureBannerItem(
                    title: "Favorites Update Failed",
                    message: error.localizedDescription,
                    style: .error
                ))
            }
        }
    }

    /// Prefer clean wide key art for full-bleed surfaces; posters remain a fallback
    /// for titles without usable backdrops.
    private func heroArtworkURL(for show: SeerrTVDetail) -> URL? {
        vm.heroArtwork?.backdropURL ?? show.heroBackdropURL ?? show.backdropURL ?? show.heroPosterURL ?? initialPosterURL
    }

    /// Global-Y below which the hero title is considered tucked behind the status +
    /// inline nav bar (≈ Dynamic Island height + bar); a few px off on other devices
    /// is imperceptible.
    private var heroTitleRevealThreshold: CGFloat { 100 }

    private func showBadges(_ show: SeerrTVDetail) -> [DetailBadge] {
        var badges: [DetailBadge] = []
        if let rating = show.contentRatingText {
            badges.append(DetailBadge(icon: "shield", label: rating, color: .yellow))
        }
        return badges
    }

    private func heroMetadataDetail(for show: SeerrTVDetail) -> String? {
        var components: [String] = []
        if let seasons = show.numberOfSeasons {
            components.append("\(seasons) \(seasons == 1 ? "Season" : "Seasons")")
        }
        if let status = shortShowStatus(show.status) {
            components.append(status)
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private func heroRatingItems(for show: SeerrTVDetail) -> [DetailHeroRatingItem] {
        [
            vm.ratings?.imdbRating.map {
                DetailHeroRatingItem(label: "IMDb", value: String(format: "%.1f", $0))
            },
            (vm.ratings?.tmdbRating ?? show.voteAverage).flatMap {
                $0 > 0 ? DetailHeroRatingItem(label: "TMDb", value: String(format: "%.0f%%", $0 * 10)) : nil
            },
            vm.ratings?.criticsScore.map {
                DetailHeroRatingItem(label: "RT", value: "\($0)%")
            },
            vm.ratings?.audienceScore.map {
                DetailHeroRatingItem(label: "Audience", value: "\($0)%")
            }
        ].compactMap { $0 }
    }

    // MARK: - Cards Section

    @ViewBuilder
    private func cardsSection(_ show: SeerrTVDetail) -> some View {
        requestCard(show)

        if show.hasPlayableContent, !show.requestableSeasons.isEmpty {
            TVSeasonEpisodeShelf(
                show: show,
                jellyfinClient: vm.jellyfinClient,
                jellyfinSeriesId: vm.playbackAvailability.playableItemId,
                onPlayEpisode: playEpisodeFromShelf,
                onOpenEpisodeDetail: openEpisodeDetail
            )
        }

        if let providers = show.usWatchProviders, let named = namedProviders(providers) {
            watchProvidersCard(providers, named: named)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if let cast = show.credits?.cast, !cast.isEmpty {
            CastShelfView(
                items: cast.prefix(20).map(CastShelfItem.init),
                onSelect: openCastMember
            )
        }

        if vm.hasResolvedLocalTrailers,
           !vm.localTrailers.isEmpty || !show.trailerVideos.isEmpty {
            TrailerShelfView(
                localTrailers: vm.localTrailers,
                youtubeVideos: show.trailerVideos,
                fallbackArtworkURL: show.heroBackdropURL ?? show.heroPosterURL
            )
        }

        let infoRows = showInfoRows(show)
        if !infoRows.isEmpty {
            rowsCard(header: "Info", icon: "info.circle", rows: infoRows)
        }

        if !vm.recommendations.isEmpty {
            MediaSliderView(title: "You Might Also Like", items: vm.recommendations, apiClient: apiClient)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        #if os(tvOS)
        reportIssueButton
        #endif
    }

    #if os(tvOS)
    /// Inline replacement for the toolbar's Report an Issue menu, which the
    /// tvOS focus engine can't reach.
    private var reportIssueButton: some View {
        HStack {
            Button {
                showReportSheet = true
            } label: {
                Label("Report an Issue", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 52)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(TVHeroActionButtonStyle())

            Spacer()
        }
        .padding(.top, 8)
    }
    #endif

    // MARK: - Request Card

    /// Play / Request now live in the hero, so this card only surfaces what the hero
    /// can't: Jellyfin availability diagnostics, failed-request recovery, and the
    /// moderator-only approve / decline / open-in-Trawl actions.
    @ViewBuilder
    private func requestCard(_ show: SeerrTVDetail) -> some View {
        if show.hasPlayableContent {
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
                        openExternalURL(url)
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

    private func openCastMember(_ item: CastShelfItem) {
        selectedCastMember = item.destination
    }

    private func queueCastCreditNavigation(_ destination: MediaDestination) {
        pendingCastCreditDestination = destination
    }

    private func completeCastCreditNavigation() {
        guard let destination = pendingCastCreditDestination else { return }
        pendingCastCreditDestination = nil
        router.openMedia(destination)
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

    private func rowsCard(header: String, icon: String, rows: [(String, String, String)]) -> some View {
        #if os(tvOS)
        let horizontalPadding: CGFloat = 28
        let headerTopPadding: CGFloat = 22
        let headerBottomPadding: CGFloat = 12
        let rowVerticalPadding: CGFloat = 14
        let rowSpacing: CGFloat = 14
        let iconWidth: CGFloat = 24
        let dividerLeadingPadding: CGFloat = 66
        #else
        let horizontalPadding: CGFloat = 16
        let headerTopPadding: CGFloat = 14
        let headerBottomPadding: CGFloat = 8
        let rowVerticalPadding: CGFloat = 11
        let rowSpacing: CGFloat = 10
        let iconWidth: CGFloat = 16
        let dividerLeadingPadding: CGFloat = 42
        #endif

        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel(header, icon: icon)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, headerTopPadding)
                .padding(.bottom, headerBottomPadding)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: rowSpacing) {
                    Image(systemName: row.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: iconWidth, alignment: .center)
                    Text(row.1)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.2)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, rowVerticalPadding)

                if index < rows.count - 1 {
                    Divider().padding(.leading, dividerLeadingPadding)
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
            .lureNavigationTitle("Request Seasons")
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

#if DEBUG
#Preview("TV Request Sheet") {
    let vm = TVDetailViewModel(
        previewShow: .previewShow,
        apiClient: PreviewSupport.apiClient,
        jellyfinService: PreviewSupport.jellyfinService
    )
    TVRequestSheet(viewModel: vm)
}
#endif
