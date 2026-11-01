import AppKit
import Carbon.HIToolbox
@preconcurrency import KeyboardShortcuts
import SwiftUI

/// Shows a recorded shortcut as keycaps; click to record a new one.
struct ShortcutKeys: View {
    let name: KeyboardShortcuts.Name
    let label: String
    /// Names the owner when a different shortcut name already uses this shortcut.
    let conflict: (KeyboardShortcuts.Shortcut, KeyboardShortcuts.Name) -> String?
    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var monitor: Any?
    @State private var notice: String?
    @State private var frame = CGRect.zero
    @State private var shortcutsWereEnabled = true

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggleRecording) { keycaps }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .help(isRecording ? "Press a shortcut, Delete to clear it, or Escape to cancel" : "Record a shortcut")
                .accessibilityLabel(accessibilityText)
            if let notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
        .onDisappear(perform: stopRecording)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            stopRecording()
        }
    }

    @ViewBuilder private var keycaps: some View {
        if isRecording {
            placeholder("Type shortcut", border: Color.accentColor, dashed: false)
        } else if let shortcut {
            HStack(spacing: 4) {
                ForEach(Array(Self.keys(of: shortcut.description).enumerated()), id: \.offset) { _, key in
                    Keycap(text: key)
                }
            }
            .padding(3)
            .contentShape(Rectangle())
        } else {
            placeholder("Add shortcut", border: Color(nsColor: .tertiaryLabelColor), dashed: true)
        }
    }

    private func placeholder(_ text: String, border: Color, dashed: Bool) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3] : [])))
            .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        if isRecording { return "Recording a shortcut for \(label)" }
        return shortcut.map { "Shortcut for \(label): \($0.description)" } ?? "Add a shortcut for \(label)"
    }

    private func toggleRecording() {
        if isRecording { return stopRecording() }
        notice = nil
        // Free every global shortcut so the keys reach this window while recording.
        shortcutsWereEnabled = KeyboardShortcuts.isEnabled
        KeyboardShortcuts.isEnabled = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            handle(event)
        }
        if monitor == nil { KeyboardShortcuts.isEnabled = shortcutsWereEnabled }
    }

    private func stopRecording() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        KeyboardShortcuts.isEnabled = shortcutsWereEnabled
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else {
            // A click anywhere but the keycaps cancels; a click on them is handled by the button.
            if !frame.contains(Self.topLeftLocation(of: event)) { stopRecording() }
            return event
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let keyCode = Int(event.keyCode)
        if modifiers.isEmpty, keyCode == kVK_Escape {
            stopRecording()
            return nil
        }
        if modifiers.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            stopRecording()
            save(nil)
            return nil
        }
        guard !modifiers.subtracting(.shift).isEmpty || Self.functionKeys.contains(keyCode),
              let new = KeyboardShortcuts.Shortcut(event: event) else {
            NSSound.beep()
            notice = "Include ⌘, ⌥ or ⌃."
            return nil
        }
        if let owner = conflict(new, name) {
            NSSound.beep()
            notice = "\(new.description) is already used by \(owner)."
            return nil
        }
        stopRecording()
        save(new)
        return nil
    }

    private func save(_ new: KeyboardShortcuts.Shortcut?) {
        KeyboardShortcuts.setShortcut(new, for: name)
        shortcut = KeyboardShortcuts.getShortcut(for: name)
        notice = nil
    }

    /// The event's location in the hosting view's top-left coordinates, matching SwiftUI's global space.
    private static func topLeftLocation(of event: NSEvent) -> CGPoint {
        let height = event.window?.contentView?.bounds.height ?? 0
        return CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    /// Splits a description such as "⌥⇧Space" into its modifier symbols and its key.
    static func keys(of description: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var keys = description.prefix { modifiers.contains($0) }.map(String.init)
        let key = description.drop { modifiers.contains($0) }
        if !key.isEmpty { keys.append(String(key)) }
        return keys
    }
}

private struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 26)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
