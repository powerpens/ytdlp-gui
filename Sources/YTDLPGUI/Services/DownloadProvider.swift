import Foundation

protocol DownloadProvider: AnyObject {
    var id: String { get }
    func canHandle(_ request: DownloadRequest) -> Bool
    func start(
        id: UUID,
        request: DownloadRequest,
        configuration: ToolchainStatus,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) throws
    func cancel(id: UUID)
}

final class YTDLPDownloadProvider: DownloadProvider {
    let id = "yt-dlp"

    private let engine = DownloadEngine()

    func canHandle(_ request: DownloadRequest) -> Bool {
        request.mode != .spotifyMusic
    }

    func start(
        id: UUID,
        request: DownloadRequest,
        configuration: ToolchainStatus,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) throws {
        guard let ytDLPPath = configuration.ytDLP?.path,
              let ffmpegPath = configuration.ffmpeg?.path
        else {
            throw DownloadEngineError.missingBinary("yt-dlp")
        }

        try engine.start(
            id: id,
            request: request,
            configuration: DownloadEngineConfiguration(ytDLPPath: ytDLPPath, ffmpegPath: ffmpegPath),
            onEvent: onEvent
        )
    }

    func cancel(id: UUID) {
        engine.cancel(id: id)
    }
}

final class DownloadProviderRouter {
    private let providers: [DownloadProvider]

    init(providers: [DownloadProvider]) {
        self.providers = providers
    }

    func provider(for request: DownloadRequest) -> DownloadProvider? {
        providers.first(where: { $0.canHandle(request) })
    }

    func cancel(job: DownloadJob) {
        providers.first(where: { $0.id == job.providerID })?.cancel(id: job.id)
    }
}
