import Foundation

struct DownloadEngineConfiguration {
    let ytDLPPath: String
    let ffmpegPath: String
}

enum DownloadEvent {
    case state(DownloadJobState, message: String)
    case progress(DownloadProgress)
    case outputPath(String)
    case rawOutput(String)
}

enum DownloadEngineError: LocalizedError {
    case missingBinary(String)
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case let .missingBinary(name):
            "\(name) is not available."
        case .invalidRequest:
            "Please enter at least one valid URL."
        }
    }
}

private final class StreamAccumulator: @unchecked Sendable {
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

private final class ProcessOutputContext: @unchecked Sendable {
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

final class DownloadEngine: @unchecked Sendable {
    private var processes: [UUID: Process] = [:]
    private var cancelledJobs = Set<UUID>()
    private let lock = NSLock()

    func start(
        id: UUID,
        request: DownloadRequest,
        configuration: DownloadEngineConfiguration,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) throws {
        guard !request.urls.isEmpty else {
            throw DownloadEngineError.invalidRequest
        }

        guard FileManager.default.isExecutableFile(atPath: configuration.ytDLPPath) else {
            throw DownloadEngineError.missingBinary("yt-dlp")
        }

        guard FileManager.default.isExecutableFile(atPath: configuration.ffmpegPath) else {
            throw DownloadEngineError.missingBinary("ffmpeg")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.ytDLPPath)
        process.arguments = Self.buildArguments(request: request, configuration: configuration)

        let combinedPipe = Pipe()
        process.standardOutput = combinedPipe
        process.standardError = combinedPipe

        let accumulator = StreamAccumulator()
        let outputContext = ProcessOutputContext()
        combinedPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let lines = accumulator.append(data)
            for line in lines {
                outputContext.record(line)
                onEvent(.rawOutput(line))
                if let progress = Self.parseProgressLine(line) {
                    onEvent(.progress(progress))
                }
                if let outputPath = Self.parseDestinationLine(line) {
                    onEvent(.outputPath(outputPath))
                }
            }
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            combinedPipe.fileHandleForReading.readabilityHandler = nil

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
                let failure = Self.inferFailure(
                    from: outputContext.snapshot(),
                    terminationStatus: Int(terminatedProcess.terminationStatus),
                    reason: terminatedProcess.terminationReason
                )
                onEvent(.state(.failed(failure), message: failure.summary))
            }
        }

        lock.lock()
        processes[id] = process
        lock.unlock()

        onEvent(.state(.running, message: "Preparing download"))
        try process.run()
    }

    func cancel(id: UUID) {
        lock.lock()
        cancelledJobs.insert(id)
        let process = processes[id]
        lock.unlock()
        process?.terminate()
    }

    static func buildArguments(request: DownloadRequest, configuration: DownloadEngineConfiguration) -> [String] {
        var arguments = [
            "--newline",
            "--progress",
            "--no-simulate",
            "--ffmpeg-location", configuration.ffmpegPath,
            "-P", request.destinationPath,
            "-o", "%(title)s [%(id)s].%(ext)s"
        ]

        switch request.preset {
        case .bestVideo:
            arguments += ["-f", "bv*+ba/b"]
        case .bestAudio:
            arguments += ["-x", "--audio-format", "mp3"]
        case .mp4Compatible:
            arguments += ["-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b", "--merge-output-format", "mp4"]
        }

        switch request.playlistMode {
        case .auto:
            break
        case .singleItem:
            arguments.append("--no-playlist")
        case .wholePlaylist:
            arguments.append("--yes-playlist")
        }

        switch request.cookieSource {
        case .none:
            break
        case let .browser(browser):
            arguments += ["--cookies-from-browser", browser.rawValue]
        case let .file(path):
            arguments += ["--cookies", path]
        }

        if request.options.includeSubtitles {
            arguments += ["--embed-subs", "--write-subs", "--sub-langs", "all"]
        }
        if request.options.embedThumbnail {
            arguments += ["--embed-thumbnail"]
        }
        if request.options.writeInfoJSON {
            arguments += ["--write-info-json"]
        }
        if !request.options.formatOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["-f", request.options.formatOverride.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        if !request.options.extraFlags.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += request.options.extraFlags
                .split(separator: " ")
                .map(String.init)
        }

        return arguments + request.urls
    }

