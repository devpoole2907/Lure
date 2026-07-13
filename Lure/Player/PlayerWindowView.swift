import SwiftUI

#if os(macOS)
enum PlayerWindowScene {
    static let id = "player"
}

struct PlayerWindowView: View {
    let media: PlayableMedia

    @Environment(JellyfinService.self) private var jellyfinService
    @State private var vm: PlayerViewModel?
    @State private var errorMessage: String?
    @State private var didStop = false

    var body: some View {
        Group {
            if let vm {
                PlayerView(vm: vm, media: media) {
                    didStop = true
                }
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.yellow)
                    Text(errorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
        .task {
            guard vm == nil, errorMessage == nil else { return }
            do {
                vm = try PlayerViewModel(jellyfinService: jellyfinService)
            } catch {
                errorMessage = "Player failed to start: \(error.localizedDescription)"
            }
        }
        .onDisappear {
            guard !didStop, let vm else { return }
            didStop = true
            Task { await vm.stop() }
        }
    }
}
#endif
