import Foundation

private final class SpotDLStreamAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        guard let string = String(data: buffer, encoding: .utf8) else {
            return []
        }

        let lines = string.components(separatedBy: .newlines)
        if string.hasSuffix("\n") {
            buffer.removeAll(keepingCapacity: true)
            return lines.filter { !$0.isEmpty }
        }

        let completedLines = Array(lines.dropLast())
        buffer = Data((lines.last ?? "").utf8)
        return completedLines.filter { !$0.isEmpty }
    }
}

private final class SpotDLOutputContext: @unchecked Sendable {
    private let lock = NSLock()
    private var recentLines: [String] = []

    func record(_ line: String) {
        lock.lock()
        recentLines.append(line)
        recentLines = Array(recentLines.suffix(30))
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recentLines
    }
}

enum SpotDLProviderError: LocalizedError {
    case missingBinary
    case missingFFmpeg
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "spotDL is not available."
        case .missingFFmpeg:
            "ffmpeg is not available."
        case .invalidRequest:
            "Please enter at least one Spotify track, album, or playlist URL."
        }
    }
}

final class SpotDLDownloadProvider: @unchecked Sendable, DownloadProvider {
    let id = "spotdl"

    private var processes: [UUID: Process] = [:]
    private var cancelledJobs = Set<UUID>()
    private let lock = NSLock()

    func canHandle(_ request: DownloadRequest) -> Bool {
        request.mode == .spotifyMusic
    }

    func start(
        id: UUID,
        request: DownloadRequest,
        configuration: ToolchainStatus,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) throws {
        guard request.mode == .spotifyMusic, !request.urls.isEmpty else {
            throw SpotDLProviderError.invalidRequest
        }

        guard let spotDLPath = configuration.spotDL?.path,
              FileManager.default.isExecutableFile(atPath: spotDLPath)
        else {
            throw SpotDLProviderError.missingBinary
        }

        guard let ffmpegPath = configuration.ffmpeg?.path,
              FileManager.default.isExecutableFile(atPath: ffmpegPath)
        else {
            throw SpotDLProviderError.missingFFmpeg
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: spotDLPath)
        process.arguments = Self.buildArguments(request: request, ffmpegPath: ffmpegPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let accumulator = SpotDLStreamAccumulator()
        let outputContext = SpotDLOutputContext()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let lines = accumulator.append(data)
            for line in lines {
                outputContext.record(line)
                onEvent(.rawOutput(line))
                if let stage = Self.parseStage(from: line) {
                    onEvent(.state(.running, message: stage))
                }
                if let progress = Self.parseProgressLine(line) {
                    onEvent(.progress(progress))
                }
                if let outputPath = Self.parseOutputPath(from: line) {
                    onEvent(.outputPath(outputPath))
                }
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            pipe.fileHandleForReading.readabilityHandler = nil

            let wasCancelled: Bool
            self?.lock.lock()
            wasCancelled = self?.cancelledJobs.contains(id) ?? false
            _ = self?.cancelledJobs.remove(id)
            self?.processes.removeValue(forKey: id)
            self?.lock.unlock()

            if wasCancelled {
                onEvent(.state(.cancelled, message: "Cancelled"))
            } else if terminatedProcess.terminationStatus == 0 {
                onEvent(.state(.completed, message: "Completed"))
            } else {
                let failure = Self.inferFailure(from: outputContext.snapshot(), terminationStatus: Int(terminatedProcess.terminationStatus))
                onEvent(.state(.failed(failure), message: failure.summary))
            }
        }

        lock.lock()
        processes[id] = process
        lock.unlock()

        onEvent(.state(.running, message: "Resolving Spotify metadata"))
        try process.run()
    }

    func cancel(id: UUID) {
        lock.lock()
        cancelledJobs.insert(id)
        let process = processes[id]
        lock.unlock()
        process?.terminate()
    }

    static func buildArguments(request: DownloadRequest, ffmpegPath: String) -> [String] {
        let outputTemplate = URL(fileURLWithPath: request.destinationPath)
            .appendingPathComponent("{artist}/{album}/{track-number} - {title}.{output-ext}")
            .path

        var arguments = [
            "download",
            "--ffmpeg", ffmpegPath,
            "--output", outputTemplate
        ]

        switch request.musicOptions.formatPreset {
        case .bestQualityMP3:
            arguments += ["--format", "mp3", "--bitrate", "320k"]
        case .aacM4A:
            arguments += ["--format", "m4a"]
        case .keepBestSource:
            break
        }

        if request.musicOptions.embedArtwork == false {
            arguments.append("--skip-album-art")
        }
        if request.musicOptions.writeMetadata == false {
            arguments.append("--skip-metadata")
        }
        if request.musicOptions.preservePlaylistOrder {
            arguments.append("--playlist-numbering")
        }

        if !request.options.extraFlags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += request.options.extraFlags.split(separator: " ").map(String.init)
        }

        return arguments + request.urls
    }

