import CoreGraphics
import Foundation

/// Content the user attached to a message: a captured screen region, an image, or a file.
public struct Capture: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        /// PNG-encoded image data.
        case image(Data)
        /// A PDF file and its file name.
        case pdf(name: String, data: Data)
        /// A UTF-8 text file and its file name.
        case text(name: String, text: String)
    }

    public let content: Content
    /// Screen-space rect (top-left origin, points) of the captured content. Used to anchor the answer panel.
    public let anchor: CGRect?
    /// Bundle identifier of the app the content came from, when known.
    public let sourceBundleID: String?

    public init(content: Content, anchor: CGRect?, sourceBundleID: String?) {
        self.content = content
        self.anchor = anchor
        self.sourceBundleID = sourceBundleID
    }
}

public enum CaptureError: Error, Sendable, Equatable {
    case screenRecordingPermissionDenied
    case cancelled
    case failed(String)
}

/// Lets the user drag out a screen region and returns it as an image.
public protocol ScreenRegionCapturer: Sendable {
    func captureRegion() async throws -> Capture
}
