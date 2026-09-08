import AppKit
import KeyboardShortcuts
import PeekCore
import SwiftUI

@MainActor
public final class AppController: NSObject, NSMenuDelegate {
    private let session: AskSession
    private let settingsModel: SettingsModel
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private lazy var panel = AnswerPanel(session: session, openSettings: { [weak self] in self?.showSettings() })

    public init(regionCapturer: any ScreenRegionCapturer,
                providers: [any AIProvider], settingsStore: any SettingsStore, credentials: any CredentialStore) {
        session = AskSession(regionCapturer: regionCapturer, providers: providers, settingsStore: settingsStore)
        settingsModel = SettingsModel(providers: providers, store: settingsStore, credentials: credentials)
        super.init()
        session.onSettingsChange = { [weak self] in self?.settingsModel.settings = settingsStore.load() }
    }

    public func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = PeekGlyph.template
        let menu = NSMenu()
        menu.delegate = self
        let region = menu.addItem(withTitle: "Ask about screen region", action: #selector(askRegion), keyEquivalent: "")
        region.target = self
        region.setShortcut(for: .askRegion)
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        let quit = menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        item.menu = menu
        statusItem = item
        KeyboardShortcuts.onKeyUp(for: .askRegion) { [weak self] in self?.askRegion() }
        session.onPresent = { [weak self] in
            guard let self else { return }
            panel.present(anchor: session.latestCapture?.anchor)
        }
    }

    public func menuWillOpen(_ menu: NSMenu) { KeyboardShortcuts.disable(.askRegion) }
    public func menuDidClose(_ menu: NSMenu) { KeyboardShortcuts.enable(.askRegion) }

    @objc private func askRegion() { session.beginCapture() }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 584, height: 594),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Peek Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: settingsModel))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        Task { await settingsModel.refreshAvailability() }
    }
}