    private static func parseStage(from line: String) -> String? {
        let normalized = line.lowercased()
        if normalized.contains("retrieving spotify metadata") || normalized.contains("fetching song metadata") {
            return "Resolving Spotify metadata"
        }
        if normalized.contains("found result") || normalized.contains("searching youtube") || normalized.contains("search query") {
            return "Finding audio source"
        }
        if normalized.contains("downloading") {
            return "Downloading audio"
        }
        if normalized.contains("converting") {
            return "Converting"
        }
        if normalized.contains("metadata") || normalized.contains("album art") || normalized.contains("embedding") {
            return "Writing tags and artwork"
        }
        return nil
    }

    private static func parseProgressLine(_ line: String) -> DownloadProgress? {
        let percentPattern = #"(\d+(?:\.\d+)?)%"#
        guard let regex = try? NSRegularExpression(pattern: percentPattern) else { return nil }
        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, range: range),
              let percentRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[percentRange])
        else {
            return nil
        }

        return DownloadProgress(
            fractionCompleted: percent / 100.0,
            percentText: "\(Int(percent))%",
            sizeText: nil,
            speedText: nil,
            etaText: nil
        )
    }

    private static func parseOutputPath(from line: String) -> String? {
        let markers = [
            "Downloaded \"",
            "Saved to \"",
            "Output file: "
        ]

        for marker in markers where line.contains(marker) {
            let path = line.components(separatedBy: marker).last ?? ""
            return path.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }

        return nil
    }

    private static func inferFailure(from lines: [String], terminationStatus: Int) -> DownloadFailure {
        let likelyErrorLine = lines.reversed().first(where: { $0.lowercased().contains("error") }) ?? lines.last ?? "spotDL exited with status \(terminationStatus)"
        let normalized = likelyErrorLine.lowercased()

        if normalized.contains("ffmpeg") {
            return DownloadFailure(
                category: .missingTools,
                summary: "spotDL needs ffmpeg to finish this music download.",
                recoverySuggestion: "Open Settings and repair the toolchain, then retry.",
                technicalDetails: likelyErrorLine
            )
        }

        if normalized.contains("no results found") || normalized.contains("could not find match") {
            return DownloadFailure(
                category: .unsupported,
                summary: "spotDL couldn't find a matching audio source for at least one Spotify item.",
                recoverySuggestion: "Retry the item later or switch to a different music preset.",
                technicalDetails: likelyErrorLine
            )
        }

        if normalized.contains("spotify") && normalized.contains("error") {
            return DownloadFailure(
                category: .authentication,
                summary: "spotDL couldn't resolve the Spotify item metadata.",
                recoverySuggestion: "Check that the Spotify link is public and retry.",
                technicalDetails: likelyErrorLine
            )
        }

        return DownloadFailure(
            category: .process,
            summary: "spotDL failed before the music download could finish.",
            recoverySuggestion: "Retry the download. If it keeps failing, inspect the latest log line for the failing stage.",
            technicalDetails: likelyErrorLine
        )
    }
}
