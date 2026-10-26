import PeekCore
import SwiftUI

/// Shown while a response streams: finished tool calls before any answer text, then the typed status line.
struct ResponseStatus: View {
    let steps: [AIActivity]
    let liveStep: AIActivity?
    let answerStarted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !answerStarted {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    if step.id != liveStep?.id { StepRow(step: step) }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "circle").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tint)
                    .frame(width: 14)
                TypewriterText(text: liveStep?.runningLabel ?? "Responding…")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// One finished tool call.
struct StepRow: View {
    let step: AIActivity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
                .frame(width: 14)
            Text(step.doneLabel).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// The tool calls behind an answer, folded into one line that expands on click.
struct StepsSummary: View {
    let steps: [AIActivity]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.smooth(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(Self.summary(steps))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the steps" : "Shows the steps")
            if isExpanded {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in StepRow(step: step) }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    static func summary(_ steps: [AIActivity]) -> String {
        let searches = steps.count { $0.kind == .searchingWeb }
        let files = steps.count { $0.kind == .readingFiles }
        let commands = steps.count { $0.kind == .runningCommand }
        var parts: [String] = []
        if searches > 0 { parts.append(searches == 1 ? "searched the web" : "searched the web \(searches) times") }
        if files > 0 { parts.append(files == 1 ? "read 1 file" : "read \(files) files") }
        if commands > 0 { parts.append(commands == 1 ? "ran 1 command" : "ran \(commands) commands") }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// Erases back to what the old and new text share, then types the rest, with a blinking caret.
struct TypewriterText: View {
    let text: String
    @State private var shown = ""
    @State private var caretOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 1) {
            Text(shown).lineLimit(1).truncationMode(.middle)
            Rectangle().fill(.tint).frame(width: 1.5, height: 14).opacity(caretOn ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .task(id: text) { await type() }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                caretOn.toggle()
            }
        }
    }

    private func type() async {
        guard !reduceMotion else { shown = text; return }
        while !text.hasPrefix(shown) {
            shown.removeLast()
            guard await pause(.milliseconds(12)) else { return }
        }
        // Long queries type faster so each finishes in under a second.
        let step = Duration.milliseconds(min(30, 800 / max(text.count - shown.count, 1)))
        while shown.count < text.count {
            shown.append(text[text.index(text.startIndex, offsetBy: shown.count)])
            guard await pause(step) else { return }
        }
    }

    private func pause(_ duration: Duration) async -> Bool {
        try? await Task.sleep(for: duration)
        return !Task.isCancelled
    }
}

extension AIActivity {
    var runningLabel: String {
        switch kind {
        case .searchingWeb: detail.map { "Searching: \($0)" } ?? "Searching the web…"
        case .readingFiles: detail.map { "Reading: \($0)" } ?? "Reading attachments…"
        case .runningCommand: detail.map { "Running: \($0)" } ?? "Running a command…"
        }
    }

    var doneLabel: String {
        switch kind {
        case .searchingWeb: detail.map { "Searched: \($0)" } ?? "Searched the web"
        case .readingFiles: detail.map { "Read: \($0)" } ?? "Read attachments"
        case .runningCommand: detail.map { "Ran: \($0)" } ?? "Ran a command"
        }
    }
}
