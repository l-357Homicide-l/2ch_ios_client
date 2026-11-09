//
//  ImageCacheManager.swift
//  Makaba
//
//  Bounded two-tier (LRU Memory + Disk) image caching and downsampling pipeline.
//

import UIKit
import ImageIO
import CryptoKit

/// Thread-safe image caching and downsampling engine.
public final class ImageCacheManager: @unchecked Sendable {
    public static let shared = ImageCacheManager()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    private let ioQueue = DispatchQueue(label: "org.makaba.imagecache.io", qos: .utility)
    private let lock = NSLock()
    private var inFlightTasks: [URL: Task<UIImage?, Never>] = [:]

    // Disk limit: 200 MB
    private let maxDiskBytes: Int64 = 200 * 1024 * 1024
    // Memory limit: 80 MB, max 150 images
    private let maxMemoryCost: Int = 80 * 1024 * 1024
    private let maxMemoryCount: Int = 150

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheURL = caches.appendingPathComponent("MakabaImageCache", isDirectory: true)

        if !fileManager.fileExists(atPath: diskCacheURL.path) {
            try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
        }

        memoryCache.totalCostLimit = maxMemoryCost
        memoryCache.countLimit = maxMemoryCount

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc public func clearMemoryCache() {
        lock.lock()
        memoryCache.removeAllObjects()
        lock.unlock()
    }

    /// Synchronous memory cache lookup to prevent view flicker during list scroll.
    public func memoryImage(for url: URL) -> UIImage? {
        return memoryCache.object(forKey: url as NSURL)
    }

    /// Asynchronously retrieves, downsamples, and caches an image from memory, disk, or remote network.
    public func image(for url: URL, targetSize: CGSize? = nil) async -> UIImage? {
        // 1. Check memory cache
        if let memHit = memoryImage(for: url) {
            return memHit
        }

        // 2. In-flight request deduplication
        lock.lock()
        if let existingTask = inFlightTasks[url] {
            lock.unlock()
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> { [weak self] () -> UIImage? in
            guard let self = self else { return nil }
            return await self.loadAndProcessImage(for: url, targetSize: targetSize)
        }
        inFlightTasks[url] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        inFlightTasks.removeValue(forKey: url)
        lock.unlock()

        return result
    }

    private func loadAndProcessImage(for url: URL, targetSize: CGSize?) async -> UIImage? {
        let diskPath = diskFilePath(for: url)

        // Check disk cache
        if fileManager.fileExists(atPath: diskPath.path),
           let diskData = try? Data(contentsOf: diskPath) {
            // Update last access timestamp for LRU disk pruning
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: diskPath.path)
            if let img = decodeAndDownsample(data: diskData, targetSize: targetSize) {
                storeInMemory(image: img, for: url)
                return img
            }
        }

        // Download from network
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            // Persist raw bytes to disk
            ioQueue.async { [weak self] in
                guard let self = self else { return }
                try? data.write(to: diskPath, options: .atomic)
                self.pruneDiskCacheIfNeeded()
            }

            if let img = decodeAndDownsample(data: data, targetSize: targetSize) {
                storeInMemory(image: img, for: url)
                return img
            }
        } catch {
            return nil
        }

        return nil
    }

    private func storeInMemory(image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private func diskFilePath(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
        return diskCacheURL.appendingPathComponent(hashString)
    }

    /// Memory-efficient downsampling via ImageIO without loading full bitmap into memory.
    private func decodeAndDownsample(data: Data, targetSize: CGSize?) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        guard let targetSize = targetSize, targetSize.width > 0, targetSize.height > 0 else {
            return UIImage(data: data)
        }

        let maxDimension = max(targetSize.width, targetSize.height) * UIScreen.main.scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension)
        ]

        if let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
            return UIImage(cgImage: downsampledImage)
        }

        return UIImage(data: data)
    }

    /// Removes oldest disk cache files when total directory size exceeds maxDiskBytes.
    private func pruneDiskCacheIfNeeded() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: diskCacheURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        var totalSize: Int64 = 0
        var files: [(url: URL, size: Int64, date: Date)] = []

        for fileURL in contents {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.contentModificationDate ?? Date.distantPast
            totalSize += size
            files.append((url: fileURL, size: size, date: date))
        }

        if totalSize > maxDiskBytes {
            // Sort oldest first
            files.sort { $0.date < $1.date }
            var currentSize = totalSize
            for file in files {
                try? fileManager.removeItem(at: file.url)
                currentSize -= file.size
                if currentSize <= (maxDiskBytes * 3 / 4) { // Prune to 75% watermark
                    break
                }
            }
        }
    }
}
