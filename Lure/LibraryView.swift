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
            .navigationDestination(for: MediaDestination.self) { destination in
                if destination.mediaType == "movie" {
                    MovieDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                } else {
                    TVDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                }
            }
            .refreshable {
                await viewModel?.refresh()
            }
            .task {
                await loadLibraryIfNeeded()
            }
            .toolbarTitleDisplayMode(.large)
        }
    }

    @MainActor
    private func loadLibraryIfNeeded() async {
        guard viewModel == nil else { return }
        let viewModel = LibraryViewModel(apiClient: apiClient)
        self.viewModel = viewModel
        await viewModel.load()
    }
}
