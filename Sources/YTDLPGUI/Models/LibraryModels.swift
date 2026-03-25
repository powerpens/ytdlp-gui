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
