## 1.0.5

Android: the camera's FileProvider is the SDK's own class, so it no longer collides with apps or libraries (e.g.
unity-webview) that declare androidx FileProvider. The Android SDK is 1.0.5; iOS is unchanged and stays 1.0.4.

## 1.0.4

The native SDKs 1.0.4: a flow decides whether the user can type. Buttons can keep the field under them, and a step
that turns typing off keeps the conversation locked after the flow is over, offering only a new conversation. With an
earlier server, and with flows that do not use these settings, nothing changes.

## 1.0.3

The native SDKs 1.0.3: the microphone answers the moment it is touched, and a press of about a second records instead
of asking to hold.

## 1.0.2

The native SDKs 1.0.2 on both platforms: voice messages (the microphone replaces the emoji button), the camera,
offline messages that wait and go when the network is back, the launcher after a late initialize, and the fixes the
first integration tests found. Recording needs `RECORD_AUDIO` in the Android manifest and `NSMicrophoneUsageDescription`
in the iOS Info.plist; without them the microphone is not shown.

## 1.0.1

Android: the session carries the app's package name (Android SDK 1.0.1), so an inbox that names an Android
package accepts its keys only from that app, as iOS already did with the bundle ID.

## 1.0.0

The first release: the Clomni Messenger through the native iOS and Android SDKs (opening it, users, flows, push, the
unread count and events as streams, theme, sounds, language, links). On iOS the SDK comes through Swift Package
Manager, or with CocoaPods from the repository's tag (one line in the Podfile).
