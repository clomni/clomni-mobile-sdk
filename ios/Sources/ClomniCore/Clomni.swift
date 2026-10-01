/// The SDK's public facade. Its API (initialize, loginUser, present, …) arrives with CM-086; ClomniMessenger extends
/// it with the screens.
public enum Clomni {
    /// Sent as `sdk_version` and in the X-Clomni-SDK header; equal to the podspec's version.
    public static let version = "1.0.0"
}
