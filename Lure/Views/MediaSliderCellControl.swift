import SwiftUI

struct MediaSliderCellControl: View {
    let item: SeerrMediaItem
    let destination: MediaDestination
    let apiClient: SeerrAPIClient
    let transitionNamespace: Namespace.ID?
    let onSelect: ((MediaDestination) -> Void)?

    @Environment(InAppNotificationCenter.self) private var notificationCenter
    @Environment(RequestsCoordinator.self) private var requestsCoordinator

    var body: some View {
        if item.hasRequestContextActions {
            control
                .contextMenu {
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
            control
        }
    }

    @ViewBuilder
    private var control: some View {
        #if os(tvOS)
        NavigationLink(value: destination) {
            card
        }
        .buttonStyle(TVPosterFocusButtonStyle())
        #else
        if onSelect != nil {
            Button(action: select) {
                card
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: destination) {
                card
            }
            .buttonStyle(.plain)
        }
        #endif
    }

    @ViewBuilder
    private var card: some View {
        // matchedTransitionSource feeds the iOS/visionOS zoom transition
        // only; on tvOS it flattens the card into a snapshot container that
        // strips the hover effect's rounded shape (focused cards render
        // square-cornered), so it must not wrap cards there.
        #if os(tvOS)
        TitleCardView(item: item)
        #else
        if let transitionNamespace {
            TitleCardView(item: item)
                .matchedTransitionSource(id: destination, in: transitionNamespace)
        } else {
            TitleCardView(item: item)
        }
        #endif
    }

    private func select() {
        onSelect?(destination)
    }
}
