import AppKit
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
