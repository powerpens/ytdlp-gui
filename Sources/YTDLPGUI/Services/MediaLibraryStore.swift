import AppKit
import AVFoundation
import Foundation

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var rootFolderURL: URL
    @Published private(set) var items: [LibraryMediaItem] = []
    @Published private(set) var lastRefreshAt: Date?

    private let fileManager: FileManager
    private let thumbnailCache = NSCache<NSURL, NSImage>()

    init(rootFolderURL: URL, fileManager: FileManager = .default) {
        self.rootFolderURL = rootFolderURL
        self.fileManager = fileManager
        ensureRootFolderExists()
        refresh()
    }

    func updateRootFolder(to url: URL) {
        rootFolderURL = url
        ensureRootFolderExists()
        refresh()
    }

    func refresh() {
        ensureRootFolderExists()

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        let enumerator = fileManager.enumerator(
            at: rootFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let urls = (enumerator?.allObjects as? [URL]) ?? []
        items = urls.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: resourceKeys),
                values.isRegularFile == true
            else {
                return nil
            }

            return LibraryMediaItem(
                id: url,
                url: url,
                fileName: url.lastPathComponent,
                kind: Self.kind(for: url.pathExtension),
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            )
        }
        .sorted { lhs, rhs in
            let leftDate = lhs.modifiedAt ?? .distantPast
            let rightDate = rhs.modifiedAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
        }

        lastRefreshAt = Date()
    }

    func open(_ item: LibraryMediaItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: LibraryMediaItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func icon(for item: LibraryMediaItem) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 48, height: 48)
        return icon
    }

    func previewImage(for item: LibraryMediaItem, size: CGSize) async -> NSImage {
        let cacheKey = item.url as NSURL
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        guard item.kind == .video else {
            let fallback = icon(for: item)
            thumbnailCache.setObject(fallback, forKey: cacheKey)
            return fallback
        }

        if let image = Self.generateVideoThumbnail(for: item.url, size: size) {
            thumbnailCache.setObject(image, forKey: cacheKey)
            return image
        }

        let fallback = icon(for: item)
        thumbnailCache.setObject(fallback, forKey: cacheKey)
        return fallback
    }

    private func ensureRootFolderExists() {
        try? fileManager.createDirectory(at: rootFolderURL, withIntermediateDirectories: true)
    }

    private static func kind(for pathExtension: String) -> LibraryMediaKind {
        let ext = pathExtension.lowercased()
        if ["mp4", "mov", "mkv", "webm", "avi", "m4v"].contains(ext) {
            return .video
        }
        if ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"].contains(ext) {
            return .audio
        }
        return .other
    }

    private static func generateVideoThumbnail(for url: URL, size: CGSize) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size

        do {
            let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            return nil
        }
    }
}
