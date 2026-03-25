import Testing
@testable import YTDLPGUI

struct DownloadEngineTests {
    @Test
    func buildsArgumentsForAudioWithCookiesAndOverrides() {
        let request = DownloadRequest(
            urls: ["https://example.com/watch?v=123"],
            preset: .bestAudio,
            destinationPath: "/tmp/out",
            playlistMode: .singleItem,
            cookieSource: .browser(.firefox),
            options: DownloadOptions(
                includeSubtitles: true,
                embedThumbnail: true,
                writeInfoJSON: true,
                formatOverride: "ba",
                extraFlags: "--ignore-errors --no-warnings"
            )
        )

        let arguments = DownloadEngine.buildArguments(
            request: request,
            configuration: DownloadEngineConfiguration(ytDLPPath: "/usr/local/bin/yt-dlp", ffmpegPath: "/usr/local/bin/ffmpeg")
        )

        #expect(arguments.contains("--cookies-from-browser"))
        #expect(arguments.contains("firefox"))
        #expect(arguments.contains("--no-playlist"))
        #expect(arguments.contains("--audio-format"))
        #expect(arguments.contains("mp3"))
        #expect(arguments.contains("--embed-thumbnail"))
        #expect(arguments.contains("--write-info-json"))
        #expect(arguments.suffix(1).first == "https://example.com/watch?v=123")
    }

    @Test
    func parsesProgressLine() {
        let progress = DownloadEngine.parseProgressLine("[download]  42.3% of 55.01MiB at 2.11MiB/s ETA 00:09")

        #expect(progress?.percentText == "42.3%")
        #expect(progress?.fractionCompleted == 0.423)
        #expect(progress?.sizeText == "55.01MiB")
        #expect(progress?.speedText == "2.11MiB/s")
        #expect(progress?.etaText == "00:09")
    }

    @Test
    func parsesDestinationLines() {
        #expect(DownloadEngine.parseDestinationLine(#"[Merger] Merging formats into "/tmp/video.mp4""#) == "/tmp/video.mp4")
        #expect(DownloadEngine.parseDestinationLine("[download] Destination: /tmp/audio.webm") == "/tmp/audio.webm")
    }

    @Test
    func classifiesAuthenticationFailure() {
        let failure = DownloadEngine.inferFailure(
            from: ["ERROR: Sign in to confirm your age"],
            terminationStatus: 1,
            reason: .exit
        )

        #expect(failure.category == .authentication)
        #expect(failure.summary.contains("authentication"))
    }

    @Test
    func classifiesUnsupportedFailure() {
        let failure = DownloadEngine.inferFailure(
            from: ["ERROR: Unsupported URL: https://example.com/post/123"],
            terminationStatus: 1,
            reason: .exit
        )

        #expect(failure.category == .unsupported)
    }

    @Test
    func buildsSpotDLArgumentsForTaggedMusicDownloads() {
        let request = DownloadRequest(
            mode: .spotifyMusic,
            urls: ["https://open.spotify.com/track/abc123"],
            preset: .bestAudio,
            destinationPath: "/tmp/music",
            playlistMode: .wholePlaylist,
            cookieSource: .none,
            options: DownloadOptions(extraFlags: "--threads 4"),
            musicOptions: MusicOptions(
                embedArtwork: false,
                writeMetadata: true,
                preservePlaylistOrder: true,
                formatPreset: .aacM4A
            )
        )

        let arguments = SpotDLDownloadProvider.buildArguments(
            request: request,
            ffmpegPath: "/usr/local/bin/ffmpeg"
        )

        #expect(arguments.contains("download"))
        #expect(arguments.contains("--ffmpeg"))
        #expect(arguments.contains("/usr/local/bin/ffmpeg"))
        #expect(arguments.contains("--format"))
        #expect(arguments.contains("m4a"))
        #expect(arguments.contains("--playlist-numbering"))
        #expect(arguments.contains("--skip-album-art"))
        #expect(arguments.contains("https://open.spotify.com/track/abc123"))
    }

    @Test
    func parsesSpotDLBatchProgressAndStage() {
        let line = "Processing query 2/5: Chef Paul - Carbonara"

        let progress = SpotDLDownloadProvider.parseProgressLine(line)
        let stage = SpotDLDownloadProvider.parseStage(from: line)

        #expect(progress?.percentText == "2/5")
        #expect(progress?.fractionCompleted == 0.4)
        #expect(progress?.sizeText == "Track 2 of 5 • Chef Paul - Carbonara")
        #expect(stage == "Finding audio source • Track 2 of 5")
    }

    @Test
    func extractsSpotDLDisplayTitle() {
        let title = SpotDLDownloadProvider.parseDisplayTitle(from: "Downloading Chef Paul - Carbonara")
        #expect(title == "Chef Paul - Carbonara")
    }

    @Test
    func classifiesBrokenSpotDLEnvironment() {
        let failure = SpotDLDownloadProvider.inferFailure(
            from: ["ModuleNotFoundError: No module named 'pkg_resources'"],
            terminationStatus: 1
        )

        #expect(failure.category == .missingTools)
        #expect(failure.summary.contains("pkg_resources"))
    }
}
