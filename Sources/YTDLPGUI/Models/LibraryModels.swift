import Foundation

enum LibraryMediaKind: String, Codable, CaseIterable {
    case video
    case audio
    case other

    var title: String {
        switch self {
        case .video:
            "Video"
        case .audio:
            "Audio"
        case .other:
            "Other"
        }
    }
}

enum LibraryBrowserLayout: String, CaseIterable, Identifiable {
    case list
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list:
            "List"
        case .gallery:
            "Gallery"
        }
    }
}

struct LibraryMediaItem: Identifiable, Equatable {
    let id: URL
    let url: URL
    let fileName: String
    let kind: LibraryMediaKind
    let fileSize: Int64
    let modifiedAt: Date?
    let metadata: LibraryMediaMetadata

    var displayTitle: String {
        metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? fileName
    }

    var secondaryText: String? {
        switch (metadata.artist?.nonEmpty, metadata.album?.nonEmpty) {
        case let (artist?, album?):
            return "\(artist) • \(album)"
        case let (artist?, nil):
            return artist
        case let (nil, album?):
            return album
        case (nil, nil):
            return nil
        }
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }

    var durationText: String? {
        guard let duration = metadata.duration, duration.isFinite, duration > 0 else { return nil }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration)
    }
}

struct LibraryMediaMetadata: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval?

    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
