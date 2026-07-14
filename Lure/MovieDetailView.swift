import SwiftUI

// MARK: - Previews

#if DEBUG
/// A lightweight stand-in for `MovieDetailView` that renders the full scroll layout
/// without requiring a live VM or network call. It constructs the same hero + cards
/// structure with a fully canned `SeerrMovieDetail`.
private struct MovieDetailPreviewSurface: View {
    let movie: SeerrMovieDetail

    @State private var heroVerticalOffset: CGFloat = 0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: previewStackAlignment, spacing: 20) {
                heroSection

                VStack(alignment: previewContentAlignment, spacing: 20) {
                    statsCard
                }
                .padding(.horizontal, previewHorizontalPadding)
                .padding(.bottom, 44)
                .frame(maxWidth: previewContentMaxWidth)
                .frame(maxWidth: .infinity, alignment: previewFrameAlignment)
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

    private var heroPrimaryAction: DetailPosterHeroAction {
        movie.mediaInfo?.isAvailable == true
            ? PreviewSupport.playAction
            : PreviewSupport.requestAction
    }

    private var heroGenres: [String] {
        movie.genres?.compactMap(\.name) ?? []
    }

    private var heroSection: some View {
        DetailPosterHeroView(
            title: movie.displayTitle,
            artworkURL: nil,
            logoURL: nil,
            mediaTypeLabel: "Movie",
            year: movie.year,
            runtime: movie.runtimeText,
            rating: nil,
            overview: movie.overview,
            badges: movieBadges,
            genres: heroGenres,
            ratingItems: PreviewSupport.sampleRatingItems,
            verticalOffset: heroVerticalOffset,
            primaryAction: heroPrimaryAction,
            secondaryAction: PreviewSupport.addToFavoritesAction
        )
    }

    private var movieBadges: [DetailBadge] {
        var badges: [DetailBadge] = []
        if let status = movie.mediaInfo?.mediaStatus, status.isUserVisible {
            badges.append(DetailBadge(icon: status.systemImage, label: status.displayName, color: status.color))
        }
        return badges
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Info", systemImage: "info.circle")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if let status = movie.status {
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("Status")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(status)
                        .font(.subheadline)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }

            Color.clear.frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var artBackground: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.black, .indigo.opacity(0.45), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .ignoresSafeArea()
    }
}

#Preview("Movie Detail — Available") {
    MovieDetailPreviewSurface(movie: PreviewSupport.previewMovieDetail)
}

#Preview("Movie Detail — Requested") {
    MovieDetailPreviewSurface(movie: PreviewSupport.previewMovieDetailRequested)
}

#Preview("Movie Detail — Loading") {
    ProgressView("Loading…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
}
#endif

