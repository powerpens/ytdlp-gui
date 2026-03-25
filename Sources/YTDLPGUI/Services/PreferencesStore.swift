import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var preferredPreset: MediaPreset {
        didSet { defaults.set(preferredPreset.rawValue, forKey: Keys.preferredPreset) }
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
        static let defaultDestinationPath = "defaultDestinationPath"
        static let concurrencyLimit = "concurrencyLimit"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredPreset = MediaPreset(rawValue: defaults.string(forKey: Keys.preferredPreset) ?? "") ?? .bestVideo
        defaultDestinationPath = defaults.string(forKey: Keys.defaultDestinationPath) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        let storedLimit = defaults.integer(forKey: Keys.concurrencyLimit)
        concurrencyLimit = storedLimit > 0 ? storedLimit : 2
    }
}
