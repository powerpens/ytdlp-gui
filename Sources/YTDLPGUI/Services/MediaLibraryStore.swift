import AppKit
import AVFoundation
import Foundation
@preconcurrency import QuickLookThumbnailing

@MainActor
final class MediaLibraryStore: ObservableObject {
    typealias ThumbnailProvider = (URL, CGSize, @escaping (NSImage?) -> Void) -> Void

    @Published private(set) var rootFolderURL: URL
    @Published private(set) var items: [LibraryMediaItem] = []
    @Published private(set) var lastRefreshAt: Date?

    private let fileManager: FileManager
    private let thumbnailCache = NSCache<NSURL, NSImage>()
    private let artworkCache = NSCache<NSURL, NSImage>()
    private let thumbnailProvider: ThumbnailProvider

    init(
        rootFolderURL: URL,
        fileManager: FileManager = .default,
        thumbnailProvider: @escaping ThumbnailProvider = MediaLibraryStore.quickLookThumbnail
    ) {
        self.rootFolderURL = rootFolderURL
        self.fileManager = fileManager
        self.thumbnailProvider = thumbnailProvider
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
        thumbnailCache.removeAllObjects()
        artworkCache.removeAllObjects()

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

            let kind = Self.kind(for: url.pathExtension)
            let extractedMetadata = Self.extractMetadata(for: url, kind: kind)
            if let artworkImage = extractedMetadata.artwork {
                artworkCache.setObject(artworkImage, forKey: url as NSURL)
            }

            return LibraryMediaItem(
                id: url,
                url: url,
                fileName: url.lastPathComponent,
                kind: kind,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                metadata: extractedMetadata.metadata
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

    func loadPreviewImage(
        for item: LibraryMediaItem,
        size: CGSize,
        completion: @escaping (NSImage) -> Void
    ) {
        let cacheKey = item.url as NSURL
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        if let artwork = artworkCache.object(forKey: cacheKey) {
            thumbnailCache.setObject(artwork, forKey: cacheKey)
            completion(artwork)
            return
        }

        guard item.kind == .video else {
            let fallback = icon(for: item)
            thumbnailCache.setObject(fallback, forKey: cacheKey)
            completion(fallback)
            return
        }

        thumbnailProvider(item.url, size) { [weak self] image in
            DispatchQueue.main.async {
                guard let self else { return }

                let resolvedImage = image ?? self.icon(for: item)
                self.thumbnailCache.setObject(resolvedImage, forKey: cacheKey)
                completion(resolvedImage)
            }
        }
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

    private static func extractMetadata(for url: URL, kind: LibraryMediaKind) -> (metadata: LibraryMediaMetadata, artwork: NSImage?) {
        guard kind == .audio || kind == .video else {
            return (LibraryMediaMetadata(), nil)
        }

        let asset = AVURLAsset(url: url)
        let metadata = asset.commonMetadata

        let title = stringValue(forCommonKey: .commonKeyTitle, in: metadata)
        let artist = stringValue(forCommonKey: .commonKeyArtist, in: metadata)
        let album = stringValue(forCommonKey: .commonKeyAlbumName, in: metadata)
        let duration = asset.duration.seconds.isFinite && asset.duration.seconds > 0 ? asset.duration.seconds : nil
        let artwork = artworkImage(from: metadata)

        return (
            LibraryMediaMetadata(
                title: title,
                artist: artist,
                album: album,
                duration: duration
            ),
            artwork
        )
    }

    private static func stringValue(forCommonKey key: AVMetadataKey, in items: [AVMetadataItem]) -> String? {
        items.first(where: { $0.commonKey == key })?.stringValue
    }

    private static func artworkImage(from items: [AVMetadataItem]) -> NSImage? {
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = item.dataValue, let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    nonisolated private static func quickLookThumbnail(
        for url: URL,
        size: CGSize,
        completion: @escaping (NSImage?) -> Void
    ) {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
            completion(thumbnail?.nsImage)
        }
    }
}
