import AppKit
import PeekCore
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
        let controller = AppController(selectionReader: StubSelectionReader(), regionCapturer: StubRegionCapturer(),
                                       providers: [EchoProvider()], settingsStore: UserDefaultsSettingsStore(),
                                       credentials: KeychainCredentialStore())
        self.controller = controller
        controller.start()
    }
}
