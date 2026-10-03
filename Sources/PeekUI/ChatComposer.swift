import AppKit
import PeekCore
import SwiftUI

struct ChatComposer: NSViewRepresentable {
    @Binding var text: String
    var placeholder = "Ask a follow-up"
    let onSubmit: () -> Void
    let onAttachments: ([Capture.Content]) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let input = ComposerTextView(frame: .zero)
        input.isRichText = false
        input.importsGraphics = false
        input.allowsUndo = true
        input.drawsBackground = false
        input.font = .systemFont(ofSize: NSFont.systemFontSize)
        input.textColor = .labelColor
        input.insertionPointColor = .labelColor
        input.textContainerInset = NSSize(width: 2, height: 8)
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.minSize = .zero
        input.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        input.delegate = context.coordinator
        scrollView.documentView = input
        updateNSView(scrollView, context: context)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.composer = self
        guard let input = scrollView.documentView as? ComposerTextView else { return }
        input.onSubmit = onSubmit
        input.onAttachments = onAttachments
        input.onError = onError
        if input.placeholder != placeholder {
            input.placeholder = placeholder
            input.setAccessibilityLabel(placeholder)
            input.needsDisplay = true
        }
        if input.string != text {
            input.string = text
            input.needsDisplay = true
            input.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let input = nsView.documentView as? ComposerTextView,
              let container = input.textContainer, let layout = input.layoutManager else { return nil }
        input.setFrameSize(NSSize(width: width, height: max(34, input.frame.height)))
        container.containerSize.width = max(1, width - input.textContainerInset.width * 2)
        layout.ensureLayout(for: container)
        let textHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        let height = textHeight + input.textContainerInset.height * 2
        return CGSize(width: width, height: min(100, max(34, height)))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var composer: ChatComposer

        init(_ composer: ChatComposer) { self.composer = composer }

        func textDidChange(_ notification: Notification) {
            guard let input = notification.object as? ComposerTextView else { return }
            composer.text = input.string
            input.needsDisplay = true
            input.invalidateIntrinsicContentSize()
        }
    }
}

@MainActor
final class ComposerTextView: NSTextView {
    var onSubmit: () -> Void = {}
    var onAttachments: ([Capture.Content]) -> Void = { _ in }
    var placeholder = ""
    var onError: (String) -> Void = { _ in }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        AttachmentInput.dragTypes + super.readablePasteboardTypes
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        AttachmentInput.dragTypes + super.acceptableDragTypes
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if attachFiles(from: pasteboard) { return true }
        return super.readSelection(from: pasteboard, type: type)
    }

    /// A plain text view refuses image drags and inserts file paths, so claim attachments before it can.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard AttachmentInput.containsAttachments(sender.draggingPasteboard) else { return super.draggingEntered(sender) }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard AttachmentInput.containsAttachments(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        return attachFiles(from: sender.draggingPasteboard)
    }

    /// Attaches any images or files on `pasteboard`, leaving the draft text untouched.
    /// Returns whether the pasteboard was handled as attachment input.
    func attachFiles(from pasteboard: NSPasteboard) -> Bool {
        do {
            guard let contents = try AttachmentInput.attachments(from: pasteboard) else { return false }
            onAttachments(contents)
        } catch {
            onError(error.localizedDescription)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !hasMarkedText() {
            if event.modifierFlags.contains(.shift) {
                insertLineBreak(nil)
            } else {
                onSubmit()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() {
            super.insertNewline(sender)
        } else {
            onSubmit()
        }
    }

    override func insertLineBreak(_ sender: Any?) {
        super.insertNewline(sender)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window, window.firstResponder === window {
            window.makeFirstResponder(self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.placeholderTextColor,
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }
}
