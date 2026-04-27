import SwiftUI
import UIKit

private enum PosterImageCache {
    static let shared = NSCache<NSURL, UIImage>()
}

struct PosterImage: View {
    let url: URL?
    var width: CGFloat = 120
    var height: CGFloat = 180
    var cornerRadius: CGFloat = 10

    @State private var cachedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let cachedImage {
                Image(uiImage: cachedImage)
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

        if let image = PosterImageCache.shared.object(forKey: url as NSURL) {
            cachedImage = image
            isLoading = false
            return
        }

        cachedImage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            PosterImageCache.shared.setObject(image, forKey: url as NSURL)
            withAnimation(.easeInOut(duration: 0.2)) {
                cachedImage = image
            }
        } catch {
            return
        }
    }
}
