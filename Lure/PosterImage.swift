import SwiftUI
import UIKit

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

        isLoading = true
        defer { isLoading = false }

        do {
            let data = try await LureImageCache.shared.imageData(for: url)
            let uiImage = await Task.detached(priority: .userInitiated) {
                UIImage(data: data)
            }.value
            guard let uiImage else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                cachedImage = uiImage
            }
        } catch {
            cachedImage = nil
        }
    }
}
