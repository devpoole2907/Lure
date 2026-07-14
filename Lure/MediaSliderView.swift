import SwiftUI

struct MediaSliderView: View {
    let title: String?
    var icon: String? = nil
    let items: [SeerrMediaItem]
    let apiClient: SeerrAPIClient
    var transitionNamespace: Namespace.ID? = nil
    var headerValue: DiscoverSectionDestination? = nil
    var extendsBeyondParentPadding = true
    var onSelect: ((MediaDestination) -> Void)? = nil

    #if os(tvOS)
    private let horizontalBleed: CGFloat = 90
    private let cardSpacing: CGFloat = 40
    /// Virtual repeat factor so shelf rows loop "for ages" with the Siri Remote.
    private let wrapRepeatCount = 20
    #else
    private let horizontalBleed: CGFloat = 16
    private let cardSpacing: CGFloat = 12
    #endif

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let title, !title.isEmpty {
                    #if os(tvOS)
                    // tvOS: shelf headers are plain, non-focusable text. A focusable
                    // NavigationLink header renders as a giant full-width white
                    // plate when focused; deep browsing lives in Search instead.
                    headerLabel(title: title, isNavigable: false)
                    #else
                    if let headerValue {
                        NavigationLink(value: headerValue) {
                            headerLabel(title: title, isNavigable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        headerLabel(title: title, isNavigable: false)
                    }
                    #endif
                }

                shelfRow
            }
        }
    }

    private var shelfRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: cardSpacing) {
                #if os(tvOS)
                // Virtual wrap-around: repeat the item list N times so focus can
                // keep travelling right indefinitely. IDs use the virtual index
                // so each repeated cell stays unique.
                let virtualCount = shouldWrapItems ? items.count * wrapRepeatCount : items.count
                ForEach(0..<virtualCount, id: \.self) { virtualIndex in
                    let itemIndex = shouldWrapItems ? virtualIndex % items.count : virtualIndex
                    cell(for: items[itemIndex], index: virtualIndex)
                }
                #else
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    cell(for: item, index: index)
                }
                #endif
            }
            .padding(.horizontal, rowContentHorizontalPadding)
            #if os(tvOS)
            // Vertical headroom so the focus scale-up never clips.
            .padding(.vertical, 30)
            #endif
        }
        #if os(tvOS)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        // The row bleeds past the tvOS safe area so the leading content margin
        // (90pt) measures from the ABSOLUTE screen edge — matching the hero —
        // and trailing content scrolls all the way to the screen edge.
        .padding(.horizontal, extendsBeyondParentPadding ? -horizontalBleed : 0)
        .scrollClipDisabled()
        .mediaSliderHorizontalSafeAreaBehavior(extendsBeyondParentPadding)
        #else
        .padding(.horizontal, extendsBeyondParentPadding ? -horizontalBleed : 0)
        #endif
    }

    @ViewBuilder
    private func cell(for item: SeerrMediaItem, index: Int) -> some View {
        let destination = MediaDestination(
            mediaType: item.mediaType,
            tmdbId: item.tmdbId,
            title: item.title,
            posterURL: item.posterURL,
            sourceID: navigationSourceID(for: item, index: index)
        )

        MediaSliderCellControl(
            item: item,
            destination: destination,
            apiClient: apiClient,
            transitionNamespace: transitionNamespace,
            onSelect: onSelect
        )
    }

    @ViewBuilder
    private func headerLabel(title: String, isNavigable: Bool) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                #if os(tvOS)
                .font(.title3.bold())
                #else
                .font(.title3)
                .fontWeight(.bold)
                #endif
                .foregroundStyle(.primary)
            if isNavigable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        #if os(tvOS)
        // The parent already sits at the tvOS safe area (~90pt absolute), which
        // matches the hero text column — no extra padding.
        .padding(.horizontal, 0)
        #else
        .padding(.horizontal, 16)
        #endif
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func navigationSourceID(for item: SeerrMediaItem, index: Int) -> String {
        "\(title ?? "media-slider")-\(index)-\(item.id)"
    }

    private var rowContentHorizontalPadding: CGFloat {
        #if os(tvOS)
        extendsBeyondParentPadding ? horizontalBleed : 0
        #else
        horizontalBleed
        #endif
    }

    private var shouldWrapItems: Bool {
        #if os(tvOS)
        items.count > 6
        #else
        false
        #endif
    }
}

#if os(tvOS)
private extension View {
    @ViewBuilder
    func mediaSliderHorizontalSafeAreaBehavior(_ shouldIgnore: Bool) -> some View {
        if shouldIgnore {
            ignoresSafeArea(edges: .horizontal)
        } else {
            self
        }
    }
}
#endif

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

#if DEBUG && os(iOS)
#Preview("Media Slider — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        MediaSliderView(
            title: "Popular Movies",
            icon: "popcorn.fill",
            items: PreviewSupport.sampleItems,
            apiClient: PreviewSupport.apiClient,
            extendsBeyondParentPadding: false
        )
        .padding(.vertical)
    }
    .environment(PreviewSupport.notificationCenter)
    .environment(PreviewSupport.requestsCoordinator)
}
#endif
