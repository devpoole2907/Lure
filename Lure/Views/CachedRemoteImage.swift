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
    var alignment: Alignment = .center
    var trimsTransparentPadding: Bool = false
    @ViewBuilder var placeholder: Placeholder

    @State private var image: RemotePlatformImage?
    @State private var loadedRequest: ImageRequest?

    var body: some View {
        Group {
            if let image {
                remoteImage(image)
            } else {
                placeholder
            }
        }
        .task(id: ImageRequest(url: url, trimsTransparentPadding: trimsTransparentPadding)) {
            await load()
        }
    }

    @MainActor
    private func load() async {
        let request = ImageRequest(url: url, trimsTransparentPadding: trimsTransparentPadding)
        guard let url else {
            image = nil
            loadedRequest = request
            return
        }

        if loadedRequest != request {
            image = nil
        }

        do {
            let data = try await LureImageCache.shared.imageData(for: url)
            let decodedImage = await Task.detached(priority: .userInitiated) { () -> RemotePlatformImage? in
                guard let image = RemotePlatformImage(data: data) else { return nil }
                guard trimsTransparentPadding else { return image }
                return image.trimmingTransparentPadding() ?? image
            }.value
            guard let decodedImage else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                image = decodedImage
                loadedRequest = request
            }
        } catch is CancellationError {
            return
        } catch {
            image = nil
        }
    }

    @ViewBuilder
    private func remoteImage(_ image: RemotePlatformImage) -> some View {
        switch contentMode {
        case .fit:
            GeometryReader { proxy in
                let fittedSize = image.size.fitted(in: proxy.size)
                Image(remotePlatformImage: image)
                    .resizable()
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: alignment)
            }
            .transition(.opacity)
        case .fill:
            Image(remotePlatformImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .transition(.opacity)
        }
    }
}

private struct ImageRequest: Hashable {
    let url: URL?
    let trimsTransparentPadding: Bool
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

private extension CGSize {
    func fitted(in containerSize: CGSize) -> CGSize {
        guard width > 0,
              height > 0,
              containerSize.width > 0,
              containerSize.height > 0
        else {
            return containerSize
        }

        let scale = min(containerSize.width / width, containerSize.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

#if canImport(UIKit)
private extension UIImage {
    func trimmingTransparentPadding(alphaThreshold: UInt8 = 3) -> UIImage? {
        guard let cgImage,
              let trimRect = transparentContentRect(in: cgImage, alphaThreshold: alphaThreshold),
              let cropped = cgImage.cropping(to: trimRect)
        else {
            return nil
        }

        guard trimRect.width < CGFloat(cgImage.width) || trimRect.height < CGFloat(cgImage.height) else {
            return self
        }

        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
#elseif canImport(AppKit)
private extension NSImage {
    func trimmingTransparentPadding(alphaThreshold: UInt8 = 3) -> NSImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let trimRect = transparentContentRect(in: cgImage, alphaThreshold: alphaThreshold),
              let cropped = cgImage.cropping(to: trimRect)
        else {
            return nil
        }

        guard trimRect.width < CGFloat(cgImage.width) || trimRect.height < CGFloat(cgImage.height) else {
            return self
        }

        let croppedSize = CGSize(
            width: size.width * trimRect.width / CGFloat(cgImage.width),
            height: size.height * trimRect.height / CGFloat(cgImage.height)
        )
        return NSImage(cgImage: cropped, size: croppedSize)
    }
}
#endif

private func transparentContentRect(in image: CGImage, alphaThreshold: UInt8) -> CGRect? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        return nil
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
        let rowStart = y * bytesPerRow
        for x in 0..<width {
            let alpha = pixels[rowStart + x * bytesPerPixel + 3]
            guard alpha > alphaThreshold else { continue }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

#if DEBUG && os(iOS)
#Preview("Cached Remote Image — iPadOS", traits: .fixedLayout(width: 1024, height: 1366)) {
    CachedRemoteImage(url: nil, contentMode: .fit) {
        ContentUnavailableView(
            "Artwork unavailable",
            systemImage: "photo",
            description: Text("The placeholder remains visible until artwork loads.")
        )
    }
    .frame(width: 420, height: 280)
    .padding()
}
#endif
