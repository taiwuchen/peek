import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PeekCapture

@Test func pngPreservesImageDimensions() throws {
    let context = try #require(CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
    let image = try #require(context.makeImage())
    let data = try encodePNG(image)
    #expect(Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10])
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 12)
    #expect(decoded.height == 8)
}
