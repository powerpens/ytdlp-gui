import Testing
@testable import YTDLPGUI

@MainActor
struct ToolchainManagerTests {
    @Test
    func reportsModeSpecificReadiness() {
        let ytDLP = ToolBinary(path: "/usr/local/bin/yt-dlp", version: nil, healthError: nil)
        let ffmpeg = ToolBinary(path: "/usr/local/bin/ffmpeg", version: nil, healthError: nil)
        let spotDL = ToolBinary(path: "/usr/local/bin/spotdl", version: nil, healthError: nil)

        let mediaOnly = ToolchainStatus(ytDLP: ytDLP, ffmpeg: ffmpeg, spotDL: nil)
        #expect(mediaOnly.isReady(for: .video))
        #expect(mediaOnly.isReady(for: .audio))
        #expect(!mediaOnly.isReady(for: .spotifyMusic))

        let full = ToolchainStatus(ytDLP: ytDLP, ffmpeg: ffmpeg, spotDL: spotDL)
        #expect(full.isReady(for: .spotifyMusic))
    }

    @Test
    func spotDLHealthErrorsBlockSpotifyMode() {
        let ffmpeg = ToolBinary(path: "/usr/local/bin/ffmpeg", version: nil, healthError: nil)
        let brokenSpotDL = ToolBinary(
            path: "/usr/local/bin/spotdl",
            version: nil,
            healthError: "spotDL is installed, but its Python environment is missing setuptools/pkg_resources."
        )

        let status = ToolchainStatus(ytDLP: nil, ffmpeg: ffmpeg, spotDL: brokenSpotDL)
        #expect(!status.isReady(for: .spotifyMusic))
    }

    @Test
    func resolvesFallbackCommandsWithoutShellPath() {
        let manager = ToolchainManager()

        #expect(manager.testingResolveCommand(named: "brew") != nil)
        #expect(manager.testingResolveCommand(named: "python3") != nil)
    }

    @Test
    func prefersGuidedSpotDLInstallCommand() {
        let manager = ToolchainManager()

        let command = manager.spotDLInstallCommand
        #expect(!command.isEmpty)
        #expect(command.contains("spotdl"))
    }
}
