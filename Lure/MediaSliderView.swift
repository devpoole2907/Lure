import SwiftUI

struct MediaSliderView: View {
    let title: String?
    var icon: String? = nil
    let items: [SeerrMediaItem]
    let apiClient: SeerrAPIClient
    var transitionNamespace: Namespace.ID? = nil
    var headerValue: DiscoverSectionDestination? = nil

    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator
    private let horizontalBleed: CGFloat = 16

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    if let headerValue {
                        NavigationLink(value: headerValue) {
                            headerLabel(title: title, isNavigable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        headerLabel(title: title, isNavigable: false)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            let destination = MediaDestination(
                                mediaType: item.mediaType,
                                tmdbId: item.tmdbId,
                                title: item.title,
                                posterURL: item.posterURL,
                                sourceID: navigationSourceID(for: item, index: index)
                            )

                            let link = NavigationLink(value: destination) {
                                titleCard(for: item, destination: destination)
                            }
                            .buttonStyle(.plain)

                            if item.hasRequestContextActions {
                                link.contextMenu {
                                    MediaRequestContextMenu(
                                        mediaType: item.mediaType,
                                        tmdbId: item.tmdbId,
                                        title: item.title,
                                        mediaInfo: item.mediaInfo,
                                        isKnownAvailable: item.mediaInfo?.isAvailable == true,
                                        apiClient: apiClient,
                                        notificationCenter: notificationCenter,
                                        requestsCoordinator: requestsCoordinator
                                    )
                                }
                            } else {
                                link
                            }
                        }
                    }
                    .padding(.horizontal, horizontalBleed)
                }
                .padding(.horizontal, -horizontalBleed)
            }
        }
    }

    @ViewBuilder
    private func headerLabel(title: String, isNavigable: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            if isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func titleCard(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        if let transitionNamespace {
            TitleCardView(item: item)
                .matchedTransitionSource(id: destination, in: transitionNamespace)
        } else {
            TitleCardView(item: item)
        }
    }

    private func navigationSourceID(for item: SeerrMediaItem, index: Int) -> String {
        "\(title ?? "media-slider")-\(index)-\(item.id)"
    }
}

/// Navigation value for media detail routing
struct MediaDestination: Hashable {
    let mediaType: String
    let tmdbId: Int
    let title: String?
    let posterURL: URL?
    let sourceID: String

    init(mediaType: String, tmdbId: Int, title: String?, posterURL: URL?, sourceID: String? = nil) {
        self.mediaType = mediaType
        self.tmdbId = tmdbId
        self.title = title
        self.posterURL = posterURL
        self.sourceID = sourceID ?? "\(mediaType)-\(tmdbId)"
    }
}
