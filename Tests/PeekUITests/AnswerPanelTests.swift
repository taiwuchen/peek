import AppKit
import PeekCore
import Testing
@testable import PeekUI

private struct ImageRegion: ScreenRegionCapturer {
    func captureRegion() async throws -> Capture {
        let image = NSImage(size: NSSize(width: 400, height: 130), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        return Capture(content: .image(png), anchor: nil, sourceBundleID: nil)
    }
}

@MainActor
private func waitingPanel() async throws -> AnswerPanel {
    let mode = PromptMode(name: "Explain", prompt: "Explain this", waitsForContext: true)
    let store = UserDefaultsSettingsStore(defaults: UserDefaults(suiteName: "PeekUITests.\(UUID())")!)
    store.save(AppSettings(modes: [mode], selectedModeID: mode.id))
    let session = AskSession(regionCapturer: ImageRegion(), providers: [TestProvider()], settingsStore: store)
    let panel = AnswerPanel(session: session, openSettings: {})
    session.onPresent = { [weak panel] in panel?.present(anchor: nil) }
    session.beginCapture()
    let deadline = ContinuousClock.now + .seconds(3)
    while session.draft.isEmpty && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(!session.draft.isEmpty)
    return panel
}

@MainActor
private func composerScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let scrollView = subview as? NSScrollView, scrollView.documentView is ComposerTextView { return scrollView }
        if let match = composerScrollView(in: subview) { return match }
    }
    return nil
}

@Test @MainActor func draftComposerTextFillsItsWidth() async throws {
    let panel = try await waitingPanel()
    defer { panel.close() }
    for text in ["w", "what", "what do you", "what do you see?"] {
        panel.session.question = text
        try await Task.sleep(for: .milliseconds(20))
        panel.contentView?.layoutSubtreeIfNeeded()
    }
    let content = try #require(panel.contentView)
    let scrollView = try #require(composerScrollView(in: content))
    let input = try #require(scrollView.documentView)
    #expect(scrollView.contentSize.width > 300)
    #expect(abs(input.frame.width - scrollView.contentSize.width) < 1)
}

@Test @MainActor func panelStaysCompactUntilSentThenExpandsInPlace() async throws {
    let panel = try await waitingPanel()
    defer { panel.close() }
    let compact = panel.frame
    #expect(compact.height < 250)
    panel.session.question = "what do you see?"
    panel.session.send()
    let deadline = ContinuousClock.now + .seconds(3)
    while panel.frame.height < 500 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(panel.frame.height == 500)
    // Placement reserves the full height, so the panel keeps the edge nearest the cursor.
    #expect(panel.frame.maxY == compact.maxY || panel.frame.minY == compact.minY)
}
