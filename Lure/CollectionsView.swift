import SwiftUI

struct CollectionsView: View {
    let apiClient: SeerrAPIClient
    @State private var viewModel: CollectionsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                collectionsContent(vm: vm)
            } else {
                ProgressView()
            }
        }
        .lureNavigationTitle("Collections")
#if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .refreshable { await viewModel?.refresh() }
        .task {
            if viewModel == nil {
                let vm = CollectionsViewModel(apiClient: apiClient)
                viewModel = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func collectionsContent(vm: CollectionsViewModel) -> some View {
        if vm.isLoading && vm.collections.isEmpty {
            VStack {
                Spacer()
                ProgressView("Loading Collections...")
                Spacer()
            }
        } else if let error = vm.error, vm.collections.isEmpty {
            ContentUnavailableView(
                "Collections Unavailable",
                systemImage: "rectangle.stack.badge.minus",
                description: Text(error)
            )
        } else if vm.collections.isEmpty {
            ContentUnavailableView(
                "No Collections",
                systemImage: "rectangle.stack",
                description: Text("No collections found.")
            )
        } else {
            GeometryReader { proxy in
                let posterWidth = ThreeColumnMediaGrid.posterWidth(for: proxy.size.width)

                ScrollView {
                    LazyVGrid(columns: ThreeColumnMediaGrid.columns(for: proxy.size.width), spacing: ThreeColumnMediaGrid.rowSpacing) {
                        ForEach(vm.collections.indices, id: \.self) { index in
                            NavigationLink(value: vm.collections[index]) {
                                collectionCard(vm.collections[index], posterWidth: posterWidth)
                            }
                            #if os(tvOS)
                            .buttonStyle(TVPosterFocusButtonStyle())
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, ThreeColumnMediaGrid.horizontalPadding)
                    .padding(.vertical, 12)
                }
#if os(macOS)
                .scrollEdgeEffectStyle(.soft, for: .all)
#endif
            }
        }
    }

    private func collectionCard(_ collection: SeerrCollection, posterWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PosterImage(url: collection.posterURL, width: posterWidth, height: posterWidth * 1.5, cornerRadius: 12)
                .posterFocusHighlight(cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name ?? "Unknown Collection")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)

                if let count = collection.parts?.count, count > 0 {
                    Text("\(count) \(count == 1 ? "movie" : "movies")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: posterWidth, alignment: .leading)
            .padding(.top, captionTopPadding)
            .padding(.horizontal, 2)
        }
    }

    /// tvOS needs extra clearance so the focused poster's hover-effect
    /// scale-up doesn't overlap the caption.
    private var captionTopPadding: CGFloat {
        #if os(tvOS)
        22
        #else
        6
        #endif
    }
}

#if DEBUG && os(iOS)
#Preview("Collections — Loading (iPad)", traits: .fixedLayout(width: 1024, height: 1366)) {
    NavigationStack {
        CollectionsView(apiClient: PreviewSupport.apiClient)
    }
}
#endif
