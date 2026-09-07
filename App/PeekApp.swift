import AppKit
import PeekCapture
import PeekCore
import PeekProviders
import PeekUI
import SwiftUI

@main
struct PeekApp: App {
    var body: some Scene {
        // Menu bar only (LSUIElement). PeekUI owns the status item, hotkey, and answer panel.
        Settings {
            Text("Settings are provided by PeekUI once implemented.")
                .frame(width: 320, height: 120)
        }
    }
}
