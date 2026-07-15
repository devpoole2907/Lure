import SwiftUI

struct DiscoverHeroCarouselView: View {
    let items: [SeerrMediaItem]
    @Binding var activeIndex: Int
    @Binding var scrollTargetID: String?
    var transitionNamespace: Namespace.ID? = nil
    var verticalOffset: CGFloat = 0
    var isActive: Bool = true
    /// Reports the exact image URL the active panel is displaying (including
    /// async artwork upgrades) so the host can mirror it — DiscoverView's
    /// ambient blurred background must always match the visible hero.
    var onActiveImageChange: ((URL?) -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var artworkByItemID: [String: MediaArtwork] = [:]
    @State private var containerWidth: CGFloat = 0
    @State private var heroFavoriteStates: [String: Bool] = [:]
    @State private var heroFavoriteItemIDs: [String: String] = [:]
    @State private var heroFavoriteActionsInFlight: Set<String> = []
    /// Item ids currently showing the transient expanded "Added" pill.
    @State private var heroAddedConfirmationItemIDs: Set<String> = []
    @State private var autoAdvanceResetToken = 0
    #if os(tvOS)
    @FocusState private var heroFocus: HeroFocusTarget?
    #endif
    private var heroItems: [SeerrMediaItem] {
        Self.heroItems(from: items)
    }

    /// Shared with DiscoverView so it can resolve the active hero item (for
    /// its ambient blurred background) using the same filtering the carousel
    /// itself paginates with.
    static func heroItems(from items: [SeerrMediaItem]) -> [SeerrMediaItem] {
        Array(items.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }.prefix(8))
    }

    /// Artwork URL for the ambient blurred page background behind Discover.
    /// Only a first-frame fallback — once the carousel appears it reports the
    /// exact displayed URL through `onActiveImageChange`.
    static func ambientBackdropURL(for item: SeerrMediaItem) -> URL? {
        backdropURL(for: item) ?? item.posterURL
    }

    /// The image URL the active panel is currently displaying, tracking both
    /// paging and async artwork resolution.
    private var activeHeroImageURL: URL? {
        heroItems[safe: activeIndex].flatMap { heroImageURL(for: $0) }
    }

    #if os(tvOS)
    /// Focusable slots in a hero panel's action row, keyed by the item id so
    /// each carousel panel gets distinct focus identities.
    private enum HeroFocusTarget: Hashable {
        case details(String)
        case favorite(String)
        case next(String)
        case previousEdge(String)
        case nextEdge(String)

        var itemID: String {
            switch self {
            case .details(let id), .favorite(let id), .next(let id),
                 .previousEdge(let id), .nextEdge(let id):
                id
            }
        }

        var isEdgeCatcher: Bool {
            switch self {
            case .previousEdge, .nextEdge: true
            case .details, .favorite, .next: false
            }
        }
    }

    private var heroEdgeCatcherOffset: CGFloat { 52 }
    #endif

