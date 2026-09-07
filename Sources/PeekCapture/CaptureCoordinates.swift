import CoreGraphics

enum CaptureCoordinates {
    static func topLeft(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    static func bottomLeft(_ point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        topLeft(point, primaryScreenHeight: primaryScreenHeight)
    }

    static func topLeft(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func bottomLeft(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        topLeft(rect, primaryScreenHeight: primaryScreenHeight)
    }

    static func selection(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let start = CGPoint(x: min(max(start.x, bounds.minX), bounds.maxX), y: min(max(start.y, bounds.minY), bounds.maxY))
        let end = CGPoint(x: min(max(end.x, bounds.minX), bounds.maxX), y: min(max(end.y, bounds.minY), bounds.maxY))
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
