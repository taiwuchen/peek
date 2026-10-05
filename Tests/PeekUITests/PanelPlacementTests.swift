import CoreGraphics
import Testing
@testable import PeekUI

private let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
private let panel = CGSize(width: 420, height: 220)

@Test func placesTopLeftAtCursor() {
    // Dragged down-right: the cursor ends at the capture's bottom-right corner.
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 200, width: 100, height: 30), panelSize: panel,
                             visibleFrames: [screen], primaryScreenHeight: 900, mouseLocation: CGPoint(x: 400, y: 670))
    #expect(origin == CGPoint(x: 410, y: 440))
}

@Test func flipsLeftNearRightEdge() {
    let origin = panelOrigin(anchor: CGRect(x: 1200, y: 200, width: 100, height: 30), panelSize: panel,
                             visibleFrames: [screen], primaryScreenHeight: 900, mouseLocation: CGPoint(x: 1300, y: 670))
    #expect(origin == CGPoint(x: 870, y: 440))
}

@Test func flipsAboveNearBottomEdge() {
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 770, width: 100, height: 30), panelSize: panel,
                             visibleFrames: [screen], primaryScreenHeight: 900, mouseLocation: CGPoint(x: 400, y: 100))
    #expect(origin == CGPoint(x: 410, y: 110))
}

@Test func avoidsCaptureAfterReverseDrag() {
    // Dragged up-left: the cursor ends at the capture's top-left corner, so below-right would cover it.
    let origin = panelOrigin(anchor: CGRect(x: 600, y: 300, width: 200, height: 100), panelSize: panel,
                             visibleFrames: [screen], primaryScreenHeight: 900, mouseLocation: CGPoint(x: 600, y: 600))
    #expect(origin == CGPoint(x: 170, y: 370))
}

@Test func slidesBesideCursorWhenNeitherAboveNorBelowFits() {
    let origin = panelOrigin(anchor: CGRect(x: 300, y: 420, width: 100, height: 30),
                             panelSize: CGSize(width: 420, height: 500),
                             visibleFrames: [screen], primaryScreenHeight: 900, mouseLocation: CGPoint(x: 400, y: 450))
    #expect(origin == CGPoint(x: 410, y: 25))
}

@Test func placesOnCursorDisplay() {
    let origin = panelOrigin(anchor: nil, panelSize: panel,
                             visibleFrames: [screen, CGRect(x: 0, y: 900, width: 1440, height: 875)],
                             primaryScreenHeight: 900, mouseLocation: CGPoint(x: 300, y: 1300))
    #expect(origin == CGPoint(x: 310, y: 1070))
}

@Test func flipsLeftAtRightEdgeOfSecondaryDisplay() {
    let display = CGRect(x: -1280, y: 0, width: 1280, height: 800)
    let origin = panelOrigin(anchor: nil, panelSize: panel, visibleFrames: [screen, display],
                             primaryScreenHeight: 900, mouseLocation: CGPoint(x: -30, y: 780))
    #expect(origin == CGPoint(x: -460, y: 550))
}

@Test func missingScreensAndOversizedPanelsRemainDefined() {
    let mouse = CGPoint(x: 20, y: 30)
    #expect(panelOrigin(anchor: nil, panelSize: CGSize(width: 400, height: 300), visibleFrames: [],
                        primaryScreenHeight: 900, mouseLocation: mouse) == mouse)
    #expect(panelOrigin(anchor: nil, panelSize: CGSize(width: 1400, height: 1000),
                        visibleFrames: [CGRect(x: -900, y: 0, width: 900, height: 700)],
                        primaryScreenHeight: 900, mouseLocation: CGPoint(x: -500, y: 100)) == CGPoint(x: -900, y: 0))
}

@Test func growsPanelKeepingItsTopEdge() {
    let frame = panelFrame(CGRect(x: 100, y: 400, width: 420, height: 160), height: 500,
                           within: CGRect(x: 0, y: 25, width: 1440, height: 850))
    #expect(frame == CGRect(x: 100, y: 60, width: 420, height: 500))
}

@Test func growsPanelUpWhenItWouldDropBelowScreen() {
    let frame = panelFrame(CGRect(x: 100, y: 100, width: 420, height: 160), height: 500,
                           within: CGRect(x: 0, y: 25, width: 1440, height: 850))
    #expect(frame == CGRect(x: 100, y: 25, width: 420, height: 500))
}

@Test func growsPanelUpKeepingItsBottomEdge() {
    let frame = panelFrame(CGRect(x: 100, y: 200, width: 420, height: 160), height: 500, growsUp: true,
                           within: CGRect(x: 0, y: 25, width: 1440, height: 850))
    #expect(frame == CGRect(x: 100, y: 200, width: 420, height: 500))
}

@Test func growsPanelDownWhenItWouldRiseAboveScreen() {
    let frame = panelFrame(CGRect(x: 100, y: 500, width: 420, height: 160), height: 500, growsUp: true,
                           within: CGRect(x: 0, y: 25, width: 1440, height: 850))
    #expect(frame == CGRect(x: 100, y: 375, width: 420, height: 500))
}

@Test func alignsOversizedPanelToScreenTop() {
    let frame = panelFrame(CGRect(x: 100, y: 100, width: 420, height: 160), height: 1000,
                           within: CGRect(x: 0, y: 25, width: 1440, height: 850))
    #expect(frame == CGRect(x: 100, y: -125, width: 420, height: 1000))
}
