import Foundation

final class HistoryStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("YTDLPGUI", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.fileURL = appSupport.appendingPathComponent("history.json")
        }

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [DownloadJob] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        return (try? decoder.decode([DownloadJob].self, from: data)) ?? []
    }

    func save(_ jobs: [DownloadJob]) throws {
        let data = try encoder.encode(jobs)
        try data.write(to: fileURL, options: .atomic)
    }
}
