# Changelog

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

The first release: the Clomni Messenger in Unity on Android and iOS through the native SDKs, with the same calls as
the React Native and Flutter packages and their events as C# events. Native dependencies through EDM4U; samples for
the basic calls and for Firebase push.
