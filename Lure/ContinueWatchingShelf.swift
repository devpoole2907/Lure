import SwiftUI

struct ContinueWatchingShelf: View {
    let items: [JellyfinItem]
    let jellyfinClient: JellyfinAPIClient?
    let onPlay: (JellyfinItem) -> Void
    let onMarkWatched: (JellyfinItem) async throws -> Void

    @State private var hiddenItemIDs: Set<String> = []
    @State private var destinationsByItemID: [String: MediaDestination] = [:]
    @Environment(InAppNotificationCenter.self) private var notificationCenter

    private var visibleItems: [JellyfinItem] {
        items.filter { item in
            guard let id = item.id else { return true }
            return !hiddenItemIDs.contains(id)
        }
    }

    #if os(tvOS)
    private let wrapRepeatCount = 20
    #endif

    var body: some View {
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                #if os(tvOS)
                // tvOS: plain, non-focusable header — a focusable NavigationLink
                // header renders as a giant full-width white plate when focused.
                // The parent column already sits at the safe-area edge (~90pt
                // absolute), matching the hero text column.
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .foregroundStyle(.secondary)
                    Text("Continue Watching")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                #else
                NavigationLink {
                    ContinueWatchingListView(
                        items: visibleItems,
                        jellyfinClient: jellyfinClient,
                        destinationsByItemID: $destinationsByItemID,
                        onPlay: onPlay,
                        onMarkWatched: markWatched
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .foregroundStyle(.secondary)
                        Text("Continue Watching")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                #endif

                ScrollView(.horizontal, showsIndicators: false) {
                    #if os(tvOS)
                    LazyHStack(alignment: .top, spacing: 40) {
                        let virtualCount = shouldWrapItems ? visibleItems.count * wrapRepeatCount : visibleItems.count
                        ForEach(0..<virtualCount, id: \.self) { virtualIndex in
                            let itemIndex = shouldWrapItems ? virtualIndex % visibleItems.count : virtualIndex
                            let item = visibleItems[itemIndex]
                            ContinueWatchingCard(
                                item: item,
                                jellyfinClient: jellyfinClient,
                                destination: destination(for: item),
                                onPlay: onPlay,
                                onMarkWatched: markWatched
                            )
                            .contextMenu {
                                ContinueWatchingContextMenu(
                                    item: item,
                                    destination: destination(for: item),
                                    onMarkWatched: markWatched
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 90)
                    // Vertical headroom so the focus scale-up never clips.
                    .padding(.vertical, 30)
                    #else
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(visibleItems, id: \.id) { item in
                            ContinueWatchingCard(
                                item: item,
                                jellyfinClient: jellyfinClient,
                                destination: destination(for: item),
                                onPlay: onPlay,
                                onMarkWatched: markWatched
                            )
                            .contextMenu {
                                ContinueWatchingContextMenu(
                                    item: item,
                                    destination: destination(for: item),
                                    onMarkWatched: markWatched
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    #endif
                }
                #if os(tvOS)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                // Bleed past the safe area so the 90pt leading margin measures
                // from the absolute screen edge and trailing content scrolls to
                // the edge; disable clipping so focus scale isn't cut off.
                .scrollClipDisabled()
                .ignoresSafeArea(edges: .horizontal)
                #endif
            }
            .task(id: visibleItems.compactMap(\.id).joined(separator: "|")) {
                destinationsByItemID = await ContinueWatchingDestinationResolver.destinations(
                    for: visibleItems,
                    client: jellyfinClient,
                    existing: destinationsByItemID
                )
            }
        }
    }

    private func destination(for item: JellyfinItem) -> MediaDestination? {
        guard let itemID = item.id else { return nil }
        return destinationsByItemID[itemID]
    }

    private var shouldWrapItems: Bool {
        #if os(tvOS)
        visibleItems.count > 4
        #else
        false
        #endif
    }

    @MainActor
    private func markWatched(_ item: JellyfinItem) async {
        do {
            try await onMarkWatched(item)
            if let itemID = item.id {
                hiddenItemIDs.insert(itemID)
            }
            notificationCenter.show(LureBannerItem(
                title: "Marked Watched",
                message: item.seriesName ?? item.name,
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
}

private struct ContinueWatchingCard: View {
    let item: JellyfinItem
    let jellyfinClient: JellyfinAPIClient?
    let destination: MediaDestination?
    let onPlay: (JellyfinItem) -> Void
    let onMarkWatched: (JellyfinItem) async -> Void

    #if os(tvOS)
    private static let cardWidth: CGFloat = 360
    private static let cardHeight: CGFloat = 202 // 16:9
    #else
    private static let cardWidth: CGFloat = 240
    private static let cardHeight: CGFloat = 135 // 16:9
    #endif

    private var thumbURL: URL? {
        guard let client = jellyfinClient else { return nil }
        // Episodes: prefer series thumb for context, fall back to item primary
        if let seriesId = item.seriesId {
            return client.thumbImageURL(itemId: seriesId)
        }
        guard let id = item.id else { return nil }
        return client.thumbImageURL(itemId: id)
    }

    private var progress: Double {
        guard let ticks = item.userData?.playbackPositionTicks,
              let total = item.runTimeTicks, total > 0 else { return 0 }
        return min(1.0, Double(ticks) / Double(total))
    }

    private var displayTitle: String {
        item.seriesName ?? item.name ?? ""
    }

    var body: some View {
        #if os(tvOS)
        Button {
            onPlay(item)
        } label: {
            cardContent
        }
        .buttonStyle(TVPosterFocusButtonStyle(scale: 1.06))
        .accessibilityLabel(displayTitle)
        .accessibilityHint("Starts playback. Long-press for more actions.")
        #else
        cardContent
            .onTapGesture {
                onPlay(item)
            }
        #endif
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                PosterImage(
                    url: thumbURL,
                    width: Self.cardWidth,
                    height: Self.cardHeight,
                    cornerRadius: 10
                )

                // Bottom gradient, progress, and item actions.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                    HStack(spacing: 8) {
                        if progress > 0 {
                            ProgressView(value: progress)
                                .tint(.red)
                                .scaleEffect(x: 1, y: 0.7)
                        }
                        Spacer(minLength: 0)
                        #if !os(tvOS)
                        // On tvOS the '...' Menu button is suppressed — the context
                        // menu (long-press) surfaces the same actions without adding
                        // a bordered chrome button on top of the card.
                        ContinueWatchingMenuButton(
                            item: item,
                            destination: destination,
                            onMarkWatched: onMarkWatched
                        )
                        .foregroundStyle(.white)
                        #endif
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                    .background(.black.opacity(0.6))
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )

            Text(displayTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: Self.cardWidth, alignment: .leading)

            if let ep = item.episodeLabel {
                Text(ep)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.cardWidth, alignment: .leading)
            }
        }
        .frame(width: Self.cardWidth)
        .contentShape(Rectangle())
    }
}

private struct ContinueWatchingListView: View {
    let items: [JellyfinItem]
    let jellyfinClient: JellyfinAPIClient?
    @Binding var destinationsByItemID: [String: MediaDestination]
    let onPlay: (JellyfinItem) -> Void
    let onMarkWatched: (JellyfinItem) async -> Void

    @State private var hiddenItemIDs: Set<String> = []

    private var visibleItems: [JellyfinItem] {
        items.filter { item in
            guard let id = item.id else { return true }
            return !hiddenItemIDs.contains(id)
        }
    }

    var body: some View {
        List {
            ForEach(visibleItems, id: \.id) { item in
                HStack(spacing: 12) {
                    Button {
                        onPlay(item)
                    } label: {
                        ContinueWatchingRowLabel(item: item, jellyfinClient: jellyfinClient)
                    }
                    .buttonStyle(.plain)

                    ContinueWatchingMenuButton(
                        item: item,
                        destination: destination(for: item),
                        onMarkWatched: markWatched
                    )
                    .foregroundStyle(.secondary)
                }
                .contextMenu {
                    ContinueWatchingContextMenu(
                        item: item,
                        destination: destination(for: item),
                        onMarkWatched: markWatched
                    )
                }
            }
        }
        .listStyle(.plain)
        .lureNavigationTitle("Continue Watching")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: visibleItems.compactMap(\.id).joined(separator: "|")) {
            destinationsByItemID = await ContinueWatchingDestinationResolver.destinations(
                for: visibleItems,
                client: jellyfinClient,
                existing: destinationsByItemID
            )
        }
    }

    private func destination(for item: JellyfinItem) -> MediaDestination? {
        guard let itemID = item.id else { return nil }
        return destinationsByItemID[itemID]
    }

    @MainActor
    private func markWatched(_ item: JellyfinItem) async {
        await onMarkWatched(item)
        if let itemID = item.id {
            hiddenItemIDs.insert(itemID)
        }
    }
}

private struct ContinueWatchingRowLabel: View {
    let item: JellyfinItem
    let jellyfinClient: JellyfinAPIClient?

    private var thumbURL: URL? {
        guard let client = jellyfinClient else { return nil }
        if let seriesId = item.seriesId {
            return client.thumbImageURL(itemId: seriesId, width: 320)
        }
        guard let id = item.id else { return nil }
        return client.thumbImageURL(itemId: id, width: 320)
    }

    private var progress: Double {
        guard let ticks = item.userData?.playbackPositionTicks,
              let total = item.runTimeTicks, total > 0 else { return 0 }
        return min(1.0, Double(ticks) / Double(total))
    }

    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: thumbURL, width: 96, height: 54, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.seriesName ?? item.name ?? "Untitled")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if let episodeLabel = item.episodeLabel {
                    Text(episodeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if progress > 0 {
                    ProgressView(value: progress)
                        .tint(.red)
                        .scaleEffect(x: 1, y: 0.7)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ContinueWatchingMenuButton: View {
    let item: JellyfinItem
    let destination: MediaDestination?
    let onMarkWatched: (JellyfinItem) async -> Void

    var body: some View {
        Menu {
            ContinueWatchingContextMenu(
                item: item,
                destination: destination,
                onMarkWatched: onMarkWatched
            )
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
    }
}

private struct ContinueWatchingContextMenu: View {
    let item: JellyfinItem
    let destination: MediaDestination?
    let onMarkWatched: (JellyfinItem) async -> Void

    var body: some View {
        if let destination {
            NavigationLink(value: destination) {
                Label(destination.mediaType == "tv" ? "Go to Show" : "Go to Movie", systemImage: destination.mediaType == "tv" ? "tv" : "film")
            }
        }

        Button {
            Task { await onMarkWatched(item) }
        } label: {
            Label("Mark as Watched", systemImage: "checkmark.circle")
        }
    }
}

private enum ContinueWatchingDestinationResolver {
    @MainActor
    static func destinations(
        for items: [JellyfinItem],
        client: JellyfinAPIClient?,
        existing: [String: MediaDestination]
    ) async -> [String: MediaDestination] {
        guard let client else { return existing }
        var destinations = existing

        for item in items {
            guard let itemID = item.id, destinations[itemID] == nil else { continue }
            if let directDestination = directDestination(for: item) {
                destinations[itemID] = directDestination
                continue
            }

            guard let seriesId = item.seriesId,
                  let series = try? await client.getItem(itemId: seriesId),
                  let destination = directDestination(for: series, fallbackTitle: item.seriesName) else {
                continue
            }
            destinations[itemID] = destination
        }

        return destinations
    }

    private static func directDestination(for item: JellyfinItem, fallbackTitle: String? = nil) -> MediaDestination? {
        guard let tmdbId = item.tmdbId else { return nil }
        let type = item.type?.lowercased()

        if type == "movie" {
            return MediaDestination(mediaType: "movie", tmdbId: tmdbId, title: item.name, posterURL: nil)
        }

        if type == "series" {
            return MediaDestination(mediaType: "tv", tmdbId: tmdbId, title: item.name ?? fallbackTitle, posterURL: nil)
        }

        return nil
    }
}

#if DEBUG && os(iOS)
#Preview("Continue Watching — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    let items = [
        JellyfinItem(
            id: "episode-1",
            name: "The Signal",
            type: "Episode",
            productionYear: 2026,
            providerIds: nil,
            seriesId: "series-1",
            seriesName: "Northern Lights",
            seasonId: "season-1",
            indexNumber: 3,
            parentIndexNumber: 1,
            userData: JellyfinUserData(
                playbackPositionTicks: 1_620_000_000,
                played: false,
                isFavorite: false
            ),
            runTimeTicks: 3_000_000_000,
            dateCreated: nil,
            communityRating: 8.2,
            overview: nil,
            people: nil,
            imageTags: nil
        ),
        JellyfinItem(
            id: "movie-1",
            name: "The Midnight Signal",
            type: "Movie",
            productionYear: 2025,
            providerIds: ["Tmdb": "550"],
            seriesId: nil,
            seriesName: nil,
            seasonId: nil,
            indexNumber: nil,
            parentIndexNumber: nil,
            userData: JellyfinUserData(
                playbackPositionTicks: 2_400_000_000,
                played: false,
                isFavorite: true
            ),
            runTimeTicks: 6_600_000_000,
            dateCreated: nil,
            communityRating: 7.8,
            overview: nil,
            people: nil,
            imageTags: nil
        )
    ]

    NavigationStack {
        ContinueWatchingShelf(
            items: items,
            jellyfinClient: nil,
            onPlay: { _ in },
            onMarkWatched: { _ in }
        )
        .padding(.vertical)
    }
    .environment(PreviewSupport.notificationCenter)
}
#endif
