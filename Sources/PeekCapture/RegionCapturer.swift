import AppKit
import ImageIO
import PeekCore
import ScreenCaptureKit
import UniformTypeIdentifiers

public struct RegionCapturer: ScreenRegionCapturer {
    @MainActor private static var isCapturing = false

    public init() {}

    @MainActor
    public func captureRegion() async throws -> Capture {
        guard Permissions.screenRecordingGranted else { throw CaptureError.screenRecordingPermissionDenied }
        guard !Self.isCapturing else { throw CaptureError.failed("A region capture is already in progress.") }
        Self.isCapturing = true
        defer { Self.isCapturing = false }
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let session = RegionSelectionSession()

        do {
            let selection = try await withTaskCancellationHandler {
                try await session.select()
            } onCancel: {
                Task { @MainActor in session.cancel() }
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(34))
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else {
                throw CaptureError.failed("The selected display is no longer available.")
            }
            let overlays = content.windows.filter { session.windowIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: overlays)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = selection.sourceRect
            configuration.width = max(1, Int((selection.sourceRect.width * selection.scale).rounded(.up)))
            configuration.height = max(1, Int((selection.sourceRect.height * selection.scale).rounded(.up)))
            configuration.showsCursor = false
            try Task.checkCancellation()
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            return Capture(content: .image(try encodePNG(image)), anchor: selection.anchor, sourceBundleID: sourceBundleID)
        } catch is CancellationError {
            throw CaptureError.cancelled
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }
}

func encodePNG(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CaptureError.failed("Could not create a PNG image.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CaptureError.failed("Could not encode the PNG image.") }
    return data as Data
}

struct SelectedRegion: Sendable {
    let displayID: CGDirectDisplayID
    let sourceRect: CGRect
    let anchor: CGRect
    let scale: CGFloat

    init(rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat, displayID: CGDirectDisplayID, scale: CGFloat) {
        self.displayID = displayID
        self.scale = scale
        sourceRect = CaptureCoordinates.topLeft(rect, primaryScreenHeight: screenFrame.height)
        let global = rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        anchor = CaptureCoordinates.topLeft(global, primaryScreenHeight: primaryScreenHeight)
    }
}
