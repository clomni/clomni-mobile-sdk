// SwiftPM builds ClomniProtocol as its own module; CocoaPods compiles every file under ios/Sources into the single
// ClomniMessenger module, where there is nothing to import.
#if canImport(ClomniProtocol)
@_exported import ClomniProtocol
#endif

/// The SDK's public facade. Its API (initialize, loginUser, present, …) arrives with CM-086.
public enum Clomni {
    /// Sent as `sdk_version` and in the X-Clomni-SDK header; equal to the podspec's version.
    public static let version = "1.0.0"
}
