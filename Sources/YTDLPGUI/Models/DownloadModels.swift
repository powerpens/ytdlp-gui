import Foundation

enum DownloadMode: String, CaseIterable, Codable, Identifiable {
    case video
    case audio
    case spotifyMusic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video:
            "Video"
        case .audio:
            "Audio"
        case .spotifyMusic:
            "Spotify Music"
        }
    }

    var summary: String {
        switch self {
        case .video:
            "Download videos with yt-dlp presets."
        case .audio:
            "Extract audio from supported media URLs."
        case .spotifyMusic:
            "Resolve Spotify tracks, albums, and playlists into tagged music downloads."
        }
    }
}

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

enum MusicFormatPreset: String, CaseIterable, Codable, Identifiable {
    case bestQualityMP3
    case aacM4A
    case keepBestSource

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestQualityMP3:
            "Best Quality MP3"
        case .aacM4A:
            "AAC / M4A"
        case .keepBestSource:
            "Keep Best Source"
        }
    }

    var summary: String {
        switch self {
        case .bestQualityMP3:
            "Convert matched sources to a library-friendly MP3."
        case .aacM4A:
            "Prefer AAC / M4A output for smaller files and good quality."
        case .keepBestSource:
            "Keep the highest-quality source format that spotDL can provide."
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

struct DownloadFailure: Codable, Equatable {
    var category: DownloadFailureCategory
    var summary: String
    var recoverySuggestion: String
    var technicalDetails: String
}

enum DownloadJobState: Codable, Equatable {
    case queued
    case running
    case completed
    case failed(DownloadFailure)
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

struct MusicOptions: Codable, Equatable {
    var embedArtwork = true
    var writeMetadata = true
    var preservePlaylistOrder = true
    var formatPreset: MusicFormatPreset = .bestQualityMP3

    init(
        embedArtwork: Bool = true,
        writeMetadata: Bool = true,
        preservePlaylistOrder: Bool = true,
        formatPreset: MusicFormatPreset = .bestQualityMP3
    ) {
        self.embedArtwork = embedArtwork
        self.writeMetadata = writeMetadata
        self.preservePlaylistOrder = preservePlaylistOrder
        self.formatPreset = formatPreset
    }
}

struct DownloadRequest: Codable, Equatable {
    var mode: DownloadMode
    var urls: [String]
    var preset: MediaPreset
    var destinationPath: String
    var playlistMode: PlaylistMode
    var cookieSource: CookieSource
    var options: DownloadOptions
    var musicOptions: MusicOptions

    init(
        mode: DownloadMode = .video,
        urls: [String],
        preset: MediaPreset,
        destinationPath: String,
        playlistMode: PlaylistMode,
        cookieSource: CookieSource,
        options: DownloadOptions,
        musicOptions: MusicOptions = MusicOptions()
    ) {
        self.mode = mode
        self.urls = urls
        self.preset = preset
        self.destinationPath = destinationPath
        self.playlistMode = playlistMode
        self.cookieSource = cookieSource
        self.options = options
        self.musicOptions = musicOptions
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case urls
        case preset
        case destinationPath
        case playlistMode
        case cookieSource
        case options
        case musicOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(DownloadMode.self, forKey: .mode) ?? .video
        urls = try container.decode([String].self, forKey: .urls)
        preset = try container.decodeIfPresent(MediaPreset.self, forKey: .preset) ?? .bestVideo
        destinationPath = try container.decode(String.self, forKey: .destinationPath)
        playlistMode = try container.decodeIfPresent(PlaylistMode.self, forKey: .playlistMode) ?? .auto
        cookieSource = try container.decodeIfPresent(CookieSource.self, forKey: .cookieSource) ?? .none
        options = try container.decodeIfPresent(DownloadOptions.self, forKey: .options) ?? DownloadOptions()
        musicOptions = try container.decodeIfPresent(MusicOptions.self, forKey: .musicOptions) ?? MusicOptions()
    }
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
    var providerID: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var state: DownloadJobState
    var progress: DownloadProgress
    var outputPath: String?
    var detailMessage: String
    var lastOutputLine: String?
    var currentStage: String?
    var itemCount: Int?

    static func queued(from request: DownloadRequest) -> DownloadJob {
        DownloadJob(
            id: UUID(),
            request: request,
            providerID: request.mode == .spotifyMusic ? "spotdl" : "yt-dlp",
            title: request.urls.first ?? "Download",
            createdAt: Date(),
            updatedAt: Date(),
            state: .queued,
            progress: DownloadProgress(fractionCompleted: nil, percentText: "Queued", sizeText: nil, speedText: nil, etaText: nil),
            outputPath: nil,
            detailMessage: request.mode == .spotifyMusic ? request.musicOptions.formatPreset.title : request.preset.title,
            lastOutputLine: nil,
            currentStage: request.mode == .spotifyMusic ? "Queued for Spotify resolution" : nil,
            itemCount: request.mode == .spotifyMusic ? request.urls.count : nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case request
        case providerID
        case title
        case createdAt
        case updatedAt
        case state
        case progress
        case outputPath
        case detailMessage
        case lastOutputLine
        case currentStage
        case itemCount
    }

    init(
        id: UUID,
        request: DownloadRequest,
        providerID: String = "yt-dlp",
        title: String,
        createdAt: Date,
        updatedAt: Date,
        state: DownloadJobState,
        progress: DownloadProgress,
        outputPath: String?,
        detailMessage: String,
        lastOutputLine: String?,
        currentStage: String? = nil,
        itemCount: Int? = nil
    ) {
        self.id = id
        self.request = request
        self.providerID = providerID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.progress = progress
        self.outputPath = outputPath
        self.detailMessage = detailMessage
        self.lastOutputLine = lastOutputLine
        self.currentStage = currentStage
        self.itemCount = itemCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        request = try container.decode(DownloadRequest.self, forKey: .request)
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID) ?? (request.mode == .spotifyMusic ? "spotdl" : "yt-dlp")
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        state = try container.decode(DownloadJobState.self, forKey: .state)
        progress = try container.decode(DownloadProgress.self, forKey: .progress)
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        detailMessage = try container.decode(String.self, forKey: .detailMessage)
        lastOutputLine = try container.decodeIfPresent(String.self, forKey: .lastOutputLine)
        currentStage = try container.decodeIfPresent(String.self, forKey: .currentStage)
        itemCount = try container.decodeIfPresent(Int.self, forKey: .itemCount)
    }
}

extension DownloadFailureCategory {
    var displayTitle: String {
        switch self {
        case .missingTools:
            "Missing Tools"
        case .authentication:
            "Authentication Required"
        case .network:
            "Connection Problem"
        case .filesystem:
            "File Access Problem"
        case .unsupported:
            "Unsupported URL"
        case .userCancelled:
            "Cancelled"
        case .process:
            "Download Error"
        }
    }
}

struct AlertInfo: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
