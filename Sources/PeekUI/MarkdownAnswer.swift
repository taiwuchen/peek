import AppKit
import SwiftUI

/// An answer rendered from Markdown into one text view, so the whole answer can be selected at once.
struct MarkdownAnswer: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(frame: .zero)
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        // Re-rendering resets the selection, so only do it when the answer changed.
        guard context.coordinator.text != text else { return }
        context.coordinator.text = text
        view.textStorage?.setAttributedString(AnswerText.attributed(text))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        // Measure in a scratch layout; resizing the live text view here would leave it at a probe width.
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        let storage = NSTextStorage(attributedString: nsView.attributedString())
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }

    final class Coordinator {
        var text: String?
    }
}

/// Converts Markdown into one attributed string with paragraphs, lists, code, quotes, and tables.
enum AnswerText {
    private static let bodySize = NSFont.systemFontSize
    private static let indent: CGFloat = 16

    static func attributed(_ markdown: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        guard let source = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: attributes(for: []))
        }
        let result = NSMutableAttributedString()
        var lastBlocks: [PresentationIntent.IntentType] = []
        var lastItem: Int?
        for run in source.runs {
            let blocks = run.presentationIntent?.components ?? []
            let isNewBlock = blocks.first?.identity != lastBlocks.first?.identity
            if isNewBlock && result.length > 0 {
                result.append(separator(from: lastBlocks, to: blocks))
            }
            if isNewBlock, let item = blocks.first(where: \.isListItem), item.identity != lastItem {
                result.append(NSAttributedString(string: marker(for: item, in: blocks) + "\t",
                                                 attributes: attributes(for: blocks)))
                lastItem = item.identity
            }
            var text = String(source[run.range].characters)
            if blocks.contains(where: \.isCodeBlock), text.hasSuffix("\n") { text.removeLast() }
            var runAttributes = attributes(for: blocks)
            applyInline(run.inlinePresentationIntent, to: &runAttributes)
            if let link = run.link { runAttributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: runAttributes))
            lastBlocks = blocks
        }
        return result
    }

    /// Cells in one table row share a line, list items stack tightly, and other blocks get a short blank line.
    private static func separator(from previous: [PresentationIntent.IntentType],
                                  to next: [PresentationIntent.IntentType]) -> NSAttributedString {
        let previousRow = previous.first(where: \.isTableRow)?.identity
        if let row = next.first(where: \.isTableRow)?.identity, row == previousRow {
            return NSAttributedString(string: "\t", attributes: attributes(for: next))
        }
        let separator = NSMutableAttributedString(string: "\n", attributes: attributes(for: previous))
        let tight = (previous.contains(where: \.isListItem) && next.contains(where: \.isListItem))
            || (previousRow != nil && next.contains(where: \.isTableRow))
        if !tight {
            separator.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 5)]))
        }
        return separator
    }

    private static func marker(for item: PresentationIntent.IntentType, in blocks: [PresentationIntent.IntentType]) -> String {
        guard case .listItem(let ordinal) = item.kind,
              let index = blocks.firstIndex(where: { $0.identity == item.identity }),
              blocks.indices.contains(index + 1), case .orderedList = blocks[index + 1].kind else { return "•" }
        return "\(ordinal)."
    }

    private static func attributes(for blocks: [PresentationIntent.IntentType]) -> [NSAttributedString.Key: Any] {
        var font = NSFont.systemFont(ofSize: bodySize)
        var color = NSColor.labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        var result: [NSAttributedString.Key: Any] = [:]
        let depth = blocks.filter(\.isListItem).count
        if depth > 0 {
            paragraph.firstLineHeadIndent = indent * CGFloat(depth - 1)
            paragraph.headIndent = indent * CGFloat(depth)
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent * CGFloat(depth))]
        }
        for block in blocks {
            switch block.kind {
            case .header(let level):
                font = .systemFont(ofSize: bodySize + max(0, CGFloat(4 - level)) * 2, weight: .semibold)
            case .codeBlock:
                font = .monospacedSystemFont(ofSize: bodySize - 1, weight: .regular)
                result[.backgroundColor] = NSColor.quaternaryLabelColor
            case .blockQuote:
                color = .secondaryLabelColor
                paragraph.firstLineHeadIndent += indent
                paragraph.headIndent += indent
            case .tableHeaderRow:
                font = .systemFont(ofSize: bodySize, weight: .semibold)
            default:
                break
            }
        }
        result[.font] = font
        result[.foregroundColor] = color
        result[.paragraphStyle] = paragraph
        return result
    }

    private static func applyInline(_ intent: InlinePresentationIntent?, to attributes: inout [NSAttributedString.Key: Any]) {
        guard let intent, var font = attributes[.font] as? NSFont else { return }
        if intent.contains(.code) {
            font = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular)
            attributes[.backgroundColor] = NSColor.quaternaryLabelColor
        }
        if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        attributes[.font] = font
    }
}

private extension PresentationIntent.IntentType {
    var isListItem: Bool { if case .listItem = kind { true } else { false } }
    var isCodeBlock: Bool { if case .codeBlock = kind { true } else { false } }
    var isTableRow: Bool {
        switch kind {
        case .tableRow, .tableHeaderRow: true
        default: false
        }
    }
}
