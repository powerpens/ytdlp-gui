import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct YTDLPGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = PreferencesStore()
    @StateObject private var toolchainManager = ToolchainManager()
    @StateObject private var cookieManager = CookieManager()
    @StateObject private var viewModel: AppViewModel

    init() {
        let preferences = PreferencesStore()
        let toolchainManager = ToolchainManager()
        let cookieManager = CookieManager()
        _preferences = StateObject(wrappedValue: preferences)
        _toolchainManager = StateObject(wrappedValue: toolchainManager)
        _cookieManager = StateObject(wrappedValue: cookieManager)
        _viewModel = StateObject(
            wrappedValue: AppViewModel(
                preferences: preferences,
                toolchainManager: toolchainManager,
                cookieManager: cookieManager,
                historyStore: HistoryStore()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(preferences)
                .environmentObject(toolchainManager)
                .environmentObject(cookieManager)
                .environmentObject(viewModel)
                .frame(minWidth: 960, minHeight: 720)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(toolchainManager)
                .environmentObject(viewModel)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Start Download") {
                    viewModel.startDownload()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!viewModel.canStartDownload)

                Button("Choose Destination...") {
                    viewModel.chooseDestination()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Import Cookie File...") {
                    cookieManager.importCookieFile()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])

                Divider()

                Button("Paste URL from Clipboard") {
                    viewModel.pasteFromClipboard()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Quick Look") {
                    viewModel.quickLookSelectedLibraryItem()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!viewModel.canQuickLookSelectedLibraryItem)
            }
        }
    }
}
