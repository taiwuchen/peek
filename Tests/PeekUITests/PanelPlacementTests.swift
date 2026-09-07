import CoreGraphics
import Testing
@testable import PeekUI

@Test func placesBelowTopLeftAnchor() {
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 200, width: 100, height: 30),
                             panelSize: CGSize(width: 420, height: 220),
                             visibleFrames: [CGRect(x: 0, y: 25, width: 1440, height: 850)],
                             primaryScreenHeight: 900, mouseLocation: .zero)
    #expect(origin == CGPoint(x: 300, y: 440))
}

@Test func placesAboveWhenBelowDoesNotFit() {
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 750, width: 100, height: 30),
                             panelSize: CGSize(width: 420, height: 220),
                             visibleFrames: [CGRect(x: 0, y: 25, width: 1440, height: 850)],
                             primaryScreenHeight: 900, mouseLocation: .zero)
    #expect(origin == CGPoint(x: 300, y: 160))
}

@Test func placesBesideTallCapture() {
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 100, width: 100, height: 700),
                             panelSize: CGSize(width: 420, height: 220),
                             visibleFrames: [CGRect(x: 0, y: 25, width: 1440, height: 850)],
                             primaryScreenHeight: 900, mouseLocation: .zero)
    #expect(origin == CGPoint(x: 410, y: 340))
}

@Test func placesOnDisplayAbovePrimary() {
    let origin = panelOrigin(anchor: CGRect(x: 200, y: -600, width: 100, height: 30),
                             panelSize: CGSize(width: 420, height: 220),
                             visibleFrames: [CGRect(x: 0, y: 25, width: 1440, height: 850),
                                             CGRect(x: 0, y: 900, width: 1440, height: 875)],
                             primaryScreenHeight: 900, mouseLocation: .zero)
    #expect(origin == CGPoint(x: 200, y: 1240))
}

@Test func usesMouseDisplayAndClampsEdges() {
    let display = CGRect(x: -1280, y: 0, width: 1280, height: 800)
    let size = CGSize(width: 420, height: 220)
    let origin = panelOrigin(anchor: nil, panelSize: size,
                             visibleFrames: [CGRect(x: 0, y: 25, width: 1440, height: 850), display],
                             primaryScreenHeight: 900, mouseLocation: CGPoint(x: -30, y: 780))
    #expect(display.contains(CGRect(origin: origin, size: size)))
    #expect(origin.x == -420)
}

@Test func missingScreensAndOversizedPanelsRemainDefined() {
    let mouse = CGPoint(x: 20, y: 30)
    #expect(panelOrigin(anchor: nil, panelSize: CGSize(width: 400, height: 300), visibleFrames: [],
                        primaryScreenHeight: 900, mouseLocation: mouse) == mouse)
    #expect(panelOrigin(anchor: nil, panelSize: CGSize(width: 1400, height: 1000),
                        visibleFrames: [CGRect(x: -900, y: 0, width: 900, height: 700)],
                        primaryScreenHeight: 900, mouseLocation: CGPoint(x: -500, y: 100)) == CGPoint(x: -900, y: 0))
}
