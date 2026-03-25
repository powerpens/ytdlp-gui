import Testing
@testable import YTDLPGUI

struct ToolchainManagerTests {
    @Test
    func reportsModeSpecificReadiness() {
        let ytDLP = ToolBinary(path: "/usr/local/bin/yt-dlp", version: nil)
        let ffmpeg = ToolBinary(path: "/usr/local/bin/ffmpeg", version: nil)
        let spotDL = ToolBinary(path: "/usr/local/bin/spotdl", version: nil)

        let mediaOnly = ToolchainStatus(ytDLP: ytDLP, ffmpeg: ffmpeg, spotDL: nil)
        #expect(mediaOnly.isReady(for: .video))
        #expect(mediaOnly.isReady(for: .audio))
        #expect(!mediaOnly.isReady(for: .spotifyMusic))

        let full = ToolchainStatus(ytDLP: ytDLP, ffmpeg: ffmpeg, spotDL: spotDL)
        #expect(full.isReady(for: .spotifyMusic))
    }
}
