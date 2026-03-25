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
}
