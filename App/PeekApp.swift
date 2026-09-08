import AppKit
import PeekCapture
import PeekCore
import PeekProviders
import PeekUI
import SwiftUI

@main
struct PeekApp: App {
    @NSApplicationDelegateAdaptor(PeekAppDelegate.self) private var delegate

    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class PeekAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = UserDefaultsSettingsStore()
        let credentials = KeychainCredentialStore()
        let controller = AppController(
            regionCapturer: RegionCapturer(),
            providers: apiProviders(credentials: credentials) + cliProviders(settings: settings),
            settingsStore: settings,
            credentials: credentials
        )
        self.controller = controller
        controller.start()
    }
}
