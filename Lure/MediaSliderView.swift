import SwiftUI

struct MediaSliderView: View {
    let title: String?
    var icon: String? = nil
    let items: [SeerrMediaItem]
    let apiClient: SeerrAPIClient
    var transitionNamespace: Namespace.ID? = nil
    var headerValue: DiscoverSectionDestination? = nil

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    if let headerValue {
                        NavigationLink(value: headerValue) {
                            headerLabel(title: title)
                        }
                        .buttonStyle(.plain)
                    } else {
                        headerLabel(title: title)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            let destination = MediaDestination(mediaType: item.mediaType, tmdbId: item.tmdbId, title: item.title, posterURL: item.posterURL)

                            NavigationLink(value: destination) {
                                titleCard(for: item, destination: destination)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .horizontalSoftEdges()
            }
        }
    }

    @ViewBuilder
    private func headerLabel(title: String) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
            Text(title)
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

    @ViewBuilder
    private func titleCard(for item: SeerrMediaItem, destination: MediaDestination) -> some View {
        if let transitionNamespace {
            TitleCardView(item: item)
                .matchedTransitionSource(id: destination, in: transitionNamespace)
        } else {
            TitleCardView(item: item)
        }
    }
}

/// Navigation value for media detail routing
struct MediaDestination: Hashable {
    let mediaType: String
    let tmdbId: Int
    let title: String?
    let posterURL: URL?
}
