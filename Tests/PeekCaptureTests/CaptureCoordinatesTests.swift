import CoreGraphics
import Testing
@testable import PeekCapture

@Test(arguments: [
    (CGPoint(x: 0, y: 1080), CGPoint(x: 0, y: 0)),
    (CGPoint(x: 400, y: 200), CGPoint(x: 400, y: 880)),
    (CGPoint(x: -100, y: 1200), CGPoint(x: -100, y: -120)),
    (CGPoint(x: 2000, y: -300), CGPoint(x: 2000, y: 1380)),
])
func pointCoordinates(appKit: CGPoint, expected: CGPoint) {
    #expect(CaptureCoordinates.topLeft(appKit, primaryScreenHeight: 1080) == expected)
    #expect(CaptureCoordinates.bottomLeft(expected, primaryScreenHeight: 1080) == appKit)
}

@Test(arguments: [
    (CGRect(x: 10, y: 20, width: 100, height: 200), CGRect(x: 10, y: 860, width: 100, height: 200)),
    (CGRect(x: -900, y: 1200, width: 300, height: 100), CGRect(x: -900, y: -220, width: 300, height: 100)),
    (CGRect(x: 1920, y: -900, width: 200, height: 400), CGRect(x: 1920, y: 1580, width: 200, height: 400)),
])
func rectangleCoordinates(appKit: CGRect, expected: CGRect) {
    #expect(CaptureCoordinates.topLeft(appKit, primaryScreenHeight: 1080) == expected)
    #expect(CaptureCoordinates.bottomLeft(expected, primaryScreenHeight: 1080) == appKit)
}

@Test func reverseDragAndScreenClamping() {
    let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    #expect(CaptureCoordinates.selection(from: CGPoint(x: 600, y: 500), to: CGPoint(x: 100, y: 50), in: bounds) == CGRect(x: 100, y: 50, width: 500, height: 450))
    #expect(CaptureCoordinates.selection(from: CGPoint(x: 600, y: 500), to: CGPoint(x: -200, y: 900), in: bounds) == CGRect(x: 0, y: 500, width: 600, height: 100))
    #expect(CaptureCoordinates.selection(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20), in: bounds).isEmpty)
    #expect(CaptureCoordinates.selection(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 50), in: bounds).isEmpty)
}

@Test func secondaryDisplayCaptureGeometry() {
    let selection = SelectedRegion(
        rect: CGRect(x: 100, y: 200, width: 300, height: 150),
        screenFrame: CGRect(x: -1440, y: 1080, width: 1440, height: 900),
        primaryScreenHeight: 1080,
        displayID: 42,
        scale: 2
    )
    #expect(selection.sourceRect == CGRect(x: 100, y: 550, width: 300, height: 150))
    #expect(selection.anchor == CGRect(x: -1340, y: -350, width: 300, height: 150))
    #expect(selection.displayID == 42)
    #expect(selection.scale == 2)
}
