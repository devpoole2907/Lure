import SwiftUI

/// Full-screen video player. Presented as a `.fullScreenCover`.
///
/// On appear: loads the stream from Jellyfin via `PlayerViewModel.load(…)`.
/// On dismiss: stops the engine and reports playback position to Jellyfin.
struct PlayerView: View {
    @State var vm: PlayerViewModel
    let itemId: String
    let title: String
    let episodeLabel: String?
    let serviceUrl: String?
    let tmdbId: Int?
    let releaseYear: Int?
    let mediaType: String

    @Environment(\.dismiss) private var dismiss
    @State private var hasStartedLoad = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(engine: vm.engine)
                .ignoresSafeArea()

            SubtitleOverlay(vm: vm)
                .ignoresSafeArea()

            TransportOverlay(vm: vm) {
                Task { await stop() }
            }
            .ignoresSafeArea()

            if vm.isBuffering {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            if let error = vm.errorMessage {
                errorView(error)
            }
        }
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear {
            #if DEBUG
            print("[PlayerView] onAppear hasStartedLoad=\(hasStartedLoad) itemId=\(itemId.isEmpty ? "<empty>" : itemId) title=\(title) mediaType=\(mediaType)")
            #endif
            PlayerOrientationController.lockLandscape()
            guard !hasStartedLoad else { return }
            hasStartedLoad = true
            Task {
                await vm.load(
                    itemId: itemId,
                    title: title,
                    episodeLabel: episodeLabel,
                    serviceUrl: serviceUrl,
                    tmdbId: tmdbId,
                    releaseYear: releaseYear,
                    mediaType: mediaType
                )
            }
        }
        .onDisappear {
            PlayerOrientationController.unlock()
        }
    }

    private func stop() async {
        await vm.stop()
        // Rotate back to portrait *before* tearing down the cover, otherwise the
        // detail view underneath flashes in landscape and snaps round afterwards.
        PlayerOrientationController.unlock()
        try? await Task.sleep(for: .milliseconds(350))
        dismiss()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 16) {
                Button("Retry") {
                    Task { await vm.load(
                        itemId: itemId,
                        title: title,
                        episodeLabel: episodeLabel,
                        serviceUrl: serviceUrl,
                        tmdbId: tmdbId,
                        releaseYear: releaseYear,
                        mediaType: mediaType
                    ) }
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button("Close") {
                    Task { await stop() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
