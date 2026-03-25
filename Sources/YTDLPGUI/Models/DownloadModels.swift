import Foundation

enum MediaPreset: String, CaseIterable, Codable, Identifiable {
    case bestVideo
    case bestAudio
    case mp4Compatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestVideo:
            "Best Video"
        case .bestAudio:
            "Best Audio"
        case .mp4Compatible:
            "MP4 Compatible"
        }
    }

    var summary: String {
        switch self {
        case .bestVideo:
            "Highest quality video and audio available"
        case .bestAudio:
            "Extract audio and convert to MP3"
        case .mp4Compatible:
            "Prefer MP4/M4A for wide compatibility"
        }
    }
}

enum PlaylistMode: String, CaseIterable, Codable, Identifiable {
    case auto
    case singleItem
    case wholePlaylist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            "Auto"
        case .singleItem:
            "Single Item"
        case .wholePlaylist:
            "Whole Playlist"
        }
    }
}

enum BrowserCookieSource: String, CaseIterable, Codable, Identifiable {
    case safari
    case chrome
    case firefox
    case edge
    case brave

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum CookieSource: Codable, Equatable {
    case none
    case browser(BrowserCookieSource)
    case file(path: String)

    var description: String {
        switch self {
        case .none:
            "None"
        case let .browser(browser):
            "Browser: \(browser.title)"
        case let .file(path):
            URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

enum DownloadFailureCategory: String, Codable, CaseIterable {
    case missingTools
    case authentication
    case network
    case filesystem
    case unsupported
    case userCancelled
    case process
}

enum DownloadJobState: Codable, Equatable {
    case queued
    case running
    case completed
    case failed(DownloadFailureCategory)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .running:
            false
        }
    }
}

struct DownloadOptions: Codable, Equatable {
    var includeSubtitles = false
    var embedThumbnail = false
    var writeInfoJSON = false
    var formatOverride: String = ""
    var extraFlags: String = ""
}

struct DownloadRequest: Codable, Equatable {
    var urls: [String]
    var preset: MediaPreset
    var destinationPath: String
    var playlistMode: PlaylistMode
    var cookieSource: CookieSource
    var options: DownloadOptions
}

struct DownloadProgress: Codable, Equatable {
    var fractionCompleted: Double?
    var percentText: String
    var sizeText: String?
    var speedText: String?
    var etaText: String?
}

struct DownloadJob: Identifiable, Codable, Equatable {
    var id: UUID
    var request: DownloadRequest
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var state: DownloadJobState
    var progress: DownloadProgress
    var outputPath: String?
    var detailMessage: String
    var lastOutputLine: String?

    static func queued(from request: DownloadRequest) -> DownloadJob {
        DownloadJob(
            id: UUID(),
            request: request,
            title: request.urls.first ?? "Download",
            createdAt: Date(),
            updatedAt: Date(),
            state: .queued,
            progress: DownloadProgress(fractionCompleted: nil, percentText: "Queued", sizeText: nil, speedText: nil, etaText: nil),
            outputPath: nil,
            detailMessage: request.preset.title,
            lastOutputLine: nil
        )
    }
}
