import CoreGraphics

/// TCC permission checks. Requests open the system prompt or System Settings; the grant is tied to the app's code signature.
public enum Permissions {
    public static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
