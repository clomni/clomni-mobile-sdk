# @clomni/react-native — changelog

## 1.0.1

Android: the session carries the app's package name (Android SDK 1.0.1), so an inbox that names an Android
package accepts its keys only from that app, as iOS already did with the bundle ID.

## 1.0.0

The first release: the Clomni Messenger through the native iOS and Android SDKs, for both React Native architectures
(0.75+) and Expo development builds (SDK 52+). The iOS SDK comes as a Swift package through React Native's
`spm_dependency`, or as a pod from the repository's tag when the Podfile names it.
