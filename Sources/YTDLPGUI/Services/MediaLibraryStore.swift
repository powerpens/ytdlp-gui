import AppKit
import Foundation
@preconcurrency import AVFoundation
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
    private var metadataRefreshID = UUID()

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
        metadataRefreshID = UUID()

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
            return LibraryMediaItem(
                id: url,
                url: url,
                fileName: url.lastPathComponent,
                kind: kind,
                fileSize: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate,
                metadata: LibraryMediaMetadata()
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
        let refreshID = metadataRefreshID
        let snapshot = items
        Task(priority: .utility) { [weak self] in
            let enrichedItems = await Self.enrichedItems(from: snapshot)

            guard let self, self.metadataRefreshID == refreshID else { return }
            for item in enrichedItems {
                if let artworkImage = item.artwork {
                    self.artworkCache.setObject(artworkImage, forKey: item.item.url as NSURL)
                }
            }
            self.items = enrichedItems.map(\.item)
        }
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

    private static func enrichedItems(from items: [LibraryMediaItem]) async -> [(item: LibraryMediaItem, artwork: NSImage?)] {
        var enriched: [(item: LibraryMediaItem, artwork: NSImage?)] = []
        enriched.reserveCapacity(items.count)

        for item in items {
            let extracted = await extractMetadata(for: item.url, kind: item.kind)
            enriched.append((
                item: LibraryMediaItem(
                    id: item.id,
                    url: item.url,
                    fileName: item.fileName,
                    kind: item.kind,
                    fileSize: item.fileSize,
                    modifiedAt: item.modifiedAt,
                    metadata: extracted.metadata
                ),
                artwork: extracted.artwork
            ))
        }

        return enriched
    }

    private static func extractMetadata(for url: URL, kind: LibraryMediaKind) async -> (metadata: LibraryMediaMetadata, artwork: NSImage?) {
        guard kind == .audio || kind == .video else {
            return (LibraryMediaMetadata(), nil)
        }

        let asset = AVURLAsset(url: url)
        let metadataItems = (try? await asset.load(.commonMetadata)) ?? []
        let durationTime = try? await asset.load(.duration)

        let title = await stringValue(forCommonKey: .commonKeyTitle, in: metadataItems)
        let artist = await stringValue(forCommonKey: .commonKeyArtist, in: metadataItems)
        let album = await stringValue(forCommonKey: .commonKeyAlbumName, in: metadataItems)
        let duration = durationTime?.seconds.isFinite == true && (durationTime?.seconds ?? 0) > 0 ? durationTime?.seconds : nil
        let artwork = await artworkImage(from: metadataItems)

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

    private static func stringValue(forCommonKey key: AVMetadataKey, in items: [AVMetadataItem]) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }) else {
            return nil
        }
        return try? await item.load(.stringValue)
    }

    private static func artworkImage(from items: [AVMetadataItem]) async -> NSImage? {
        for item in items where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue), let image = NSImage(data: data) {
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
