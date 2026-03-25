import Foundation
import Testing
@testable import YTDLPGUI

@MainActor
struct PreferencesStoreTests {
    @Test
    func loadsDefaultsFromUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(MediaPreset.bestAudio.rawValue, forKey: "preferredPreset")
        defaults.set("/tmp/downloads", forKey: "defaultDestinationPath")
        defaults.set(3, forKey: "concurrencyLimit")

        let store = PreferencesStore(defaults: defaults)

        #expect(store.preferredPreset == .bestAudio)
        #expect(store.defaultDestinationPath == "/tmp/downloads")
        #expect(store.concurrencyLimit == 3)
    }

    @Test
    func usesMoviesLibraryFolderByDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.removeObject(forKey: "defaultDestinationPath")

        let store = PreferencesStore(defaults: defaults)

        #expect(store.defaultDestinationPath.hasSuffix("/Movies/ytdlp-gui"))
    }
}
