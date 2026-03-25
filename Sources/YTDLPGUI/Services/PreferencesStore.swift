import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    static let uiTestLibraryPathEnvironmentKey = "YTDLPGUI_UI_TEST_LIBRARY_PATH"

    @Published var preferredPreset: MediaPreset {
        didSet { defaults.set(preferredPreset.rawValue, forKey: Keys.preferredPreset) }
    }
    @Published var preferredDownloadMode: DownloadMode {
        didSet { defaults.set(preferredDownloadMode.rawValue, forKey: Keys.preferredDownloadMode) }
    }
    @Published var preferredMusicPreset: MusicFormatPreset {
        didSet { defaults.set(preferredMusicPreset.rawValue, forKey: Keys.preferredMusicPreset) }
    }
    @Published var defaultDestinationPath: String {
        didSet { defaults.set(defaultDestinationPath, forKey: Keys.defaultDestinationPath) }
    }
    @Published var concurrencyLimit: Int {
        didSet { defaults.set(concurrencyLimit, forKey: Keys.concurrencyLimit) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let preferredPreset = "preferredPreset"
        static let preferredDownloadMode = "preferredDownloadMode"
        static let preferredMusicPreset = "preferredMusicPreset"
        static let defaultDestinationPath = "defaultDestinationPath"
        static let concurrencyLimit = "concurrencyLimit"
    }

    static var defaultLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("ytdlp-gui", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let uiTestLibraryPath = ProcessInfo.processInfo.environment[Self.uiTestLibraryPathEnvironmentKey]
        if let uiTestLibraryPath {
            try? FileManager.default.createDirectory(atPath: uiTestLibraryPath, withIntermediateDirectories: true)
        } else {
            try? FileManager.default.createDirectory(at: Self.defaultLibraryURL, withIntermediateDirectories: true)
        }

        preferredPreset = MediaPreset(rawValue: defaults.string(forKey: Keys.preferredPreset) ?? "") ?? .bestVideo
        preferredDownloadMode = DownloadMode(rawValue: defaults.string(forKey: Keys.preferredDownloadMode) ?? "") ?? .video
        preferredMusicPreset = MusicFormatPreset(rawValue: defaults.string(forKey: Keys.preferredMusicPreset) ?? "") ?? .bestQualityMP3
        defaultDestinationPath = uiTestLibraryPath ?? defaults.string(forKey: Keys.defaultDestinationPath) ?? Self.defaultLibraryURL.path
        let storedLimit = defaults.integer(forKey: Keys.concurrencyLimit)
        concurrencyLimit = storedLimit > 0 ? storedLimit : 2
    }
}
