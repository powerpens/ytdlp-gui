import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var toolchainManager: ToolchainManager
    @EnvironmentObject private var cookieManager: CookieManager

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.chooseDestination()
                } label: {
                    Label("Destination", systemImage: "folder")
                }

                Button {
                    viewModel.startDownload()
                } label: {
                    Label("Start", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartDownload)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("yt-dlp GUI")
                .font(.largeTitle.weight(.semibold))
            Text("A native macOS front-end for quick downloads, playlist capture, and authenticated media workflows.")
                .foregroundStyle(.secondary)

            ToolchainStatusCard(
                status: toolchainManager.status,
                isInstalling: toolchainManager.isInstalling,
                installLog: toolchainManager.installLog,
                installAction: viewModel.installMissingTools
            )

            if let infoBanner = viewModel.infoBanner {
                Label(infoBanner, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 280)
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DownloadComposerCard()
                ActiveDownloadsCard()
                RecentHistoryCard()
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.url, UTType.plainText], isTargeted: nil) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in
                            viewModel.acceptDroppedText(url.absoluteString)
                        }
                    }
                    return true
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                        let text = item as? String
                        guard let text else { return }
                        Task { @MainActor in
                            viewModel.acceptDroppedText(text)
                        }
                    }
                    return true
                }
            }

            return false
        }
    }
}

private struct DownloadComposerCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var cookieManager: CookieManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Download")
                    .font(.title2.weight(.semibold))

                Text("Paste one or more URLs. Each line becomes a source for the same download request.")
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.urlText)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preset")
                            .font(.headline)
                        Picker("Preset", selection: $viewModel.selectedPreset) {
                            ForEach(MediaPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.selectedPreset.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Destination")
                            .font(.headline)
                        Text(viewModel.destinationPath)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Button("Choose Folder...") {
                            viewModel.chooseDestination()
                        }
                    }
                }

                DisclosureGroup("Advanced Options", isExpanded: $viewModel.isAdvancedExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Playlist", selection: $viewModel.playlistMode) {
                            ForEach(PlaylistMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }

                        HStack(spacing: 16) {
                            Toggle("Embed subtitles", isOn: $viewModel.includeSubtitles)
                            Toggle("Embed thumbnail", isOn: $viewModel.embedThumbnail)
                            Toggle("Write info JSON", isOn: $viewModel.writeInfoJSON)
                        }

                        Picker("Browser Cookies", selection: Binding(
                            get: {
                                if case let .browser(browser) = cookieManager.selectedSource {
                                    return browser
                                }
                                return .safari
                            },
                            set: { browser in
                                cookieManager.useBrowser(browser)
                            }
                        )) {
                            ForEach(BrowserCookieSource.allCases) { browser in
                                Text(browser.title).tag(browser)
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Use Selected Browser") {
                                if case .browser = cookieManager.selectedSource {
                                    return
                                }
                                cookieManager.useBrowser(.safari)
                            }

                            Button("Import Cookie File...") {
                                cookieManager.importCookieFile()
                            }

                            Button("Clear Cookies") {
                                cookieManager.clearSelection()
                            }
                        }

                        Text("Cookie Source: \(cookieManager.selectedSource.description)")
                            .foregroundStyle(.secondary)

                        TextField("Format override (optional)", text: $viewModel.formatOverride)
                            .textFieldStyle(.roundedBorder)
                        TextField("Extra yt-dlp flags (optional)", text: $viewModel.extraFlags)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 12)
                }

                HStack {
                    Text("\(viewModel.parsedURLs.count) URL(s) queued in this request")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Start Download") {
                        viewModel.startDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canStartDownload)
                }
            }
            .padding(20)
        }
    }
}

private struct ActiveDownloadsCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Queue")
                    .font(.title3.weight(.semibold))

                if viewModel.activeJobs.isEmpty {
                    Text("No active downloads right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.activeJobs) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(job.title)
                                    .font(.headline)
                                Spacer()
                                Text(job.progress.percentText)
                                    .foregroundStyle(.secondary)
                            }

                            ProgressView(value: job.progress.fractionCompleted ?? 0)
                                .tint(.accentColor)

                            Text(job.detailMessage.isEmpty ? job.request.preset.title : job.detailMessage)
                                .foregroundStyle(.secondary)

                            if let lastLine = job.lastOutputLine {
                                Text(lastLine)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(2)
                            }

                            HStack {
                                Label(job.stateLabel, systemImage: job.stateIcon)
                                    .foregroundStyle(job.stateColor)
                                Spacer()
                                Button("Cancel", role: .destructive) {
                                    viewModel.cancel(job)
                                }
                            }
                        }
                        .padding(.vertical, 6)

                        if job.id != viewModel.activeJobs.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct RecentHistoryCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent History")
                    .font(.title3.weight(.semibold))

                if viewModel.recentJobs.isEmpty {
                    Text("Completed and failed downloads will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.recentJobs) { job in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.title)
                                    .font(.headline)
                                Text(job.request.urls.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(job.detailMessage)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Label(job.stateLabel, systemImage: job.stateIcon)
                                    .foregroundStyle(job.stateColor)
                                HStack {
                                    Button("Retry") {
                                        viewModel.retry(job)
                                    }
                                    if job.outputPath != nil {
                                        Button("Reveal") {
                                            viewModel.reveal(job)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        if job.id != viewModel.recentJobs.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct ToolchainStatusCard: View {
    let status: ToolchainStatus
    let isInstalling: Bool
    let installLog: String
    let installAction: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Toolchain")
                    .font(.headline)

                HStack {
                    statusRow("yt-dlp", binary: status.ytDLP)
                    statusRow("ffmpeg", binary: status.ffmpeg)
                }

                if !status.isReady {
                    Text("The app can guide installation through Homebrew when the tools are missing.")
                        .foregroundStyle(.secondary)
                    Button(isInstalling ? "Installing..." : "Install Missing Tools") {
                        installAction()
                    }
                    .disabled(isInstalling)
                }

                if !installLog.isEmpty {
                    ScrollView {
                        Text(installLog)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }
            .padding(16)
        }
    }

    private func statusRow(_ title: String, binary: ToolBinary?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let binary {
                Label(binary.version ?? binary.path, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label("Not found", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var toolchainManager: ToolchainManager

    var body: some View {
        Form {
            Picker("Default preset", selection: $preferences.preferredPreset) {
                ForEach(MediaPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            Stepper(value: $preferences.concurrencyLimit, in: 1...4) {
                Text("Concurrent downloads: \(preferences.concurrencyLimit)")
            }

            LabeledContent("Default destination") {
                Text(preferences.defaultDestinationPath)
                    .textSelection(.enabled)
            }

            LabeledContent("yt-dlp") {
                Text(toolchainManager.status.ytDLP?.path ?? "Missing")
                    .foregroundStyle(toolchainManager.status.ytDLP == nil ? .orange : .primary)
            }

            LabeledContent("ffmpeg") {
                Text(toolchainManager.status.ffmpeg?.path ?? "Missing")
                    .foregroundStyle(toolchainManager.status.ffmpeg == nil ? .orange : .primary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 520)
    }
}

private extension DownloadJob {
    var stateLabel: String {
        switch state {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case let .failed(category):
            "Failed • \(category.rawValue)"
        case .cancelled:
            "Cancelled"
        }
    }

    var stateIcon: String {
        switch state {
        case .queued:
            "clock"
        case .running:
            "arrow.down.circle"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        case .cancelled:
            "stop.circle.fill"
        }
    }

    var stateColor: Color {
        switch state {
        case .queued:
            .secondary
        case .running:
            .accentColor
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .orange
        }
    }
}
