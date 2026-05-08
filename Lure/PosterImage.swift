import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
private typealias PlatformImage = UIImage
#elseif os(macOS)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct PosterImage: View {
    let url: URL?
    var width: CGFloat = 120
    var height: CGFloat = 180
    var cornerRadius: CGFloat = 10

    @State private var cachedImage: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let cachedImage {
                Image(platformImage: cachedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if isLoading, url != nil {
                placeholder.overlay(ProgressView().tint(.secondary))
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            await loadImage()
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "film")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    @MainActor
    private func loadImage() async {
        guard let url else {
            cachedImage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await LureImageCache.shared.imageData(for: url)
            let platformImage = await Task.detached(priority: .userInitiated) {
                PlatformImage(data: data)
            }.value
            guard let platformImage else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                cachedImage = platformImage
            }
        } catch is CancellationError {
            return
        } catch {
            if cachedImage == nil {
                isLoading = false
            }
        }
    }
}

private extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS) || os(visionOS)
        self.init(uiImage: platformImage)
        #elseif os(macOS)
        self.init(nsImage: platformImage)
        #endif
    }
}
