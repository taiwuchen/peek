import CoreGraphics

/// Puts the panel's top-left just below-right of the cursor, flipping near screen edges and away from the capture.
func panelOrigin(anchor: CGRect?, panelSize: CGSize, visibleFrames: [CGRect],
                 primaryScreenHeight: CGFloat, mouseLocation: CGPoint) -> CGPoint {
    guard !visibleFrames.isEmpty else { return mouseLocation }
    let capture = anchor.map {
        CGRect(x: $0.minX, y: primaryScreenHeight - $0.maxY, width: $0.width, height: $0.height)
    }
    let frame = visibleFrames.first(where: { $0.contains(mouseLocation) })
        ?? visibleFrames.min { $0.distanceSquared(to: mouseLocation) < $1.distanceSquared(to: mouseLocation) }!
    let gap: CGFloat = 10
    let right = mouseLocation.x + gap, left = mouseLocation.x - gap - panelSize.width
    let below = mouseLocation.y - gap - panelSize.height, above = mouseLocation.y + gap
    // When neither above nor below fits, slide along the side of the cursor away from the capture.
    let slid = max(frame.minY, min(below, frame.maxY - panelSize.height))
    let candidates = [CGPoint(x: right, y: below), CGPoint(x: left, y: below),
                      CGPoint(x: right, y: above), CGPoint(x: left, y: above),
                      CGPoint(x: right, y: slid), CGPoint(x: left, y: slid)]
    let proposed = candidates.first { origin in
        let rect = CGRect(origin: origin, size: panelSize)
        return frame.contains(rect) && !(capture?.intersects(rect) ?? false)
    } ?? candidates[0]
    return CGPoint(x: max(frame.minX, min(proposed.x, frame.maxX - panelSize.width)),
                   y: max(frame.minY, min(proposed.y, frame.maxY - panelSize.height)))
}

/// Resizes `frame` to `height` keeping its top edge, or its bottom edge when it grows up, then keeps it on `visibleFrame`.
func panelFrame(_ frame: CGRect, height: CGFloat, growsUp: Bool = false, within visibleFrame: CGRect) -> CGRect {
    var result = CGRect(x: frame.minX, y: growsUp ? frame.minY : frame.maxY - height, width: frame.width, height: height)
    if result.maxY > visibleFrame.maxY { result.origin.y = visibleFrame.maxY - height }
    if result.minY < visibleFrame.minY { result.origin.y = min(visibleFrame.minY, visibleFrame.maxY - height) }
    return result
}

private extension CGRect {
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}