    var body: some View {
        if !heroItems.isEmpty {
            ZStack(alignment: .bottom) {
                AppleTVCarousel(fullBleed: heroCarouselFullBleed, scrollPositionID: $scrollTargetID) {
                    ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, item in
                        let destination = MediaDestination(
                            mediaType: item.mediaType,
                            tmdbId: item.tmdbId,
                            title: item.title,
                            posterURL: item.posterURL,
                            sourceID: "discover-hero-\(index)-\(item.id)"
                        )

                        heroPanel(for: item, destination: destination)
                        .id(item.id)
                    }
                } scrollProgress: { progress in
                    let newIndex = min(max(Int(progress.rounded()), 0), heroItems.count - 1)
                    // Do not programmatically transfer `heroFocus` as the page
                    // changes. Forcing the incoming Details button here fought
                    // tvOS's scroll/focus resolution badly enough to break hero
                    // scrolling. The occasional fallback to the shelf below is
                    // preferable until this can be revisited without mutating
                    // focus during an active scroll transition.
                    activeIndex = newIndex
                }
                .onScrollPhaseChange { _, newPhase in
                    scrollPhase = newPhase
                    if newPhase == .interacting {
                        resetAutoAdvanceTimer()
                    }
                }

                PageControlView(numberOfPages: heroItems.count, currentPage: activeIndex)
                    .frame(height: 24)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)

            }
            .frame(height: carouselHeight + verticalOffset)
            .offset(y: -verticalOffset)
            #if os(tvOS)
            .ignoresSafeArea(edges: .all)
            #endif
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { _, width in
                containerWidth = width
            }
            .onAppear { restoreScrollPosition() }
            .onChange(of: activeHeroImageURL, initial: true) { _, newValue in
                onActiveImageChange?(newValue)
            }
            .onChange(of: isActive) { _, nowActive in
                if nowActive { restoreScrollPosition() }
            }
            #if os(tvOS)
            .onChange(of: heroFocus) { oldValue, newValue in
                handleHeroFocusChange(from: oldValue, to: newValue)
            }
            #endif
            .task(id: heroItems.map(\.id).joined(separator: "|")) {
                syncCarouselSelection()
                await loadHeroArtwork()
                await preloadHeroImages()
            }
            .task(id: "\(heroItems.map(\.id).joined(separator: "|"))|\(jellyfinService.hasCredentials)") {
                await loadHeroFavoriteStates()
            }
            .task(id: "\(heroItems.map(\.id).joined(separator: "|"))|\(isActive)|\(autoAdvanceResetToken)") {
                await autoAdvanceCarousel()
            }
        }
    }

    @ViewBuilder
    private func heroPanel(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        // matchedTransitionSource feeds the iOS/visionOS zoom transition
        // only; on tvOS it flattens the panel into a snapshot container that
        // strips descendant hover effects' shapes (the hero action buttons'
        // capsule shine), so it must not wrap the panel there.
        #if os(tvOS)
        panelContent(for: item, destination: destination)
        #else
        if let transitionNamespace {
            panelContent(for: item, destination: destination)
                .matchedTransitionSource(id: destination, in: transitionNamespace)
        } else {
            panelContent(for: item, destination: destination)
        }
        #endif
    }

    private func panelContent(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                #if os(tvOS)
                // tvOS navigates via remote focus on the Details button, so
                // the masked layer isn't wrapped in a NavigationLink.
                heroImageLayer(for: item, size: size)
                #else
                // macOS and iOS/iPadOS can tap the hero image itself to open
                // the detail view; tvOS navigates via remote focus on the
                // Details button instead. The masked layer fades the hero's
                // bottom into DiscoverView's ambient blurred background,
                // exactly like the detail views' hero treatment.
                NavigationLink(value: destination) {
                    heroImageLayer(for: item, size: size)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.title)")
                #endif

                bottomContent(for: item, destination: destination)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            #if os(tvOS)
            .accessibilityElement(children: .contain)
            #else
            .accessibilityElement(children: .combine)
            #endif
            .accessibilityLabel(accessibilityLabel(for: item))
        }
    }

    private func heroImage(for item: SeerrMediaItem) -> some View {
        #if os(tvOS)
        // Progressive: sized variant first (usually cached), TMDB original
        // (up to 4K) crossfades in when decoded — the 1920pt canvas on a 4K
        // panel makes the sized variant visibly soft.
        ProgressiveRemoteImage(
            url: heroImageURL(for: item),
            highResURL: heroImageHighResURL(for: item),
            contentMode: .fill
        ) {
            heroPlaceholder(for: item)
        }
        #else
        CachedRemoteImage(url: heroImageURL(for: item), contentMode: .fill) {
            heroPlaceholder(for: item)
        }
        #endif
    }

    /// Sharp hero image plus its readability gradient, masked together so the
    /// bottom edge fades to clear and reveals the blurred `heroBackdrop`
    /// behind it instead of ending in a hard cut. 1:1 with
    /// DetailPosterHeroView's `heroVisualLayer` (same gradient stops, same
    /// mask) — the gradient must live inside the mask, or its dark bottom
    /// would paint over the fade and hide the blend entirely.
    private func heroImageLayer(for item: SeerrMediaItem, size: CGSize) -> some View {
        ZStack {
            heroImage(for: item)
                .frame(width: size.width, height: size.height)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.20), location: 0.45),
                    .init(color: .black.opacity(0.65), location: 0.72),
                    .init(color: .black.opacity(0.88), location: 0.88),
                    .init(color: .black.opacity(0.72), location: 0.96),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .mask(
            // Eased fade rather than the detail views' flat-then-linear ramp:
            // the abrupt slope change at the fade's start read as a visible
            // horizontal bar across the hero. These stops approximate a
            // smoothstep from 0.68 to 1.0.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.62),
                    .init(color: .black.opacity(0.90), location: 0.72),
                    .init(color: .black.opacity(0.72), location: 0.80),
                    .init(color: .black.opacity(0.50), location: 0.87),
                    .init(color: .black.opacity(0.30), location: 0.925),
                    .init(color: .black.opacity(0.14), location: 0.965),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }


    private func heroPlaceholder(for item: SeerrMediaItem) -> some View {
        ZStack {
            Rectangle()
                .fill(.linearGradient(
                    colors: heroPlaceholderColors(for: item),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        }
    }

    /// Derive a per-item placeholder color from the item ID so the carousel
    /// doesn't show identical black frames when artwork hasn't loaded.
    private func heroPlaceholderColors(for item: SeerrMediaItem) -> [Color] {
        let palettes: [[Color]] = [
            [.indigo, .purple.opacity(0.8), .black],
            [.blue.opacity(0.9), .indigo.opacity(0.7), .black],
            [.teal.opacity(0.8), .blue.opacity(0.6), .black],
            [.purple.opacity(0.9), .pink.opacity(0.5), .black]
        ]
        let index = abs(item.tmdbId) % palettes.count
        return palettes[index]
    }

    private func bottomContent(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        let isActive = heroItems[safe: activeIndex]?.id == item.id
        let isMarked = isHeroMarked(item)
        let isFavoriteEnabled = isHeroFavoriteEnabled(item)

        return VStack(alignment: heroContentAlignment, spacing: 10) {
            #if os(tvOS)
            HeroTitleArtworkView(
                title: item.title,
                logoURL: artworkByItemID[item.id]?.logoURL,
                maxWidth: heroTitleMaxWidth,
                maxLogoHeight: heroLogoMaxHeight,
                horizontalAlignment: heroContentAlignment
            )
            .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
            #else
            // Same tap-to-navigate treatment as the hero image itself; tvOS
            // navigates via remote focus on the Details button instead.
            NavigationLink(value: destination) {
                HeroTitleArtworkView(
                    title: item.title,
                    logoURL: artworkByItemID[item.id]?.logoURL,
                    maxWidth: heroTitleMaxWidth,
                    maxLogoHeight: heroLogoMaxHeight,
                    horizontalAlignment: heroContentAlignment
                )
                .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.title)")
            #endif

            heroMetadata(for: item)

            #if os(macOS)
            if let synopsis = synopsis(for: item) {
                Text(synopsis)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
            #endif
            #if os(tvOS)
            if let synopsis = synopsis(for: item) {
                Text(synopsis)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            #endif

            HStack(spacing: heroButtonSpacing) {
                NavigationLink(value: destination) {
                    #if os(tvOS)
                    TVHeroCapsuleLabel(title: "Details", systemImage: "info.circle.fill")
                    #else
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                        Text("Details")
                    }
                        .font(heroButtonFont)
                        .foregroundStyle(.black)
                        .padding(.horizontal, heroButtonHorizontalPadding)
                        .frame(height: heroButtonHeight)
                        .background(.white, in: Capsule())
                    #endif
                }
                #if os(tvOS)
                .buttonStyle(TVHeroActionButtonStyle())
                .focused($heroFocus, equals: .details(item.id))
                #else
                .buttonStyle(.plain)
                #endif
                .disabled(!isActive)

                Button {
                    toggleHeroMarker(for: item)
                } label: {
                    #if os(tvOS)
                    TVHeroCircleIconLabel(
                        systemImage: isMarked ? "checkmark" : "plus",
                        isHighlighted: isMarked,
                        expandedText: heroAddedConfirmationItemIDs.contains(item.id) ? "Added" : nil
                    )
                    #else
                    // A Capsule renders as a circle at rest (width == height)
                    // and stretches into a pill while the transient "Added"
                    // confirmation is showing, then springs back.
                    let isConfirmingAdd = heroAddedConfirmationItemIDs.contains(item.id)
                    HStack(spacing: 6) {
                        Image(systemName: isMarked ? "checkmark" : "plus")
                            .font(heroSecondaryButtonIconFont)
                        if isConfirmingAdd {
                            Text("Added")
                                .font(heroButtonFont)
                                .fixedSize()
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, isConfirmingAdd ? 18 : 0)
                    .frame(minWidth: heroSecondaryButtonSize)
                    .frame(height: heroSecondaryButtonSize)
                    .background {
                        Capsule()
                            .fill(isMarked ? Color.green : Color.clear)
                            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isMarked)
                    }
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(isMarked ? .white.opacity(0.55) : .white.opacity(0.18), lineWidth: 0.8)
                    }
                    .scaleEffect(isMarked ? 1.04 : 1)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isMarked)
                    #endif
                }
                #if os(tvOS)
                .buttonStyle(TVHeroActionButtonStyle())
                .focused($heroFocus, equals: .favorite(item.id))
                #else
                .buttonStyle(.plain)
                .contentShape(Capsule())
                #endif
                .disabled(!isActive || heroFavoriteActionsInFlight.contains(item.id))
                .opacity(isFavoriteEnabled || isMarked ? 1 : 0.72)
                .accessibilityLabel(isMarked ? "Remove from Favorites" : "Add to Favorites")
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: isMarked)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: heroAddedConfirmationItemIDs)

                #if os(tvOS)
                Button {
                    moveCarousel(by: 1, wraps: true, resetsTimer: true)
                } label: {
                    TVHeroCircleIconLabel(systemImage: "chevron.right")
                }
                .buttonStyle(TVHeroActionButtonStyle())
                .focused($heroFocus, equals: .next(item.id))
                .disabled(!isActive || heroItems.count < 2)
                .accessibilityLabel("Next featured title")
                #endif
            }
            #if os(tvOS)
            // Invisible focus catchers just past the row's ends. Swiping right
            // off the chevron advances the carousel; swiping left off Details
            // goes back — except on the first item, where the catcher is not
            // focusable so the system's default left-edge behavior (revealing
            // the tab bar) still applies.
            .overlay(alignment: .leading) {
                heroEdgeCatcher(.previousEdge(item.id), isEnabled: isActive && activeIndex > 0)
                    .offset(x: -heroEdgeCatcherOffset)
            }
            .overlay(alignment: .trailing) {
                heroEdgeCatcher(.nextEdge(item.id), isEnabled: isActive && heroItems.count > 1)
                    .offset(x: heroEdgeCatcherOffset)
            }
            #endif
            .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
            .padding(.top, 4)
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .foregroundStyle(.white)
        .frame(maxWidth: heroContentMaxWidth, alignment: heroFrameAlignment)
        .padding(.horizontal, heroHorizontalPadding)
        .padding(.bottom, heroBottomPadding)
        .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
        .compositingGroup()
        .opacity(isActive ? 1 : 0)
    }

    private func heroMetadata(for item: SeerrMediaItem) -> some View {
        HStack(spacing: 8) {
            Text(item.mediaType == "tv" ? "TV Show" : "Movie")
            if let year = item.year {
                Text("·")
                Text(year)
            }
            if let rating = item.voteAverage, rating > 0 {
                Text("·")
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                    Text(String(format: "%.1f", rating))
                }
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white.opacity(0.82))
        .frame(maxWidth: .infinity, alignment: heroFrameAlignment)
    }

    private func isHeroMarked(_ item: SeerrMediaItem) -> Bool {
        heroFavoriteStates[item.id] ?? false
    }

    private func isHeroFavoriteEnabled(_ item: SeerrMediaItem) -> Bool {
        guard !heroFavoriteActionsInFlight.contains(item.id) else { return false }
        guard item.canResolveHeroFavorite, jellyfinService.hasCredentials else { return false }
        return true
    }

    private func toggleHeroMarker(for item: SeerrMediaItem) {
        resetAutoAdvanceTimer()

        guard !heroFavoriteActionsInFlight.contains(item.id) else { return }
        guard jellyfinService.hasCredentials else {
            notificationCenter.show(LureBannerItem(
                title: "Jellyfin Not Connected",
                message: "Connect Jellyfin in Settings to manage favorites.",
                style: .info
            ))
            return
        }
        guard item.canResolveHeroFavorite else {
            notificationCenter.show(LureBannerItem(
                title: "Not in Your Library Yet",
                message: "Favorites become available when this title is added to Jellyfin.",
                style: .info
            ))
            return
        }

        Task { @MainActor in
            heroFavoriteActionsInFlight.insert(item.id)
            defer { heroFavoriteActionsInFlight.remove(item.id) }

            do {
                guard let itemID = try await resolveHeroFavoriteItemID(for: item) else {
                    throw JellyfinError.itemNotFound
                }
                guard let client = jellyfinService.client else {
                    throw JellyfinError.noCredentials
                }

                let newValue = !isHeroMarked(item)
                if newValue {
                    try await client.addFavorite(itemId: itemID)
                } else {
                    try await client.removeFavorite(itemId: itemID)
                }

                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    heroFavoriteStates[item.id] = newValue
                }
                // Confirmation lives in the button itself: it stretches into
                // an "Added" pill and springs back, instead of a banner.
                // (The button stays disabled via the in-flight set while the
                // pill is up, which also debounces double-taps.)
                if newValue {
                    heroAddedConfirmationItemIDs.insert(item.id)
                    try? await Task.sleep(for: .seconds(1.4))
                    heroAddedConfirmationItemIDs.remove(item.id)
                }
            } catch {
                notificationCenter.show(LureBannerItem(
                    title: "Favorites Update Failed",
                    message: error.localizedDescription,
                    style: .error
                ))
            }
        }
    }

    private func resetAutoAdvanceTimer() {
        autoAdvanceResetToken &+= 1
    }

    #if os(tvOS)
    private func heroEdgeCatcher(_ target: HeroFocusTarget, isEnabled: Bool) -> some View {
        Color.clear
            .frame(width: 40, height: 52)
            .focusable(isEnabled)
            .focused($heroFocus, equals: target)
            .accessibilityHidden(true)
    }

    /// Treats focus landing on an edge catcher as a swipe past the end of the
    /// action row and pages the carousel. Focus arriving on a catcher from
    /// anywhere other than this row's own buttons (e.g. swiping up from a shelf
    /// below) is bounced to the Details button without paging.
    private func handleHeroFocusChange(from oldValue: HeroFocusTarget?, to newValue: HeroFocusTarget?) {
        resetAutoAdvanceTimer()

        guard let newValue, newValue.isEdgeCatcher else { return }

        guard let oldValue, !oldValue.isEdgeCatcher, oldValue.itemID == newValue.itemID else {
            heroFocus = .details(newValue.itemID)
            return
        }

        if case .nextEdge = newValue {
            moveCarousel(by: 1, wraps: true, resetsTimer: true)
        } else {
            moveCarousel(by: -1, wraps: false, resetsTimer: true)
        }
        // Intentionally leave focus resolution to tvOS after paging. Explicitly
        // assigning the incoming panel's Details target here made the carousel's
        // scrolling unstable. Revisit only with a scroll-aware focus strategy.
    }
    #endif

    private func synopsis(for item: SeerrMediaItem) -> String? {
        let overview: String?
        switch item {
        case .movie(let movie):
            overview = movie.overview
        case .tv(let show):
            overview = show.overview
        case .person:
            overview = nil
        }
        let trimmed = overview?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    @MainActor
    private func loadHeroFavoriteStates() async {
        guard jellyfinService.hasCredentials else {
            heroFavoriteStates = [:]
            heroFavoriteItemIDs = [:]
            heroFavoriteActionsInFlight = []
            return
        }

        var states = heroFavoriteStates
        var itemIDs = heroFavoriteItemIDs

        for item in heroItems where item.canResolveHeroFavorite {
            guard let itemID = try? await resolveHeroFavoriteItemID(for: item) else { continue }
            itemIDs[item.id] = itemID

            guard let client = jellyfinService.client,
                  let jellyfinItem = try? await client.getItem(itemId: itemID)
            else { continue }

            states[item.id] = jellyfinItem.userData?.isFavorite == true
        }

        let currentIDs = Set(heroItems.map(\.id))
        heroFavoriteItemIDs = itemIDs.filter { currentIDs.contains($0.key) }
        heroFavoriteStates = states.filter { currentIDs.contains($0.key) }
    }

    @MainActor
    private func resolveHeroFavoriteItemID(for item: SeerrMediaItem) async throws -> String? {
        if let cached = heroFavoriteItemIDs[item.id] {
            return cached
        }

        guard item.canResolveHeroFavorite else { return nil }
        guard let itemID = try await jellyfinService.findItemId(
            serviceUrl: item.mediaInfo?.serviceUrl,
            tmdbId: item.tmdbId,
            mediaType: item.mediaType,
            title: item.title,
            releaseYear: item.year.flatMap(Int.init)
        ) else {
            return nil
        }

        heroFavoriteItemIDs[item.id] = itemID
        return itemID
    }

    private static func backdropURL(for item: SeerrMediaItem) -> URL? {
        switch item {
        case .movie(let movie):
            movie.backdropURL
        case .tv(let show):
            show.backdropURL
        case .person:
            nil
        }
    }

    /// The fast, sized variant. On tvOS the hero renders progressively:
    /// this loads first, then `heroImageHighResURL` (TMDB original, up to
    /// 4K) crossfades in over it.
    private func heroImageURL(for item: SeerrMediaItem) -> URL? {
        artworkByItemID[item.id]?.backdropURL
            ?? Self.backdropURL(for: item)
            ?? item.posterURL
    }

    #if os(tvOS)
    private func heroImageHighResURL(for item: SeerrMediaItem) -> URL? {
        ImageURL.originalTMDBImageURL(heroImageURL(for: item))
    }
    #endif

    private func preloadHeroImages() async {
        let urls = heroItems.flatMap { item -> [URL] in
            var itemURLs = [
                heroImageURL(for: item),
                artworkByItemID[item.id]?.logoURL,
                item.posterURL
            ]
            #if os(tvOS)
            // Warm the 4K originals too so the progressive upgrade usually
            // lands before the panel is even looked at.
            itemURLs.append(heroImageHighResURL(for: item))
            #endif
            return itemURLs.compactMap(\.self)
        }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await LureImageCache.shared.imageData(for: url)
                }
            }
        }
    }

    @MainActor
    private func loadHeroArtwork() async {
        var resolved = artworkByItemID

        await withTaskGroup(of: (String, MediaArtwork).self) { group in
            for item in heroItems {
                let id = item.id
                let mediaType = item.mediaType
                let tmdbId = item.tmdbId
                let fallbackBackdropURL = Self.backdropURL(for: item)
                let fallbackPosterURL = item.posterURL

                group.addTask {
                    let artwork = await MediaArtworkService.shared.artwork(
                        mediaType: mediaType,
                        tmdbId: tmdbId,
                        fallbackBackdropURL: fallbackBackdropURL,
                        fallbackPosterURL: fallbackPosterURL
                    )
                    return (id, artwork)
                }
            }

            for await (id, artwork) in group {
                resolved[id] = artwork
            }
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            artworkByItemID = resolved.filter { pair in
                heroItems.contains(where: { $0.id == pair.key })
            }
        }
    }

    /// Re-assert the saved scroll position. When the carousel is re-added after a
    /// navigation pop, the underlying `ScrollView` snaps back to offset 0 while the
    /// bound id stays unchanged, so `.scrollPosition(id:)` never re-applies it.
    /// Bouncing the binding through `nil` forces the scroll view back to the item
    /// the user last had open.
    @MainActor
    private func restoreScrollPosition() {
        #if os(tvOS)
        return
        #else
        guard let target = scrollTargetID,
              heroItems.contains(where: { $0.id == target }) else { return }

        // When the carousel is re-added after a pop, the ScrollView resets its
        // offset to 0 and `.scrollPosition(id:)` writes that back into the bound
        // id — clobbering the saved item. The exact frame that happens on is
        // non-deterministic, so re-assert the target across several frames
        // (bouncing through nil each time so the position actually re-applies)
        // to reliably win that race. If the position is already correct these
        // bounces are no-ops, so there's no visible flicker.
        Task { @MainActor in
            for _ in 0..<5 {
                scrollTargetID = nil
                try? await Task.sleep(for: .milliseconds(40))
                scrollTargetID = target
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
        #endif
    }

    @MainActor
    private func syncCarouselSelection() {
        if let scrollTargetID,
           let currentIndex = heroItems.firstIndex(where: { $0.id == scrollTargetID }) {
            activeIndex = currentIndex
            return
        }

        activeIndex = 0
        scrollTargetID = heroItems.first?.id
    }

    @MainActor
    private func autoAdvanceCarousel() async {
        guard heroItems.count > 1, !reduceMotion else { return }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, isActive, scrollPhase == .idle else { continue }

            moveCarousel(by: 1, wraps: true, resetsTimer: false)
        }
    }

    @MainActor
    private func moveCarousel(by offset: Int, wraps: Bool, resetsTimer: Bool) {
        guard heroItems.count > 1 else { return }
        if resetsTimer {
            resetAutoAdvanceTimer()
        }

        let currentIndex = scrollTargetID.flatMap { id in
            heroItems.firstIndex(where: { $0.id == id })
        } ?? activeIndex
        let proposedIndex = currentIndex + offset
        let targetIndex: Int
        if wraps {
            targetIndex = (proposedIndex % heroItems.count + heroItems.count) % heroItems.count
        } else {
            targetIndex = min(max(proposedIndex, 0), heroItems.count - 1)
        }

        setCarouselIndex(targetIndex, currentIndex: currentIndex)
    }

    @MainActor
    private func setCarouselIndex(_ targetIndex: Int, currentIndex: Int? = nil) {
        guard heroItems.indices.contains(targetIndex) else { return }
        let resolvedCurrentIndex = currentIndex ?? activeIndex
        guard targetIndex != resolvedCurrentIndex || scrollTargetID != heroItems[targetIndex].id else { return }
        withAnimation(.smooth(duration: 0.45)) {
            #if !os(tvOS)
            activeIndex = targetIndex
            #endif
            scrollTargetID = heroItems[targetIndex].id
        }
    }

    private func accessibilityLabel(for item: SeerrMediaItem) -> String {
        var components = [item.title, item.mediaType == "tv" ? "TV Show" : "Movie"]
        if let year = item.year {
            components.append(year)
        }
        return components.joined(separator: ", ")
    }

    private var heroCarouselFullBleed: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    private var heroButtonSpacing: CGFloat { 12 }

    // Non-tvOS metrics; the tvOS row uses the shared TVHeroCapsuleLabel /
    // TVHeroCircleIconLabel so it always matches the detail heroes 1:1.
    private var heroButtonFont: Font { .subheadline.weight(.semibold) }
    private var heroButtonHorizontalPadding: CGFloat { 22 }
    private var heroButtonHeight: CGFloat { 42 }
    private var heroSecondaryButtonIconFont: Font { .title3.weight(.semibold) }
    private var heroSecondaryButtonSize: CGFloat { 44 }

    private var carouselHeight: CGFloat {
        #if os(macOS)
        guard containerWidth > 0 else { return 540 }
        return min(max(containerWidth * 0.48, 420), 640)
        #elseif os(tvOS)
        // tvOS canvas is 1920×1080; hero fills ~90% of screen height
        guard containerWidth > 0 else { return 960 }
        return min(max(containerWidth * 0.552, 720), 1032)
        #else
        // iPhone windows are always narrow, so the hero stays effectively
        // fixed. iPad (and visionOS) windows can be resized well below their
        // full-screen width via Split View or Stage Manager, so scale the
        // hero down with the container instead of letting a height tuned for
        // a full-screen iPad swallow a crushed one. Keyed on device idiom
        // rather than horizontalSizeClass, since the size class boundary
        // itself shifts as the window is resized and would otherwise leave
        // a range of shrunk-but-not-tiny widths where nothing scales down.
        guard containerWidth > 0 else {
            return horizontalSizeClass == .compact ? 610 : 740
        }
        if UIDevice.current.userInterfaceIdiom == .phone {
            return min(610, max(320, containerWidth * 1.65))
        }
        return min(740, max(320, containerWidth))
        #endif
    }

    private var heroContentAlignment: HorizontalAlignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var heroFrameAlignment: Alignment {
        #if os(macOS)
        .leading
        #elseif os(tvOS)
        .leading
        #else
        .center
        #endif
    }

    private var heroContentMaxWidth: CGFloat {
        #if os(macOS)
        500
        #elseif os(tvOS)
        900
        #else
        520
        #endif
    }

    private var heroTitleMaxWidth: CGFloat {
        #if os(macOS)
        heroContentMaxWidth * 0.7
        #elseif os(tvOS)
        800
        #else
        430
        #endif
    }

    private var heroLogoMaxHeight: CGFloat {
        #if os(macOS)
        73
        #elseif os(tvOS)
        180
        #else
        132
        #endif
    }

    private var heroHorizontalPadding: CGFloat {
        #if os(macOS)
        56
        #elseif os(tvOS)
        90
        #else
        28
        #endif
    }

    private var heroBottomPadding: CGFloat {
        #if os(macOS)
        68
        #elseif os(tvOS)
        80
        #else
        58
        #endif
    }
}

