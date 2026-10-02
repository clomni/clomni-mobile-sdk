import Foundation

/// The APNs side of a device: its token as text, and which APNs environment it belongs to.
package enum PushToken {
    /// The token APNs hands the app (`didRegisterForRemoteNotificationsWithDeviceToken`) as lower-case hex.
    package static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the app is signed for the APNs sandbox: the `aps-environment` entitlement in its
    /// embedded.mobileprovision says "development". App Store and TestFlight builds carry no such profile, or one
    /// that says "production": both are production, as is anything unreadable.
    package static func isSandbox(provisioningProfile: Data?) -> Bool {
        guard let profile = provisioningProfile,
              // The profile is a signed envelope around a plain XML property list.
              let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound..<end.upperBound],
                                                                      format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return false }
        return entitlements["aps-environment"] as? String == "development"
    }

    /// This app's own profile (none in App Store builds). The Simulator has no profile and its tokens are sandbox ones.
    package static var appIsSandbox: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return isSandbox(provisioningProfile: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) })
        #endif
    }
}

/// The token the app gave, and for whom the server has it. The server keeps one token per device, so a new token
/// replaces the old one there.
struct PushRegistration: Codable, Equatable {
    var token: String
    var sandbox: Bool
    /// The user the server registered this token for; nil until it has, and after logout, which removes it there.
    var registeredFor: String?
}
