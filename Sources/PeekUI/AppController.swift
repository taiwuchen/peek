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
    private static let dismissShortcut = KeyboardShortcuts.Name("dismissAnswer")
    private lazy var panel = AnswerPanel(session: session, openSettings: { [weak self] in self?.showSettings() },
                                        onDismiss: { [weak self] in
        self?.session.cancel()
        KeyboardShortcuts.disable(Self.dismissShortcut)
    })

    public init(selectionReader: any SelectionReader, regionCapturer: any ScreenRegionCapturer,
                providers: [any AIProvider], settingsStore: any SettingsStore, credentials: any CredentialStore) {
        session = AskSession(selectionReader: selectionReader, regionCapturer: regionCapturer,
                             providers: providers, settingsStore: settingsStore)
        settingsModel = SettingsModel(providers: providers, store: settingsStore, credentials: credentials)
        super.init()
    }

    public func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = PeekGlyph.template
        let menu = NSMenu()
        menu.delegate = self
        let selection = menu.addItem(withTitle: "Ask about selection", action: #selector(askSelection), keyEquivalent: "")
        selection.target = self
        selection.setShortcut(for: .askSelection)
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
        KeyboardShortcuts.onKeyUp(for: .askSelection) { [weak self] in self?.askSelection() }
        KeyboardShortcuts.onKeyUp(for: .askRegion) { [weak self] in self?.askRegion() }
        KeyboardShortcuts.setShortcut(.init(.escape), for: Self.dismissShortcut)
        KeyboardShortcuts.onKeyUp(for: Self.dismissShortcut) { [weak self] in self?.panel.dismiss() }
        KeyboardShortcuts.disable(Self.dismissShortcut)
        session.onPresent = { [weak self] in
            guard let self else { return }
            panel.present(anchor: session.capture?.anchor)
            KeyboardShortcuts.enable(Self.dismissShortcut)
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        panel.dismiss()
        KeyboardShortcuts.disable(.askSelection, .askRegion)
    }
    public func menuDidClose(_ menu: NSMenu) { KeyboardShortcuts.enable(.askSelection, .askRegion) }

    @objc private func askSelection() { panel.dismiss(); session.begin(.selection) }
    @objc private func askRegion() { panel.dismiss(); session.begin(.region) }

    @objc private func showSettings() {
        panel.dismiss()
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
