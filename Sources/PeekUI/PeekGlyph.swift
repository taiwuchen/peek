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
}
