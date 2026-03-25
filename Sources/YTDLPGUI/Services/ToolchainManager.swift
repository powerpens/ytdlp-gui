import Foundation

struct ToolBinary: Codable, Equatable {
    let path: String
    let version: String?
    let healthError: String?
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
            spotDL != nil && spotDL?.healthError == nil && ffmpeg != nil
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
        status.spotDL == nil || status.spotDL?.healthError != nil
    }

    var spotDLInstallCommand: String {
        let shouldRepairExistingSpotDL = status.spotDL != nil

        if resolveCommand(named: "pipx") != nil {
            return shouldRepairExistingSpotDL
                ? "pipx reinstall spotdl\npipx inject spotdl setuptools"
                : "pipx install spotdl\npipx inject spotdl setuptools"
        }

        if resolveCommand(named: "brew") != nil {
            return shouldRepairExistingSpotDL
                ? "brew install pipx\npipx reinstall spotdl\npipx inject spotdl setuptools"
                : "brew install pipx\npipx install spotdl\npipx inject spotdl setuptools"
        }

        return shouldRepairExistingSpotDL
            ? "pipx reinstall spotdl\npipx inject spotdl setuptools"
            : "pipx install spotdl\npipx inject spotdl setuptools"
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

        let result = try? ProcessRunner.runResult(path, arguments: ["--version"])
        let output = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first
        let healthError = inferredHealthError(for: command, output: output, terminationStatus: result?.terminationStatus ?? 0)

        return ToolBinary(path: path, version: version, healthError: healthError)
    }

    private func resolveCommand(named command: String) -> String? {
        if let fallback = commandFallbacks[command]?.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return fallback
        }

        return ProcessRunner.which(command)
    }

    private func inferredHealthError(for command: String, output: String, terminationStatus: Int32) -> String? {
        guard terminationStatus != 0 || output.lowercased().contains("module") || output.lowercased().contains("traceback") else {
            return nil
        }

        let normalized = output.lowercased()
        if command == "spotdl", normalized.contains("pkg_resources") {
            return "spotDL is installed, but its Python environment is missing setuptools/pkg_resources."
        }

        if output.isEmpty {
            return "\(command) is installed but not responding correctly."
        }

        return output.components(separatedBy: .newlines).first(where: { !$0.isEmpty }) ?? "\(command) is installed but not responding correctly."
    }
}

extension ToolchainManager {
    func testingResolveCommand(named command: String) -> String? {
        resolveCommand(named: command)
    }
}
