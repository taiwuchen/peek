import AppKit

/// The Peek callout-P mark as a template image for the menu bar and in-app labels.
@MainActor
enum PeekGlyph {
    static let template: NSImage = {
        let url = Bundle.module.url(forResource: "PeekGlyph", withExtension: "pdf")!
        let image = NSImage(contentsOf: url)!
        image.isTemplate = true
        image.size = NSSize(width: 15, height: 18)
        image.accessibilityDescription = "Peek"
        return image
    }()

    /// Orange, non-template variant so Peek Dev stands out from prod in the menu bar.
    static let qa: NSImage = {
        let glyph = template
        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.draw(in: rect)
            NSColor.systemOrange.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.accessibilityDescription = "Peek Dev"
        return image
    }()
}
