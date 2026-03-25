import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var toolchainManager: ToolchainManager

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                if viewModel.selectedSection == .downloads {
                    Button {
                        viewModel.chooseDestination()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    .help("Choose the destination folder for downloaded files")

                    Button {
                        viewModel.startDownload()
                    } label: {
                        Label("Start", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canStartDownload)
                } else {
                    Button {
                        viewModel.refreshLibrary()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Button {
                        viewModel.openLibraryFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .alert(item: $viewModel.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("yt-dlp GUI")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text("Download videos and browse what you’ve saved.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                SidebarButton(
                    title: "Downloads",
                    subtitle: "Paste links, choose presets, and monitor queue progress.",
                    systemImage: "arrow.down.circle",
                    isSelected: viewModel.selectedSection == .downloads
                ) {
                    viewModel.selectedSection = .downloads
                }

                SidebarButton(
                    title: "Library",
                    subtitle: "\(viewModel.libraryStore.items.count) item(s) in \(viewModel.libraryStore.rootFolderURL.lastPathComponent)",
                    systemImage: "film.stack",
                    isSelected: viewModel.selectedSection == .library
                ) {
                    viewModel.selectedSection = .library
                }
            }

            if !toolchainManager.status.isReady {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Downloads are unavailable until yt-dlp and ffmpeg are installed.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Open Settings to install or inspect the toolchain.")
                            .foregroundStyle(.secondary)
                        SettingsLink {
                            Label("Open Settings", systemImage: "gearshape")
                        }
                    }
                    .padding(16)
                }
            }

            if let infoBanner = viewModel.infoBanner {
                Label(infoBanner, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedSection {
        case .downloads:
            downloadsDetail
        case .library:
            libraryDetail
        }
    }

    private var downloadsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DownloadHeroCard()
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

    private var libraryDetail: some View {
        LibraryBrowserView()
            .padding(24)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SidebarButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.8) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct DownloadHeroCard: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Drop a URL to save it offline")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Downloads appear in the browser view automatically after they finish.")
                    .foregroundStyle(.secondary)
                HStack {
                    Label(viewModel.destinationPath, systemImage: "folder.fill")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if !viewModel.activeJobs.isEmpty {
                        Label("\(viewModel.activeJobs.count) active", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            .padding(24)
        }
        .frame(minHeight: 170)
    }
}

private struct DownloadComposerCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var cookieManager: CookieManager

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New Download")
                            .font(.title2.weight(.semibold))
                        Text("Paste one or more URLs. Each line becomes a source for the same request.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Paste from Clipboard") {
                        viewModel.pasteFromClipboard()
                    }
                }

                TextEditor(text: $viewModel.urlText)
                    .font(.body.monospaced())
                    .frame(minHeight: 130)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

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
                        Text("Destination Folder")
                            .font(.headline)
                        Text(viewModel.destinationPath)
                            .textSelection(.enabled)
                            .lineLimit(3)
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
                                    .foregroundStyle(job.failureSummary == nil ? .tertiary : .primary)
                                if let failureSummary = job.failureSummary {
                                    Text(failureSummary)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
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

private struct LibraryBrowserView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)
    ]

    var body: some View {
        HSplitView {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Saved Media")
                                .font(.title2.weight(.semibold))
                            Text("\(viewModel.libraryStore.items.count) item(s)")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open in Finder") {
                            viewModel.openLibraryFolder()
                        }
                    }

                    if viewModel.libraryStore.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No media found yet.")
                                .font(.headline)
                            Text("Downloads saved into this folder will appear here automatically.")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(viewModel.libraryStore.items) { item in
                                    LibraryItemCard(
                                        item: item,
                                        isSelected: viewModel.selectedLibraryItemID == item.id
                                    ) {
                                        viewModel.selectedLibraryItemID = item.id
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(20)
            }

            GroupBox {
                if let item = viewModel.selectedLibraryItem {
                    LibraryDetailPane(item: item)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select an item")
                            .font(.headline)
                        Text("Choose something from the library to preview its details and open it.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
                }
            }
            .frame(minWidth: 260, idealWidth: 320)
        }
    }
}

private struct LibraryItemCard: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let item: LibraryMediaItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                LibraryPreviewImage(item: item, size: CGSize(width: 220, height: 140))
                    .frame(height: 98)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(2)

                HStack {
                    Text(item.kind.title)
                    Spacer()
                    Text(item.fileExtension)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryDetailPane: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let item: LibraryMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                LibraryPreviewImage(item: item, size: CGSize(width: 320, height: 220))
                    .frame(width: 260, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer()
            }

            Text(item.fileName)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)

            DetailRow(label: "Type", value: item.kind.title)
            DetailRow(label: "Format", value: item.fileExtension)
            DetailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
            DetailRow(label: "Modified", value: item.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "--")
            DetailRow(label: "Path", value: item.url.path)

            Spacer()

            HStack {
                Button("Reveal in Finder") {
                    viewModel.revealLibraryItem(item)
                }
                Button("Open") {
                    viewModel.openLibraryItem(item)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}

private struct LibraryPreviewImage: View {
    @EnvironmentObject private var viewModel: AppViewModel
    let item: LibraryMediaItem
    let size: CGSize

    @State private var previewImage: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: viewModel.libraryStore.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(22)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: item.id) {
            previewImage = await viewModel.libraryStore.previewImage(for: item, size: size)
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var toolchainManager: ToolchainManager
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section("Toolchain") {
                LabeledContent("yt-dlp") {
                    Text(toolchainManager.status.ytDLP?.path ?? "Missing")
                        .foregroundStyle(toolchainManager.status.ytDLP == nil ? .orange : .primary)
                }

                LabeledContent("ffmpeg") {
                    Text(toolchainManager.status.ffmpeg?.path ?? "Missing")
                        .foregroundStyle(toolchainManager.status.ffmpeg == nil ? .orange : .primary)
                }

                if !toolchainManager.status.isReady {
                    Text("This app can install missing tools with Homebrew, or you can install them yourself and relaunch.")
                        .foregroundStyle(.secondary)
                    Button(toolchainManager.isInstalling ? "Installing..." : "Install Missing Tools") {
                        viewModel.installMissingTools()
                    }
                    .disabled(toolchainManager.isInstalling)
                }

                if !toolchainManager.installLog.isEmpty {
                    ScrollView {
                        Text(toolchainManager.installLog)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 140)
                }
            }

            Section("Downloads") {
                Picker("Default preset", selection: $preferences.preferredPreset) {
                    ForEach(MediaPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Stepper(value: $preferences.concurrencyLimit, in: 1...4) {
                    Text("Concurrent downloads: \(preferences.concurrencyLimit)")
                }

                LabeledContent("Library folder") {
                    Text(preferences.defaultDestinationPath)
                        .textSelection(.enabled)
                }

                Button("Open Library Folder") {
                    viewModel.openLibraryFolder()
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(width: 560)
    }
}

private extension DownloadJob {
    var failureSummary: String? {
        if case let .failed(failure) = state {
            return failure.technicalDetails
        }
        return nil
    }

    var stateLabel: String {
        switch state {
        case .queued:
            "Queued"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case let .failed(failure):
            failure.category.displayTitle
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
