import SwiftUI
import SwiftData

struct LibraryView: View {
    let apiClient: SeerrAPIClient

    @State private var viewModel: LibraryViewModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(JellyfinService.self) private var jellyfinService
    @Environment(LureRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.libraryPath) {
            Group {
                if let viewModel {
                    LibraryContentView(viewModel: viewModel, apiClient: apiClient)
                } else {
                    ProgressView()
                }
            }
            #if os(tvOS)
            .navigationTitle("")
            #else
            .navigationTitle("Library")
            #endif
            .navigationDestination(for: MediaDestination.self) { destination in
                switch destination.mediaType {
                case "movie":
                    MovieDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        jellyfinService: jellyfinService,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                case "tv":
                    TVDetailView(
                        tmdbId: destination.tmdbId,
                        apiClient: apiClient,
                        jellyfinService: jellyfinService,
                        initialTitle: destination.title,
                        initialPosterURL: destination.posterURL
                    )
                default:
                    Text("Unsupported media type: \(destination.mediaType)")
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

    @MainActor
    private func loadLibraryIfNeeded() async {
        guard viewModel == nil else { return }
        let viewModel = LibraryViewModel(
            apiClient: apiClient,
            jellyfinService: jellyfinService,
            modelContext: modelContext
        )
        self.viewModel = viewModel
        await viewModel.load()
    }
}

#if DEBUG && os(iOS)
#Preview("Library — iPad", traits: .fixedLayout(width: 1024, height: 1366)) {
    LibraryView(apiClient: PreviewSupport.apiClient)
        .environment(PreviewSupport.jellyfinService)
        .environment(PreviewSupport.playerCoordinator)
        .environment(PreviewSupport.notificationCenter)
        .environment(PreviewSupport.requestsCoordinator)
        .modelContainer(OnboardingPreviewSupport.modelContainer)
}
#endif
