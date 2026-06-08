import SwiftUI
import AetherEngine

/// Hosts AetherEngine's video surface inside SwiftUI.
///
/// As of AetherEngine 2.x the engine owns its display surface and attaches the
/// correct layer (`AVPlayerLayer` for the native path, `AVSampleBufferDisplayLayer`
/// for the software path) to an `AetherPlayerView`. `AetherPlayerSurface` is the
/// engine's own `UIViewRepresentable`, which calls `engine.bind(view:)` on creation
/// and detaches on teardown — so we no longer manage `videoLayer` or
/// `onVideoLayerReplaced` ourselves.
struct PlayerLayerView: View {
    let engine: AetherEngine

    var body: some View {
        AetherPlayerSurface(engine: engine)
    }
}
