import AppKit
import PeekCapture
import PeekCore
import PeekProviders
import PeekUI
import Sparkle
import SwiftUI

@main
struct PeekApp: App {
    @NSApplicationDelegateAdaptor(PeekAppDelegate.self) private var delegate

    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class PeekAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = UserDefaultsSettingsStore()
        let credentials = KeychainCredentialStore(service: "\(Bundle.main.bundleIdentifier!).api-keys")
        // Only prod has a feed, so Peek Dev never updates itself.
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let updater = feed.isEmpty ? nil : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                                         userDriverDelegate: nil)
        self.updater = updater
        let controller = AppController(
            regionCapturer: RegionCapturer(),
            providers: cliProviders(settings: settings) + apiProviders(credentials: credentials),
            settingsStore: settings,
            credentials: credentials,
            checkForUpdates: updater.map { updater in { updater.checkForUpdates(nil) } }
        )
        self.controller = controller
        controller.start()
    }
}
