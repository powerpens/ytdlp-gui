import Foundation
import Testing
@testable import YTDLPGUI

struct HistoryStoreTests {
    @Test
    func roundTripsHistory() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let store = HistoryStore(fileURL: tempURL)

        let request = DownloadRequest(
            urls: ["https://example.com/video"],
            preset: .mp4Compatible,
            destinationPath: "/tmp",
            playlistMode: .auto,
            cookieSource: .none,
            options: .init()
        )
        let job = DownloadJob(
            id: UUID(),
            request: request,
            title: "Example",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            state: .completed,
            progress: DownloadProgress(fractionCompleted: 1.0, percentText: "100%", sizeText: "55MiB", speedText: nil, etaText: nil),
            outputPath: "/tmp/video.mp4",
            detailMessage: "Completed",
            lastOutputLine: nil
        )

        try store.save([job])
        let loaded = store.load()

        #expect(loaded == [job])
    }
}
