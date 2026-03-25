import Foundation
import Testing
@testable import YTDLPGUI

@MainActor
struct PreferencesStoreTests {
    @Test
    func loadsDefaultsFromUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(MediaPreset.bestAudio.rawValue, forKey: "preferredPreset")
        defaults.set(DownloadMode.spotifyMusic.rawValue, forKey: "preferredDownloadMode")
        defaults.set(MusicFormatPreset.aacM4A.rawValue, forKey: "preferredMusicPreset")
        defaults.set("/tmp/downloads", forKey: "defaultDestinationPath")
        defaults.set(3, forKey: "concurrencyLimit")

        let store = PreferencesStore(defaults: defaults)

        #expect(store.preferredPreset == .bestAudio)
        #expect(store.preferredDownloadMode == .spotifyMusic)
        #expect(store.preferredMusicPreset == .aacM4A)
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