    static func parseProgressLine(_ line: String) -> DownloadProgress? {
        guard line.contains("[download]") else {
            return nil
        }

        let pattern = #"\[download\]\s+(\d+(?:\.\d+)?)%\s+of\s+(.+?)(?:\s+at\s+(.+?))?(?:\s+ETA\s+(.+))?$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: line.utf16.count)
        guard
            let match = regex?.firstMatch(in: line, range: range),
            let percentRange = Range(match.range(at: 1), in: line)
        else {
            return nil
        }

        let percentText = String(line[percentRange]) + "%"
        let fraction = Double(String(line[percentRange])).map { $0 / 100.0 }
        let sizeText = Range(match.range(at: 2), in: line).map { String(line[$0]) }
        let speedText = Range(match.range(at: 3), in: line).map { String(line[$0]) }
        let etaText = Range(match.range(at: 4), in: line).map { String(line[$0]) }
        return DownloadProgress(
            fractionCompleted: fraction,
            percentText: percentText,
            sizeText: sizeText,
            speedText: speedText,
            etaText: etaText
        )
    }

    static func parseDestinationLine(_ line: String) -> String? {
        let markers = [
            "[download] Destination: ",
            "[Merger] Merging formats into \"",
            "[ExtractAudio] Destination: "
        ]

        for marker in markers where line.contains(marker) {
            let path = line.components(separatedBy: marker).last ?? ""
            return path.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }

        return nil
    }

    static func inferFailure(
        from recentLines: [String],
        terminationStatus: Int,
        reason: Process.TerminationReason
    ) -> DownloadFailure {
        if reason == .uncaughtSignal {
            return DownloadFailure(
                category: .userCancelled,
                summary: "The download was cancelled before it finished.",
                recoverySuggestion: "Start the download again when you're ready.",
                technicalDetails: "The yt-dlp process was interrupted by a signal."
            )
        }

        let likelyErrorLine = recentLines.reversed().first(where: { line in
            let lowered = line.lowercased()
            return lowered.contains("error:") || lowered.contains("permission denied") || lowered.contains("unsupported url")
        }) ?? recentLines.last ?? "yt-dlp exited with status \(terminationStatus)"
        let cleanedLine = cleanTechnicalLine(likelyErrorLine)
        let normalized = cleanedLine.lowercased()

        if normalized.contains("unsupported url") || normalized.contains("no suitable extractor") {
            return DownloadFailure(
                category: .unsupported,
                summary: "This URL or site is not supported by the current yt-dlp setup.",
                recoverySuggestion: "Double-check the link. If it looks right, try updating yt-dlp in Settings and retry.",
                technicalDetails: cleanedLine
            )
        }

        if normalized.contains("login required")
            || normalized.contains("sign in")
            || normalized.contains("cookies")
            || normalized.contains("private")
            || normalized.contains("members only")
            || normalized.contains("authentication")
        {
            return DownloadFailure(
                category: .authentication,
                summary: "This download likely needs authentication or fresher cookies.",
                recoverySuggestion: "Open Advanced Options and choose a browser cookie source or import a cookie file, then retry.",
                technicalDetails: cleanedLine
            )
        }

        if normalized.contains("timed out")
            || normalized.contains("connection")
            || normalized.contains("network is unreachable")
            || normalized.contains("temporary failure")
            || normalized.contains("unable to download")
        {
            return DownloadFailure(
                category: .network,
                summary: "The download failed while talking to the source site.",
                recoverySuggestion: "Check your connection, wait a moment, and try again.",
                technicalDetails: cleanedLine
            )
        }

        if normalized.contains("permission denied")
            || normalized.contains("read-only file system")
            || normalized.contains("operation not permitted")
            || normalized.contains("no space left")
            || normalized.contains("cannot write")
        {
            return DownloadFailure(
                category: .filesystem,
                summary: "The app couldn't write files to the selected folder.",
                recoverySuggestion: "Choose a different destination folder or fix the folder permissions, then retry.",
                technicalDetails: cleanedLine
            )
        }

        if normalized.contains("ffmpeg not found")
            || normalized.contains("ffprobe not found")
            || normalized.contains("yt-dlp not found")
        {
            return DownloadFailure(
                category: .missingTools,
                summary: "A required download tool is missing or unavailable.",
                recoverySuggestion: "Open Settings and install or repair yt-dlp and ffmpeg, then retry.",
                technicalDetails: cleanedLine
            )
        }

        if normalized.contains("requested format is not available") {
            return DownloadFailure(
                category: .process,
                summary: "The selected format isn't available for this video.",
                recoverySuggestion: "Clear the format override or switch to a broader preset like Best Video, then retry.",
                technicalDetails: cleanedLine
            )
        }

        return DownloadFailure(
            category: .process,
            summary: "yt-dlp couldn't finish this download.",
            recoverySuggestion: "Review the details, adjust the options if needed, and try again.",
            technicalDetails: cleanedLine.isEmpty ? "yt-dlp exited with status \(terminationStatus)." : cleanedLine
        )
    }

    private static func cleanTechnicalLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "ERROR: ", with: "")
            .replacingOccurrences(of: "error: ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
