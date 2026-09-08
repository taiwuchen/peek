import AppKit
import KeyboardShortcuts
import PeekCore
import SwiftUI

@MainActor
public final class AppController: NSObject, NSMenuDelegate {
    private let regionCapturer: any ScreenRegionCapturer
    private let providers: [any AIProvider]
    private let settingsStore: any SettingsStore
    private let settingsModel: SettingsModel
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    /// Open conversation windows, one per capture, oldest first.
    private(set) var conversations: [AnswerPanel] = []

    public init(regionCapturer: any ScreenRegionCapturer,
                providers: [any AIProvider], settingsStore: any SettingsStore, credentials: any CredentialStore) {
        self.regionCapturer = regionCapturer
        self.providers = providers
        self.settingsStore = settingsStore
        settingsModel = SettingsModel(providers: providers, store: settingsStore, credentials: credentials)
        super.init()
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
    }

    public func menuWillOpen(_ menu: NSMenu) { KeyboardShortcuts.disable(.askRegion) }
    public func menuDidClose(_ menu: NSMenu) { KeyboardShortcuts.enable(.askRegion) }

    /// Starts a new conversation in its own window. Ignored while a region selection is already open.
    @objc func askRegion() {
        guard !conversations.contains(where: { $0.session.isCapturing }) else { return }
        let session = AskSession(regionCapturer: regionCapturer, providers: providers, settingsStore: settingsStore)
        let panel = AnswerPanel(session: session, openSettings: { [weak self] in self?.showSettings() })
        session.onSettingsChange = { [weak self] in
            guard let self else { return }
            settingsModel.settings = settingsStore.load()
        }
        session.onPresent = { [weak panel] in
            guard let panel else { return }
            panel.present(anchor: panel.session.latestCapture?.anchor)
        }
        session.onCaptureCancelled = { [weak panel] in panel?.close() }
        panel.onClose = { [weak self, weak panel] in self?.conversations.removeAll { $0 === panel } }
        conversations.append(panel)
        session.beginCapture()
    }

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
