import Foundation

struct ToolBinary: Codable, Equatable {
    let path: String
    let version: String?
}

struct ToolchainStatus: Codable, Equatable {
    var ytDLP: ToolBinary?
    var ffmpeg: ToolBinary?
    var spotDL: ToolBinary?

    var isReady: Bool {
        ytDLP != nil && ffmpeg != nil
    }

    func isReady(for mode: DownloadMode) -> Bool {
        switch mode {
        case .video, .audio:
            ytDLP != nil && ffmpeg != nil
        case .spotifyMusic:
            spotDL != nil && ffmpeg != nil
        }
    }
}

enum ToolchainInstallError: LocalizedError {
    case brewMissing
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .brewMissing:
            "Homebrew is not installed. Install Homebrew or place yt-dlp and ffmpeg on your PATH."
        case let .installFailed(message):
            message
        }
    }
}

@MainActor
final class ToolchainManager: ObservableObject {
    @Published private(set) var status = ToolchainStatus()
    @Published private(set) var isInstalling = false
    @Published private(set) var installLog = ""

    private let searchPaths = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/homebrew/bin/spotdl",
        "/usr/local/bin/spotdl",
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/spotdl").path
    ]

    init() {
        refresh()
    }

    func refresh() {
        status = ToolchainStatus(
            ytDLP: resolveBinary(named: "yt-dlp"),
            ffmpeg: resolveBinary(named: "ffmpeg"),
            spotDL: resolveBinary(named: "spotdl")
        )
    }

    func installMissingTools() async throws {
        guard let brewPath = ProcessRunner.which("brew") else {
            throw ToolchainInstallError.brewMissing
        }

        isInstalling = true
        installLog = ""
        defer { isInstalling = false }

        let brewPackages = [
            status.ytDLP == nil ? "yt-dlp" : nil,
            status.ffmpeg == nil ? "ffmpeg" : nil
        ].compactMap { $0 }

        if !brewPackages.isEmpty {
            let output = try ProcessRunner.run(brewPath, arguments: ["install"] + brewPackages)
            installLog += output
        }

        if status.spotDL == nil {
            if let pipxPath = ProcessRunner.which("pipx") {
                installLog += try ProcessRunner.run(pipxPath, arguments: ["install", "spotdl"])
            } else if let python3Path = ProcessRunner.which("python3") {
                installLog += try ProcessRunner.run(python3Path, arguments: ["-m", "pip", "install", "--user", "spotdl"])
            } else {
                throw ToolchainInstallError.installFailed("spotDL is missing and neither pipx nor python3 is available to install it.")
            }
        }

        refresh()

        guard status.ytDLP != nil, status.ffmpeg != nil else {
            refresh()
            throw ToolchainInstallError.installFailed("Installation finished but yt-dlp or ffmpeg is still unavailable.")
        }
        guard status.spotDL != nil else {
            throw ToolchainInstallError.installFailed("Installation finished but spotDL is still unavailable.")
        }
    }

    private func resolveBinary(named command: String) -> ToolBinary? {
        let explicitPath = searchPaths.first { $0.hasSuffix("/\(command)") && FileManager.default.isExecutableFile(atPath: $0) }
        let resolvedPath = explicitPath ?? ProcessRunner.which(command)

        guard let path = resolvedPath else {
            return nil
        }

        let version = try? ProcessRunner.run(path, arguments: ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first

        return ToolBinary(path: path, version: version)
    }
}
