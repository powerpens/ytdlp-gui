import AppKit
import Dispatch
import Foundation
import Testing
@testable import YTDLPGUI

@MainActor
struct MediaLibraryStoreTests {
    @Test
    func deliversThumbnailCallbacksOnMainQueue() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var providerCalls = 0

        let store = MediaLibraryStore(
            rootFolderURL: rootURL,
            thumbnailProvider: { _, _, completion in
                providerCalls += 1
                Thread.detachNewThread {
                    completion(nil)
                }
            }
        )

        let item = LibraryMediaItem(
            id: rootURL.appendingPathComponent("sample.mp4"),
            url: rootURL.appendingPathComponent("sample.mp4"),
            fileName: "sample.mp4",
            kind: .video,
            fileSize: 1_024,
            modifiedAt: Date(),
            metadata: LibraryMediaMetadata()
        )

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.loadPreviewImage(for: item, size: CGSize(width: 160, height: 90)) { image in
                #expect(Thread.isMainThread)
                #expect(image.size.width > 0)
                continuation.resume()
            }
        }

        #expect(providerCalls == 1)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.loadPreviewImage(for: item, size: CGSize(width: 160, height: 90)) { image in
                #expect(Thread.isMainThread)
                #expect(image.size.width > 0)
                continuation.resume()
            }
        }

        #expect(providerCalls == 1)
    }

    @Test
    func prefersMusicMetadataForDisplay() {
        let item = LibraryMediaItem(
            id: URL(fileURLWithPath: "/tmp/test.m4a"),
            url: URL(fileURLWithPath: "/tmp/test.m4a"),
            fileName: "test.m4a",
            kind: .audio,
            fileSize: 2_048,
            modifiedAt: nil,
            metadata: LibraryMediaMetadata(
                title: "Carbonara",
                artist: "Chef Paul",
                album: "Two Headed Chef",
                duration: 182
            )
        )

        #expect(item.displayTitle == "Carbonara")
        #expect(item.secondaryText == "Chef Paul • Two Headed Chef")
        #expect(item.durationText == "03:02")
    }
}
