import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var selectedPreset: MediaPreset
    @Published var destinationPath: String
    @Published var playlistMode: PlaylistMode = .auto
    @Published var includeSubtitles = false
    @Published var embedThumbnail = false
    @Published var writeInfoJSON = false
    @Published var formatOverride = ""
    @Published var extraFlags = ""
    @Published var isAdvancedExpanded = false
    @Published var activeJobs: [DownloadJob] = []
    @Published var recentJobs: [DownloadJob] = []
    @Published var errorMessage: String?
    @Published var infoBanner: String?

    private let preferences: PreferencesStore
    private let toolchainManager: ToolchainManager
    private let cookieManager: CookieManager
    private let historyStore: HistoryStore
    private let downloadEngine = DownloadEngine()

    init(
        preferences: PreferencesStore,
        toolchainManager: ToolchainManager,
        cookieManager: CookieManager,
        historyStore: HistoryStore
    ) {
        self.preferences = preferences
        self.toolchainManager = toolchainManager
        self.cookieManager = cookieManager
        self.historyStore = historyStore
        selectedPreset = preferences.preferredPreset
        destinationPath = preferences.defaultDestinationPath
        recentJobs = historyStore.load()
    }

    var canStartDownload: Bool {
        !parsedURLs.isEmpty && activeJobs.count < preferences.concurrencyLimit
    }

    var parsedURLs: [String] {
        urlText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func startDownload() {
        guard toolchainManager.status.isReady,
              let ytDLPPath = toolchainManager.status.ytDLP?.path,
              let ffmpegPath = toolchainManager.status.ffmpeg?.path
        else {
            errorMessage = "yt-dlp and ffmpeg must both be available before starting a download."
            return
        }

        let request = DownloadRequest(
            urls: parsedURLs,
            preset: selectedPreset,
            destinationPath: destinationPath,
            playlistMode: playlistMode,
            cookieSource: cookieManager.selectedSource,
            options: DownloadOptions(
                includeSubtitles: includeSubtitles,
                embedThumbnail: embedThumbnail,
                writeInfoJSON: writeInfoJSON,
                formatOverride: formatOverride,
                extraFlags: extraFlags
            )
        )

        guard cookieManager.validate(source: request.cookieSource) else {
            errorMessage = "The selected cookie file is missing or unreadable."
            return
        }

        guard activeJobs.count < preferences.concurrencyLimit else {
            errorMessage = "The concurrency limit is \(preferences.concurrencyLimit). Wait for an active download to finish or raise the limit in Settings."
            return
        }

        let job = DownloadJob.queued(from: request)
        activeJobs.insert(job, at: 0)
        infoBanner = nil
        errorMessage = nil

        do {
            try downloadEngine.start(
                id: job.id,
                request: request,
                configuration: DownloadEngineConfiguration(ytDLPPath: ytDLPPath, ffmpegPath: ffmpegPath)
            ) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event, for: job.id)
                }
            }

            selectedPreset = preferences.preferredPreset
            preferences.defaultDestinationPath = destinationPath
        } catch {
            activeJobs.removeAll { $0.id == job.id }
            errorMessage = error.localizedDescription
        }
    }

    func cancel(_ job: DownloadJob) {
        downloadEngine.cancel(id: job.id)
    }

    func retry(_ job: DownloadJob) {
        urlText = job.request.urls.joined(separator: "\n")
        selectedPreset = job.request.preset
        destinationPath = job.request.destinationPath
        playlistMode = job.request.playlistMode
        includeSubtitles = job.request.options.includeSubtitles
        embedThumbnail = job.request.options.embedThumbnail
        writeInfoJSON = job.request.options.writeInfoJSON
        formatOverride = job.request.options.formatOverride
        extraFlags = job.request.options.extraFlags
        cookieManager.selectedSource = job.request.cookieSource
        startDownload()
    }

    func reveal(_ job: DownloadJob) {
        guard let outputPath = job.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.title = "Choose Download Destination"
        panel.directoryURL = URL(fileURLWithPath: destinationPath)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        destinationPath = url.path
        preferences.defaultDestinationPath = url.path
    }

    func installMissingTools() {
        Task {
            do {
                try await toolchainManager.installMissingTools()
                infoBanner = "Toolchain installation completed."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func acceptDroppedText(_ text: String) {
        let existing = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            urlText = text
        } else {
            urlText += "\n" + text
        }
    }

    private func handle(_ event: DownloadEvent, for jobID: UUID) {
        guard let index = activeJobs.firstIndex(where: { $0.id == jobID }) else {
            return
        }

        activeJobs[index].updatedAt = Date()

        switch event {
        case let .state(state, message):
            activeJobs[index].state = state
            activeJobs[index].detailMessage = message
            if state.isTerminal {
                finish(jobAt: index)
            }
        case let .progress(progress):
            activeJobs[index].progress = progress
            activeJobs[index].detailMessage = [progress.sizeText, progress.speedText, progress.etaText]
                .compactMap { $0 }
                .joined(separator: " • ")
            if let percentText = progress.fractionCompleted {
                activeJobs[index].title = "\(Int(percentText * 100))% • \(activeJobs[index].request.urls.first ?? "Download")"
            }
        case let .outputPath(path):
            activeJobs[index].outputPath = path
        case let .rawOutput(line):
            activeJobs[index].lastOutputLine = line
            if activeJobs[index].outputPath == nil {
                activeJobs[index].title = Self.prettifiedTitle(from: line, fallback: activeJobs[index].title)
            }
        }
    }

    private func finish(jobAt index: Int) {
        let finishedJob = activeJobs.remove(at: index)
        recentJobs.insert(finishedJob, at: 0)
        recentJobs = Array(recentJobs.prefix(20))

        do {
            try historyStore.save(recentJobs)
        } catch {
            errorMessage = "Unable to save history: \(error.localizedDescription)"
        }
    }

    private static func prettifiedTitle(from line: String, fallback: String) -> String {
        if line.contains("[download] Downloading item") {
            return line.replacingOccurrences(of: "[download] ", with: "")
        }
        if line.contains("[download] Destination:") {
            return URL(fileURLWithPath: line.replacingOccurrences(of: "[download] Destination: ", with: "")).lastPathComponent
        }
        return fallback
    }
}
