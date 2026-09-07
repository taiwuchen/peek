import CoreGraphics
import Foundation

/// Something the user pointed at: selected text or a region of the screen.
public struct Capture: Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        /// PNG-encoded image data.
        case image(Data)
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
    case accessibilityPermissionDenied
    case screenRecordingPermissionDenied
    case noSelection
    case cancelled
    case failed(String)
}

/// Reads the current text selection from the frontmost app.
public protocol SelectionReader: Sendable {
    func readSelection() async throws -> Capture
}

/// Lets the user drag out a screen region and returns it as an image.
public protocol ScreenRegionCapturer: Sendable {
    func captureRegion() async throws -> Capture
}
