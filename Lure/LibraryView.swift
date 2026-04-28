import SwiftUI

struct LibraryView: View {
    let apiClient: SeerrAPIClient

    @State private var viewModel: LibraryViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    LibraryContentView(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Library")
            .navigationSubtitle(subtitleText(for: viewModel))
            .navigationDestination(for: MediaDestination.self) { destination in
                switch destination.mediaType {
                case "movie":
                    MovieDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                case "tv":
                    TVDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                default:
                    Text("Unsupported media type: \(destination.mediaType)")
                        .onAppear {
                            assertionFailure("Unexpected mediaType in LibraryView: \(destination.mediaType)")
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if let viewModel {
                        Menu {
                            ForEach(LibrarySortOrder.allCases) { order in
                                Button {
                                    withAnimation { viewModel.sortOrder = order }
                                } label: {
                                    if viewModel.sortOrder == order {
                                        Label(order.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(order.rawValue)
                                    }
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    }
                }
            }
            .refreshable {
                await viewModel?.refresh()
            }
            .task {
                await loadLibraryIfNeeded()
            }
#if os(iOS) || os(visionOS)
            .toolbarTitleDisplayMode(.large)
#endif
        }
    }

    private func subtitleText(for viewModel: LibraryViewModel?) -> String {
        guard let vm = viewModel, !vm.isLoading else { return "" }
        let count = vm.items.filter { $0.title != "Unknown" }.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    @MainActor
    private func loadLibraryIfNeeded() async {
        guard viewModel == nil else { return }
        let viewModel = LibraryViewModel(apiClient: apiClient)
        self.viewModel = viewModel
        await viewModel.load()
    }
}