private extension SeerrMediaItem {
    var canResolveHeroFavorite: Bool {
        switch self {
        case .movie(let movie):
            movie.mediaInfo?.isAvailable == true
        case .tv(let show):
            show.mediaInfo?.hasPlayableTVContent == true
        case .person:
            false
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview("Discover Hero Carousel") {
    @Previewable @State var activeIndex = 0
    @Previewable @State var scrollTarget: String? = PreviewSupport.sampleItems.first?.id

    NavigationStack {
        ScrollView {
            DiscoverHeroCarouselView(
                items: PreviewSupport.sampleItems,
                activeIndex: $activeIndex,
                scrollTargetID: $scrollTarget
            )
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
    }
    .environment(PreviewSupport.jellyfinService)
    .environment(PreviewSupport.notificationCenter)
}

#Preview("Discover Hero Carousel — Single Item") {
    @Previewable @State var activeIndex = 0
    @Previewable @State var scrollTarget: String? = nil

    NavigationStack {
        ScrollView {
            DiscoverHeroCarouselView(
                items: [PreviewSupport.movieItem()],
                activeIndex: $activeIndex,
                scrollTargetID: $scrollTarget
            )
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
    }
    .environment(PreviewSupport.jellyfinService)
    .environment(PreviewSupport.notificationCenter)
}

#if os(tvOS)
/// Static tvOS hero panel preview — bypasses the AppleTVCarousel GeometryReader
/// so the layout and title overlay are always visible in Xcode previews.
#Preview("Discover Hero Carousel — Static Panel (tvOS)") {
    HeroCarouselStaticPreview()
}

private struct HeroCarouselStaticPreview: View {
    private let item = PreviewSupport.movieItem()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Placeholder background (simulates artwork loading)
            Rectangle()
                .fill(.linearGradient(
                    colors: [.indigo, .purple.opacity(0.8), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            LinearGradient(
                colors: [.clear, .black.opacity(0.28), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content overlay (mirrors bottomContent layout)
            VStack(alignment: .leading, spacing: 10) {
                HeroTitleArtworkView(
                    title: item.title,
                    logoURL: nil,
                    maxWidth: 800,
                    maxLogoHeight: 180,
                    horizontalAlignment: .leading
                )

                HStack(spacing: 8) {
                    Text(item.mediaType == "tv" ? "TV Show" : "Movie")
                    if let year = item.year {
                        Text("·")
                        Text(year)
                    }
                    if let rating = item.voteAverage, rating > 0 {
                        Text("·")
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))

                Text("A ticking-time-bomb insomniac and a slippery soap salesman channel primal male aggression into a shocking new form of therapy.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    TVHeroCapsuleLabel(title: "Details", systemImage: "info.circle.fill")
                    TVHeroCircleIconLabel(systemImage: "plus")
                    TVHeroCircleIconLabel(systemImage: "chevron.right")
                }
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 90)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 800)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}
#endif

#if DEBUG && os(iOS)
#Preview("Discover Hero Carousel — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    @Previewable @State var activeIndex = 0
    @Previewable @State var scrollTarget = PreviewSupport.sampleItems.first?.id

    NavigationStack {
        ScrollView {
            DiscoverHeroCarouselView(
                items: PreviewSupport.sampleItems,
                activeIndex: $activeIndex,
                scrollTargetID: $scrollTarget
            )
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.black)
    }
    .environment(PreviewSupport.jellyfinService)
    .environment(PreviewSupport.notificationCenter)
}
#endif
#endif
