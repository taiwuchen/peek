import CoreGraphics

func panelOrigin(anchor: CGRect?, panelSize: CGSize, visibleFrames: [CGRect],
                 primaryScreenHeight: CGFloat, mouseLocation: CGPoint) -> CGPoint {
    guard !visibleFrames.isEmpty else { return mouseLocation }
    let target = anchor.map {
        CGRect(x: $0.minX, y: primaryScreenHeight - $0.maxY, width: $0.width, height: $0.height)
    } ?? CGRect(origin: mouseLocation, size: .zero)
    let center = CGPoint(x: target.midX, y: target.midY)
    let screen = visibleFrames.max {
        $0.intersection(target).area < $1.intersection(target).area
    }
    let frame = visibleFrames.first(where: { $0.contains(center) })
        ?? ((screen?.intersection(target).area ?? 0) > 0 ? screen : nil)
        ?? visibleFrames.min { $0.distanceSquared(to: center) < $1.distanceSquared(to: center) }!
    let gap: CGFloat = 10
    let below = CGPoint(x: target.minX, y: target.minY - gap - panelSize.height)
    let above = CGPoint(x: target.minX, y: target.maxY + gap)
    let right = CGPoint(x: target.maxX + gap, y: target.midY - panelSize.height / 2)
    let left = CGPoint(x: target.minX - gap - panelSize.width, y: right.y)
    let candidates = [below, above, right, left]
    let proposed = candidates.first { frame.contains(CGRect(origin: $0, size: panelSize)) }
        ?? (below.y >= frame.minY ? below : above.y + panelSize.height <= frame.maxY ? above : right)
    return CGPoint(x: max(frame.minX, min(proposed.x, frame.maxX - panelSize.width)),
                   y: max(frame.minY, min(proposed.y, frame.maxY - panelSize.height)))
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let dx = max(minX - point.x, 0, point.x - maxX)
        let dy = max(minY - point.y, 0, point.y - maxY)
        return dx * dx + dy * dy
    }
}
