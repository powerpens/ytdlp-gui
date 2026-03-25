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
            modifiedAt: Date()
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
}
