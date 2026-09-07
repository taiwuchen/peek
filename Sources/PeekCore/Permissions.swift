import ApplicationServices
import CoreGraphics

/// TCC permission checks. Requests open the system prompt or System Settings; the grant is tied to the app's code signature.
public enum Permissions {
    public static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    public static func requestAccessibility() {
        // String literal instead of kAXTrustedCheckOptionPrompt, which Swift 6 rejects as non-Sendable global state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
