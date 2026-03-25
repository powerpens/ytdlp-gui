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

    var fileExtension: String {
        url.pathExtension.uppercased()
    }
}
