import AppKit
import KeyboardShortcuts
import SwiftUI

/// Shows a recorded shortcut as keycaps; clicking records a new one with the library recorder.
struct ShortcutKeys: View {
    let name: KeyboardShortcuts.Name
    let label: String
    /// Names the owner when a different shortcut name already uses this shortcut.
    let conflict: (KeyboardShortcuts.Shortcut, KeyboardShortcuts.Name) -> String?
    @State private var shortcut: KeyboardShortcuts.Shortcut?
    @State private var previous: KeyboardShortcuts.Shortcut?
    @State private var isRecording = false
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isRecording {
                FocusedRecorder(name: name, onChange: changed) { isRecording = false }
                    .frame(width: 150, height: 24)
            } else {
                Button(action: startRecording) { keycaps }
                    .buttonStyle(.plain)
                    .help(shortcut == nil ? "Record a shortcut" : "Record a new shortcut")
                    .accessibilityLabel(shortcut.map { "Shortcut for \(label): \($0.description)" } ?? "Add a shortcut for \(label)")
            }
            if let notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { shortcut = KeyboardShortcuts.getShortcut(for: name) }
    }

    @ViewBuilder private var keycaps: some View {
        if let shortcut {
            HStack(spacing: 4) {
                ForEach(Array(Self.keys(of: shortcut.description).enumerated()), id: \.offset) { _, key in
                    Keycap(text: key)
                }
            }
            .padding(3)
            .contentShape(Rectangle())
        } else {
            Text("Add shortcut")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3])))
                .contentShape(Rectangle())
        }
    }

    private func startRecording() {
        previous = shortcut
        notice = nil
        isRecording = true
    }

    /// Restores the previous shortcut when the new one clashes with another mode or the capture shortcut.
    private func changed(_ new: KeyboardShortcuts.Shortcut?) {
        if let new, let owner = conflict(new, name) {
            KeyboardShortcuts.setShortcut(previous, for: name)
            notice = "\(new.description) is already used by \(owner)."
        } else {
            notice = nil
        }
        shortcut = KeyboardShortcuts.getShortcut(for: name)
    }

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

/// The library recorder, focused as soon as it appears; reports when recording ends.
private struct FocusedRecorder: NSViewRepresentable {
    let name: KeyboardShortcuts.Name
    let onChange: (KeyboardShortcuts.Shortcut?) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnd: onEnd) }

    func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
        let recorder = KeyboardShortcuts.RecorderCocoa(for: name, onChange: onChange)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.ended(_:)),
                                               name: NSControl.textDidEndEditingNotification, object: recorder)
        // The recorder refuses focus until the run loop turn after it joins a window.
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            recorder.window?.makeFirstResponder(recorder)
        }
        return recorder
    }

    func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    @MainActor final class Coordinator: NSObject {
        var onEnd: () -> Void

        init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }

        @objc func ended(_ notification: Notification) { onEnd() }
    }
}
