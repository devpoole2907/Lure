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

    var body: some View {
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
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

                ScrollView(.horizontal, showsIndicators: false) {
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
                }
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

    private static let cardWidth: CGFloat = 240
    private static let cardHeight: CGFloat = 135 // 16:9

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
                        ContinueWatchingMenuButton(
                            item: item,
                            destination: destination,
                            onMarkWatched: onMarkWatched
                        )
                        .foregroundStyle(.white)
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
        .onTapGesture {
            onPlay(item)
        }
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
        .navigationTitle("Continue Watching")
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
