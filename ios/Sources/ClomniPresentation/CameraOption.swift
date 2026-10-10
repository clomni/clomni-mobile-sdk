import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

/// Whether the attachment sheet offers the camera (CM-087): the device has one, and the app says why it uses it
/// (NSCameraUsageDescription). Without that text iOS stops the app the moment the camera opens, so the row is not
/// there and the log says what the app is missing, once.
package enum CameraOption {
    private static let told = Locked(false)

    package static func offered(deviceHasCamera: Bool, usageDescription: Any?) -> Bool {
        guard deviceHasCamera else { return false }
        if let text = usageDescription as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        let first = told.write { told -> Bool in
            defer { told = true }
            return !told
        }
        if first {
            ClomniLog.warning("the camera is not offered: the app's Info.plist has no NSCameraUsageDescription")
        }
        return false
    }
}
