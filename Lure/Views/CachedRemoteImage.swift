import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias RemotePlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias RemotePlatformImage = NSImage
#endif

struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder

    @State private var image: RemotePlatformImage?

    var body: some View {
        Group {
            if let image {
                Image(remotePlatformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        guard let url else {
            image = nil
            return
        }

        do {
            let data = try await LureImageCache.shared.imageData(for: url)
            let decodedImage = await Task.detached(priority: .userInitiated) {
                RemotePlatformImage(data: data)
            }.value
            guard let decodedImage else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                image = decodedImage
            }
        } catch is CancellationError {
            return
        } catch {
            image = nil
        }
    }
}

private extension Image {
    init(remotePlatformImage: RemotePlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: remotePlatformImage)
        #elseif canImport(AppKit)
        self.init(nsImage: remotePlatformImage)
        #endif
    }
}
