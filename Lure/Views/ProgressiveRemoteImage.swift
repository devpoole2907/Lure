import SwiftUI
#if canImport(UIKit)
import UIKit
private typealias ProgressivePlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias ProgressivePlatformImage = NSImage
#endif

/// Two-stage remote image: shows `url` (fast, usually already in
/// LureImageCache from a shelf/poster) as soon as it's decoded, then
/// crossfades to `highResURL` once that lands. Built for the tvOS heroes,
/// where TMDB `original` art can be genuine 4K but is a multi-megabyte fetch
/// — waiting on it single-stage leaves the hero on a placeholder, and
/// settling for the sized variant looks soft on a 4K panel.
struct ProgressiveRemoteImage<Placeholder: View>: View {
    let url: URL?
    let highResURL: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: Placeholder

    @State private var lowResImage: ProgressivePlatformImage?
    @State private var highResImage: ProgressivePlatformImage?

    var body: some View {
        Group {
            if let image = highResImage ?? lowResImage {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #else
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                #endif
            } else {
                placeholder
            }
        }
        // Sequential on purpose: the sized variant is the fast path (often a
        // cache hit) and the original only replaces it when ready. The
        // previous images intentionally survive a URL change until their
        // replacements decode, so artwork upgrades don't flash a placeholder.
        .task(id: "\(url?.absoluteString ?? "")|\(highResURL?.absoluteString ?? "")") {
            if let url {
                if let image = await Self.fetchImage(url), !Task.isCancelled {
                    if highResImage == nil {
                        lowResImage = image
                    }
                }
            }
            guard let highResURL, highResURL != url else { return }
            if let image = await Self.fetchImage(highResURL), !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) {
                    highResImage = image
                }
            }
        }
    }

    private static func fetchImage(_ url: URL) async -> ProgressivePlatformImage? {
        guard let data = try? await LureImageCache.shared.imageData(for: url) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ProgressivePlatformImage(data: data)
        }.value
    }
}
