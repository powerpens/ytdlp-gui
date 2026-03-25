import AppKit
import Foundation

@MainActor
final class CookieManager: ObservableObject {
    @Published var selectedSource: CookieSource = .none
    @Published var importedFileName: String?

    func useBrowser(_ browser: BrowserCookieSource) {
        selectedSource = .browser(browser)
        importedFileName = nil
    }

    func clearSelection() {
        selectedSource = .none
        importedFileName = nil
    }

    func importCookieFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Cookie File"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        selectedSource = .file(path: url.path)
        importedFileName = url.lastPathComponent
    }

    func validate(source: CookieSource) -> Bool {
        switch source {
        case .none, .browser:
            true
        case let .file(path):
            FileManager.default.fileExists(atPath: path)
        }
    }
}
