import Foundation

struct ToolBinary: Codable, Equatable {
    let path: String
    let version: String?
}

struct ToolchainStatus: Codable, Equatable {
    var ytDLP: ToolBinary?
    var ffmpeg: ToolBinary?

    var isReady: Bool {
        ytDLP != nil && ffmpeg != nil
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
        "/usr/local/bin/ffmpeg"
    ]

    init() {
        refresh()
    }

    func refresh() {
        status = ToolchainStatus(
            ytDLP: resolveBinary(named: "yt-dlp"),
            ffmpeg: resolveBinary(named: "ffmpeg")
        )
    }

    func installMissingTools() async throws {
        guard let brewPath = ProcessRunner.which("brew") else {
            throw ToolchainInstallError.brewMissing
        }

        isInstalling = true
        installLog = ""
        defer { isInstalling = false }

        let packages = [
            status.ytDLP == nil ? "yt-dlp" : nil,
            status.ffmpeg == nil ? "ffmpeg" : nil
        ].compactMap { $0 }

        guard !packages.isEmpty else {
            refresh()
            return
        }

        let output = try ProcessRunner.run(brewPath, arguments: ["install"] + packages)
        installLog = output
        refresh()

        guard status.isReady else {
            throw ToolchainInstallError.installFailed("Installation finished but the tools are still unavailable.")
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
