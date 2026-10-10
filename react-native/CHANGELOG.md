# @clomni/react-native — changelog

## 1.0.2

The native SDKs 1.0.2 on both platforms: voice messages (the microphone replaces the emoji button), the camera,
offline messages that wait and go when the network is back, the launcher after a late initialize, and the fixes the
first integration tests found. Recording needs `RECORD_AUDIO` in the Android manifest and `NSMicrophoneUsageDescription`
in the iOS Info.plist; without them the microphone is not shown.

## 1.0.1

Android: the session carries the app's package name (Android SDK 1.0.1), so an inbox that names an Android
package accepts its keys only from that app, as iOS already did with the bundle ID.

## 1.0.0

The first release: the Clomni Messenger through the native iOS and Android SDKs, for both React Native architectures
(0.75+) and Expo development builds (SDK 52+). The iOS SDK comes as a Swift package through React Native's
`spm_dependency`, or as a pod from the repository's tag when the Podfile names it.