#if DEBUG && os(iOS)
#Preview("Movie Detail — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    MovieDetailPreviewSurface(movie: PreviewSupport.previewMovieDetail)
}
#endif

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
    @State private var selectedCastMember: CastPersonRoute?
    @State private var pendingCastCreditDestination: MediaDestination?
    @State private var isModeratingRequest = false
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
        self._vm = State(initialValue: MovieDetailViewModel(tmdbId: tmdbId, apiClient: apiClient, jellyfinService: jellyfinService))
    }

    var body: some View {
        Group {
            if let movie = vm.movie {
                scrollContent(movie)
                    .background { artBackground(url: heroArtworkURL(for: movie)) }
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
        .lureNavigationTitle(showNavTitle ? (vm.movie?.displayTitle ?? initialTitle ?? "Movie") : "")
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
                mediaId: vm.movie?.mediaInfo?.id,
                mediaTitle: vm.movie?.displayTitle ?? initialTitle,
                apiClient: apiClient
            )
        }
        .errorAlert(item: Binding(
            get: { vm.error.map { ErrorAlertItem(title: "Error", message: $0) } },
            set: { _ in vm.error = nil }
        ))
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
        let stack = LazyVStack(alignment: detailStackAlignment, spacing: 20) {
            heroSection(movie)

            VStack(alignment: detailContentHorizontalAlignment, spacing: 20) {
                cardsSection(movie)
            }
            .padding(.horizontal, detailContentHorizontalPadding)
            .padding(.bottom, 44)
            .frame(maxWidth: detailContentMaxWidth, alignment: detailFrameAlignment)
            .frame(maxWidth: .infinity)
        }
        return scrollView(for: stack)
    }

    private func scrollView<Content: View>(for content: Content) -> some View {
        ScrollView {
            content
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
        #if !os(tvOS)
        .refreshable { await vm.load() }
        #endif
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
        90
        #else
        16
        #endif
    }

    // MARK: - Hero

    private func heroSection(_ movie: SeerrMovieDetail) -> some View {
        DetailPosterHeroView(
            title: movie.displayTitle,
            artworkURL: heroArtworkURL(for: movie),
            logoURL: vm.heroArtwork?.logoURL,
            mediaTypeLabel: "Movie",
            year: movie.year,
            runtime: movie.runtimeText,
            rating: nil,
            overview: movie.overview,
            badges: movieBadges(movie),
            genres: movie.genres?.compactMap(\.name) ?? [],
            ratingItems: heroRatingItems(for: movie),
            verticalOffset: heroVerticalOffset,
            primaryAction: heroAction(for: movie),
            secondaryAction: favoriteAction(for: movie)
        )
    }

    private func heroAction(for movie: SeerrMovieDetail) -> DetailPosterHeroAction {
        if movie.mediaInfo?.isAvailable == true {
            return DetailPosterHeroAction(
                title: vm.canResume ? "Continue Watching" : "Play",
                systemImage: vm.canResume ? "play.circle.fill" : "play.fill",
                isEnabled: vm.playbackAvailability.playableItemId != nil
            ) {
                watchMovie(movie)
            }
        }

        return DetailPosterHeroAction(
            title: "Request",
            systemImage: requestButtonIcon(for: movie),
            isEnabled: !vm.isRequesting && !isModeratingRequest
        ) {
            showRequestOptions = true
        }
    }

    private func favoriteAction(for movie: SeerrMovieDetail) -> DetailPosterHeroAction {
        DetailPosterHeroAction(
            title: vm.isFavorite ? "Remove from Favorites" : "Add to Favorites",
            systemImage: vm.isFavorite ? "checkmark" : "plus",
            isEnabled: vm.playbackAvailability.playableItemId != nil,
            isHighlighted: vm.isFavorite
        ) {
            toggleFavorite(title: movie.displayTitle)
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
    private func heroArtworkURL(for movie: SeerrMovieDetail) -> URL? {
        vm.heroArtwork?.backdropURL ?? movie.heroBackdropURL ?? movie.backdropURL ?? movie.heroPosterURL ?? initialPosterURL
    }

    /// Global-Y below which the hero title is considered tucked behind the status +
    /// inline nav bar (≈ Dynamic Island height + bar); a few px off on other devices
    /// is imperceptible.
    private var heroTitleRevealThreshold: CGFloat { 100 }

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

    private func heroRatingItems(for movie: SeerrMovieDetail) -> [DetailHeroRatingItem] {
        let imdbId = movie.imdbId ?? movie.externalIds?.imdbId
        let imdbURL = imdbId.flatMap { URL(string: "https://www.imdb.com/title/\($0)/") }

        return [
            vm.ratings?.imdbRating.map {
                DetailHeroRatingItem(label: "IMDb", value: String(format: "%.1f", $0), destination: imdbURL)
            },
            movie.voteAverage.flatMap {
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
    private func cardsSection(_ movie: SeerrMovieDetail) -> some View {
        requestCard(movie)
        supplementalCards(movie)
        contentCards(movie)
    }

    @ViewBuilder
    private func supplementalCards(_ movie: SeerrMovieDetail) -> some View {
        if let providers = movie.usWatchProviders, let named = namedProviders(providers) {
            watchProvidersCard(providers, named: named)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if let cast = movie.credits?.cast, !cast.isEmpty {
            CastShelfView(
                items: cast.prefix(20).map(CastShelfItem.init),
                onSelect: openCastMember
            )
        }
    }

    @ViewBuilder
    private func contentCards(_ movie: SeerrMovieDetail) -> some View {
        if vm.hasResolvedLocalTrailers,
           !vm.localTrailers.isEmpty || !movie.trailerVideos.isEmpty {
            TrailerShelfView(
                localTrailers: vm.localTrailers,
                youtubeVideos: movie.trailerVideos,
                fallbackArtworkURL: movie.heroBackdropURL ?? movie.heroPosterURL
            )
        }

        let infoRows = movieInfoRows(movie)
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
    private func requestCard(_ movie: SeerrMovieDetail) -> some View {
        if movie.mediaInfo?.isAvailable == true {
            if let message = playbackAvailabilityMessage {
                availabilityDiagnostic(message)
            }
        } else if let failedRequest = movie.mediaInfo?.mostRecentFailedRequest {
            failedRequestCard(failedRequest, mediaTitle: movie.displayTitle)
        } else if canModerateRequests {
            moderatorActionsCard(movie)
        }
    }

    private func moderatorActionsCard(_ movie: SeerrMovieDetail) -> some View {
        let pendingRequest = pendingRequest(for: movie)
        return HStack(spacing: 12) {
            if let pendingRequest {
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

            openInTrawlButton
        }
    }

    private var openInTrawlButton: some View {
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
