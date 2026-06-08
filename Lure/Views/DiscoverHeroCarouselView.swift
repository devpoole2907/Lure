import SwiftUI

struct DiscoverHeroCarouselView: View {
    let items: [SeerrMediaItem]
    @Binding var activeIndex: Int
    @Binding var scrollTargetID: String?
    var transitionNamespace: Namespace.ID? = nil
    var verticalOffset: CGFloat = 0
    var isActive: Bool = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPhase: ScrollPhase = .idle

    private var heroItems: [SeerrMediaItem] {
        Array(items.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }.prefix(8))
    }

    var body: some View {
        if !heroItems.isEmpty {
            ZStack(alignment: .bottom) {
                AppleTVCarousel(scrollPositionID: $scrollTargetID) {
                    ForEach(Array(heroItems.enumerated()), id: \.element.id) { index, item in
                        let destination = MediaDestination(
                            mediaType: item.mediaType,
                            tmdbId: item.tmdbId,
                            title: item.title,
                            posterURL: item.posterURL,
                            sourceID: "discover-hero-\(index)-\(item.id)"
                        )

                        NavigationLink(value: destination) {
                            heroPanel(for: item, destination: destination)
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                    }
                } scrollProgress: { progress in
                    activeIndex = min(max(Int(progress.rounded()), 0), heroItems.count - 1)
                }
                .onScrollPhaseChange { _, newPhase in
                    scrollPhase = newPhase
                }

                PageControlView(numberOfPages: heroItems.count, currentPage: activeIndex)
                    .frame(height: 24)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
            }
            .frame(height: carouselHeight + verticalOffset)
            .offset(y: -verticalOffset)
            .onAppear { restoreScrollPosition() }
            .onChange(of: isActive) { _, nowActive in
                if nowActive { restoreScrollPosition() }
            }
            .task(id: heroItems.map(\.id).joined(separator: "|")) {
                syncCarouselSelection()
                await preloadHeroImages()
            }
            .task(id: "\(heroItems.map(\.id).joined(separator: "|"))|\(isActive)") {
                await autoAdvanceCarousel()
            }
        }
    }

    @ViewBuilder
    private func heroPanel(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        if let transitionNamespace {
            panelContent(for: item)
                .matchedTransitionSource(id: destination, in: transitionNamespace)
        } else {
            panelContent(for: item)
        }
    }

    private func panelContent(for item: SeerrMediaItem) -> some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .bottom) {
                heroImage(for: item)
                    .frame(width: size.width, height: size.height)
                    .clipped()

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.28),
                        .black.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                bottomContent(for: item)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: item))
        }
    }

    private func heroImage(for item: SeerrMediaItem) -> some View {
        CachedRemoteImage(url: heroImageURL(for: item), contentMode: .fill) {
            heroPlaceholder(for: item)
        }
    }

    private func heroPlaceholder(for item: SeerrMediaItem) -> some View {
        ZStack {
            Rectangle()
                .fill(.linearGradient(
                    colors: [.black, .indigo.opacity(0.45), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)
        }
    }

    private func bottomContent(for item: SeerrMediaItem) -> some View {
        let isActive = heroItems[safe: activeIndex]?.id == item.id

        return VStack(spacing: 10) {
            Text(item.title)
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

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

            Label("Details", systemImage: "info.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: 42)
                .background(.white, in: Capsule())
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: 520)
        .padding(.horizontal, 28)
        .padding(.bottom, 58)
        .compositingGroup()
        .opacity(isActive ? 1 : 0)
        .animation(isActive ? .linear(duration: 0.18) : .none) { content in
            content.opacity(scrollPhase != .interacting ? 1 : 0)
        }
    }

    private func backdropURL(for item: SeerrMediaItem) -> URL? {
        switch item {
        case .movie(let movie):
            movie.backdropURL
        case .tv(let show):
            show.backdropURL
        case .person:
            nil
        }
    }

    private func heroImageURL(for item: SeerrMediaItem) -> URL? {
        backdropURL(for: item) ?? item.posterURL
    }

    private func preloadHeroImages() async {
        let urls = heroItems.flatMap { item in
            [backdropURL(for: item), item.posterURL].compactMap(\.self)
        }
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await LureImageCache.shared.imageData(for: url)
                }
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
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, isActive, scrollPhase == .idle else { continue }

            let nextIndex = (activeIndex + 1) % heroItems.count
            withAnimation(.smooth(duration: 0.55)) {
                activeIndex = nextIndex
                scrollTargetID = heroItems[nextIndex].id
            }
        }
    }

    private func accessibilityLabel(for item: SeerrMediaItem) -> String {
        var components = [item.title, item.mediaType == "tv" ? "TV Show" : "Movie"]
        if let year = item.year {
            components.append(year)
        }
        return components.joined(separator: ", ")
    }

    private var carouselHeight: CGFloat {
        horizontalSizeClass == .compact ? 610 : 740
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
