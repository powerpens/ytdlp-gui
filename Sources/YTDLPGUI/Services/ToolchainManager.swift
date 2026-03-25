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

    private let commandFallbacks: [String: [String]] = [
        "brew": ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
        "pipx": ["/opt/homebrew/bin/pipx", "/usr/local/bin/pipx", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/pipx").path],
        "python3": ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
    ]

    init() {
        refresh()
    }

    var hasMissingMediaTools: Bool {
        status.ytDLP == nil || status.ffmpeg == nil
    }

    var needsSpotDLManualSetup: Bool {
        status.spotDL == nil
    }

    var spotDLInstallCommand: String {
        if resolveCommand(named: "pipx") != nil {
            return "pipx install spotdl"
        }

        if resolveCommand(named: "brew") != nil {
            return "brew install pipx\npipx install spotdl"
        }

        return "pipx install spotdl"
    }

    func refresh() {
        status = ToolchainStatus(
            ytDLP: resolveBinary(named: "yt-dlp"),
            ffmpeg: resolveBinary(named: "ffmpeg"),
            spotDL: resolveBinary(named: "spotdl")
        )
    }

    func installMissingTools() async throws {
        isInstalling = true
        installLog = ""
        defer { isInstalling = false }

        let brewPackages = [
            status.ytDLP == nil ? "yt-dlp" : nil,
            status.ffmpeg == nil ? "ffmpeg" : nil
        ].compactMap { $0 }

        if !brewPackages.isEmpty {
            guard let brewPath = resolveCommand(named: "brew") else {
                throw ToolchainInstallError.brewMissing
            }
            let output = try ProcessRunner.run(brewPath, arguments: ["install"] + brewPackages)
            installLog += output
        }

        refresh()

        guard status.ytDLP != nil, status.ffmpeg != nil else {
            refresh()
            throw ToolchainInstallError.installFailed("Installation finished but yt-dlp or ffmpeg is still unavailable.")
        }
    }

    private func resolveBinary(named command: String) -> ToolBinary? {
        let explicitPath = searchPaths.first { $0.hasSuffix("/\(command)") && FileManager.default.isExecutableFile(atPath: $0) }
        let resolvedPath = explicitPath ?? resolveCommand(named: command)

        guard let path = resolvedPath else {
            return nil
        }

        let version = try? ProcessRunner.run(path, arguments: ["--version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first

        return ToolBinary(path: path, version: version)
    }

    private func resolveCommand(named command: String) -> String? {
        if let fallback = commandFallbacks[command]?.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return fallback
        }

        return ProcessRunner.which(command)
    }
}

extension ToolchainManager {
    func testingResolveCommand(named command: String) -> String? {
        resolveCommand(named: command)
    }
}
