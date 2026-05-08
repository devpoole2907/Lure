import CryptoKit
import Foundation
#if os(iOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

actor LureImageCache {
    static let shared = LureImageCache()

    private let fileManager = FileManager.default
    private let memoryCache: NSCache<NSURL, NSData>
    private let cacheDirectoryURL: URL
    private let diskCacheLimit: Int64 = 256 * 1024 * 1024
    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

    init() {
        let fileManager = FileManager.default
        let memoryCache = NSCache<NSURL, NSData>()
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        self.memoryCache = memoryCache
        self.cacheDirectoryURL = cachesDirectory.appendingPathComponent("LurePosterCache", isDirectory: true)

        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 64 * 1_024 * 1_024

        if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func imageData(for url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased() else {
            throw URLError(.unsupportedURL)
        }
        #if DEBUG
        guard scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        #else
        guard scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        #endif

        if let cachedData = memoryCache.object(forKey: url as NSURL) {
            return Data(referencing: cachedData)
        }

        let fileURL = cachedFileURL(for: url)
        if let diskData = try? Data(contentsOf: fileURL), !diskData.isEmpty {
            memoryCache.setObject(diskData as NSData, forKey: url as NSURL, cost: diskData.count)
            try? updateModificationDate(for: fileURL)
            return diskData
        }

        // Check for in-flight task
        if let existingTask = inFlightTasks[url] {
            return try await existingTask.value
        }

        // Create and store new task
        let task = Task<Data, Error> {
            defer { inFlightTasks[url] = nil }

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  !data.isEmpty else {
                throw URLError(.badServerResponse)
            }

            let dataToStore = compressedData(from: data) ?? data

            guard Int64(dataToStore.count) <= diskCacheLimit else {
                return dataToStore
            }

            memoryCache.setObject(dataToStore as NSData, forKey: url as NSURL, cost: dataToStore.count)
            evictIfNecessary(incomingSize: Int64(dataToStore.count))
            try? dataToStore.write(to: fileURL, options: .atomic)
            return dataToStore
        }

        inFlightTasks[url] = task
        return try await task.value
    }

    private func updateModificationDate(for fileURL: URL) throws {
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
    }

    private func evictIfNecessary(incomingSize: Int64) {
        let currentSize = cacheSizeInBytes()
        guard currentSize + incomingSize > diskCacheLimit else { return }

        guard let fileEnumerator = fileManager.enumerator(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        struct CacheEntry {
            let url: URL
            let date: Date
            let size: Int64
        }

        var entries: [CacheEntry] = []
        for case let fileURL as URL in fileEnumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
               let date = values.contentModificationDate,
               let size = values.fileSize {
                entries.append(CacheEntry(url: fileURL, date: date, size: Int64(size)))
            }
        }

        entries.sort { $0.date < $1.date }

        var sizeToFree = (currentSize + incomingSize) - (diskCacheLimit / 2)
        for entry in entries where sizeToFree > 0 {
            try? fileManager.removeItem(at: entry.url)
            sizeToFree -= entry.size
        }
    }

    func cacheSizeInBytes() -> Int64 {
        createCacheDirectoryIfNeeded()

        guard let fileEnumerator = fileManager.enumerator(
            at: cacheDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return 0 }

        var totalSize = 0
        for case let fileURL as URL in fileEnumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  resourceValues.isRegularFile == true,
                  let fileSize = resourceValues.fileSize else { continue }
            totalSize += fileSize
        }
        return Int64(totalSize)
    }

    func clear() {
        for (_, task) in inFlightTasks {
            task.cancel()
        }
        inFlightTasks.removeAll()

        memoryCache.removeAllObjects()
        if fileManager.fileExists(atPath: cacheDirectoryURL.path) {
            try? fileManager.removeItem(at: cacheDirectoryURL)
        }
        createCacheDirectoryIfNeeded()
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let fileName = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("img")
    }

    private func createCacheDirectoryIfNeeded() {
        guard !fileManager.fileExists(atPath: cacheDirectoryURL.path) else { return }
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
    }

    private func compressedData(from data: Data) -> Data? {
        let maxDimension: CGFloat = 800
#if os(iOS) || os(visionOS)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        if scale >= 1.0 {
            return image.jpegData(compressionQuality: 0.75)
        }
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.75)
#elseif os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        if scale >= 1.0 {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        }
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: CGRect(origin: .zero, size: newSize))
        resized.unlockFocus()
        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
#endif
    }
}
