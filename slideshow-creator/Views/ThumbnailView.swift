import SwiftUI
import AppKit
import ImageIO

private enum ThumbnailCacheKey {
    nonisolated static func make(url: URL, maxPixelSize: CGFloat, scale: CGFloat) -> NSString {
        let pixelSize = max(1, Int(ceil(maxPixelSize * max(scale, 1))))
        return "\(url.path)#\(pixelSize)" as NSString
    }
}

private nonisolated(unsafe) let thumbnailMemoryCache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 500
    return cache
}()

private actor ThumbnailPipeline {
    static let shared = ThumbnailPipeline()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {}

    func thumbnail(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) async -> NSImage? {
        let pixelSize = max(1, Int(ceil(maxPixelSize * max(scale, 1))))
        let cacheKey = ThumbnailCacheKey.make(url: url, maxPixelSize: maxPixelSize, scale: scale)

        if let cached = thumbnailMemoryCache.object(forKey: cacheKey) {
            return cached
        }

        let key = cacheKey as String
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<NSImage?, Never>(priority: .userInitiated) {
            Self.makeThumbnail(for: url, maxPixelSize: pixelSize)
        }

        inFlight[key] = task
        let image = await task.value
        if let image {
            thumbnailMemoryCache.setObject(image, forKey: cacheKey)
        }
        inFlight[key] = nil
        return image
    }

    nonisolated private static func makeThumbnail(for url: URL, maxPixelSize: Int) -> NSImage? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceShouldCache: false,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil
            }

            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    let maxPixelSize: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var didFailLoading = false
    @State private var activeRequestKey = ""

    static func cachedThumbnail(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) -> NSImage? {
        let key = ThumbnailCacheKey.make(url: url, maxPixelSize: maxPixelSize, scale: scale)
        return thumbnailMemoryCache.object(forKey: key)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
            } else if didFailLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: cacheRequestKey) {
            let requestKey = cacheRequestKey
            activeRequestKey = requestKey
            image = nil
            didFailLoading = false

            let loadedImage = await ThumbnailPipeline.shared.thumbnail(
                for: url,
                maxPixelSize: maxPixelSize,
                scale: displayScale
            )

            guard !Task.isCancelled, activeRequestKey == requestKey else { return }
            image = loadedImage
            didFailLoading = loadedImage == nil
        }
    }

    private var cacheRequestKey: String {
        "\(url.path)#\(Int(ceil(maxPixelSize)))#\(Int(ceil(displayScale * 100)))"
    }
}
