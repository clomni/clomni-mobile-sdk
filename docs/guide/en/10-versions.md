# Versions

## 1.0.3

All packages are 1.0.3: Android, iOS, React Native, Flutter and Unity (tag `unity-1.0.3`).

- The microphone button answers the moment it is touched: the circle, the timer and the vibration come at once.
- A one-second press is recorded too, and the "press and hold" hint no longer shows.

To update, set the version to 1.0.3: Android `ai.clomni:messenger:1.0.3`, React Native `@clomni/react-native@1.0.3`,
Flutter `clomni_flutter: ^1.0.3`, Unity `#unity-1.0.3`, iOS `from: "1.0.3"` or `:tag => '1.0.3'`.

## 1.0.2

| Package | Version |
|---|---|
| Android `ai.clomni:messenger` | 1.0.2 |
| React Native `@clomni/react-native` | 1.0.2 |
| Flutter `clomni_flutter` | 1.0.2 |
| Unity | tag `unity-1.0.2` |
| iOS `ClomniMessenger` | 1.0.2 |

### What changed

- Voice messages: press and hold the microphone button. Slide left to cancel, slide up to lock. You can listen before
  sending, at 1×, 1.5× or 2×.
- Photos and videos from the camera.
- Messages written offline wait in a queue and go out when the connection is back.
- Bare addresses such as `clomni.ai` become links.
- The floating button shows even when `initialize` is called late (React Native, Flutter, Unity).
- Android: the Messenger no longer disappears in an app whose `MainActivity` is `singleTask`.
- The user's name is kept when the app opens again.
- The "joined the conversation" line is in its right place.
- The company's logo next to "You".
- A flow ends at a choice that leads nowhere, and the text field opens.
- On iPhone the text field stays on top of the keyboard.
- The `debug` level writes the SDK's steps to the log.
- The Messenger's language is the same online and offline.
- The emoji button is gone; the microphone button is on the right of the text field.

### Permissions

- Android: voice messages need `RECORD_AUDIO` declared in the app's manifest, otherwise the microphone button does not
  show. The camera needs no permission. See [Android → Requirements](03-android.md#requirements).
- iOS: `NSCameraUsageDescription` and `NSMicrophoneUsageDescription`. See [iOS → Info.plist](04-ios.md#infoplist).

### How to update

- **Android:** `implementation("ai.clomni:messenger:1.0.2")`.
- **React Native:** `npm install @clomni/react-native@1.0.2`, then build the app again (`pod install` on iOS).
- **Flutter:** `clomni_flutter: ^1.0.2`, then `flutter pub get`.
- **Unity:** the package URL `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.2`, then **Force
  Resolve**.
- **iOS:** `from: "1.0.2"` in Swift Package Manager, `:tag => '1.0.2'` in CocoaPods. This time the iOS code changed too.

## 1.0.1

| Package | Version |
|---|---|
| Android `ai.clomni:messenger` | 1.0.1 |
| React Native `@clomni/react-native` | 1.0.1 |
| Flutter `clomni_flutter` | 1.0.1 |
| Unity | tag `unity-1.0.1` |
| iOS `ClomniMessenger` | 1.0.0, unchanged |

### What changed

The Android SDK sends the app's package name when it connects. Clomni compares it with the inbox's "Android package
name" and refuses the key when they differ. iOS has done the same with the Bundle ID from the start. React Native,
Flutter and Unity 1.0.1 use the new Android SDK. Nothing changed on iOS.

### Who it affects

Apps on Android. If the inbox's Android package name is the app's `applicationId`, nothing changes. If it is not,
the Android app no longer connects after 1.0.1. An inbox without an Android package name has no check.

`applicationIdSuffix` is part of the package name. A debug build with a `.debug` suffix is
`com.example.app.debug` and is refused by an inbox that says `com.example.app`. Test with a build without the
suffix, or make a separate inbox for the debug app.

### Before you update

The inbox's Android package name must be the `applicationId` in `app/build.gradle(.kts)`. It is entered in the
wizard when the inbox is created, and the panel has no place to change it later. If it is wrong, write the app's
correct package name to Clomni AI and the Clomni team will fix it.

### How to update

- **Android:** `implementation("ai.clomni:messenger:1.0.1")`, then Gradle sync.
- **React Native:** `npm install @clomni/react-native@1.0.1`, then build the app again.
- **Flutter:** `clomni_flutter: ^1.0.1` in `pubspec.yaml`, then `flutter pub get`.
- **Unity:** change the package's URL in Package Manager to
  `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1` (or `#unity-1.0.1` in
  `Packages/manifest.json`), then **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
- **iOS:** nothing to do.

### When they differ

The Messenger does not open; the server refuses the key with 401 `invalid_api_key`. In Logcat, tag `Clomni`
(the SDK writes this message in Azerbaijani):

```text
api_key səhvdir və ya bu platforma üçün deyil. Tətbiqin paket adı: com.example.app.debug; paneldəki Android paket adı ilə eyni olmalıdır (applicationIdSuffix da sayılır)
```

Compare the package name in the log with the one in the panel.

## 1.0.0

The first release: Android, iOS, React Native, Flutter and Unity.
