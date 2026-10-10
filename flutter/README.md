# clomni_flutter

The Clomni Messenger in a Flutter app. The Dart API only calls the native iOS and Android SDKs, which draw the
messenger natively, through a method channel and an event channel. It does not use a WebView.

Flutter 3.16 or later; iOS 15, Android API 24.

## Install

```sh
flutter pub add clomni_flutter
```

The Android side brings the Android SDK (`ai.clomni:messenger`, Maven Central). The iOS side brings the iOS SDK
(`ClomniMessenger`), which is a Swift package and not on CocoaPods trunk:

- **Swift Package Manager** (on by default in current Flutter, e.g. 3.47; from 3.24 with
  `flutter config --enable-swift-package-manager`): nothing to add. The plugin's `Package.swift` takes the SDK from `https://github.com/clomni/clomni-mobile-sdk.git`, version
  1.0.0 up to the next major. Xcode 15 or later.
- **CocoaPods**: add one line to `ios/Podfile`, in `target 'Runner'`, then `pod install`. Without it `pod install`
  stops and prints this line.

  ```ruby
  pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
  ```

**Android: the app's `MainActivity` extends `FlutterFragmentActivity`**, not `FlutterActivity`: the messenger's
optional launcher draws on the app's activity and needs an AndroidX activity under it.

```kotlin
class MainActivity : FlutterFragmentActivity()
```

Voice messages: the app declares the microphone. Without it there is no microphone.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<!-- ios/Runner/Info.plist -->
<key>NSMicrophoneUsageDescription</key>
<string>To send voice messages to support</string>
```

To build against a checkout of this repository instead:

- iOS with CocoaPods, in `ios/Podfile`: `pod 'ClomniMessenger', :path => '../path/to/clomni-mobile-sdk'`
- Android: publish the SDK to the local Maven repository, then add `mavenLocal()` to the app's repositories (the
  example does). An included build does not work here: Flutter 3.47's apps use AGP 9, the SDK AGP 8, and one Gradle
  build cannot hold both.

  ```sh
  cd path/to/clomni-mobile-sdk/android
  ./gradlew -Pclomni.version=1.0.0 :messenger:publishReleasePublicationToMavenLocal
  ```

## Use

```dart
import 'package:clomni_flutter/clomni_flutter.dart';

// Once, at the app's start: the App ID and the API key of this platform from Clomni (Channels → Mobile app).
await Clomni.initialize('app_…', Platform.isIOS ? 'ios_…' : 'android_…');

// When the app's user logs in. userHash = hex(HMAC-SHA256(identity_secret, userId)), made on the app's server.
await Clomni.loginUser(const ClomniUser(userId: '5', email: 'aysel@example.com', name: 'Aysel'), userHash: userHash);

// The app's own buttons open the messenger; nothing of Clomni shows until then.
await Clomni.present(source: 'profile_support');
await Clomni.startFlow('ride_problem', data: {'ride_id': 'R-1042'}, openMessenger: true, source: 'ride_detail');

// The unread count for the app's own badge: the current one at once, then every change.
StreamBuilder<int>(stream: Clomni.unreadCountStream, builder: …);

// When the user logs out, or the next user of the phone sees this one's conversations.
await Clomni.logout();
```

### Push

```dart
await Clomni.setDeviceToken(token); // iOS: the APNs device token as hex; Android: the FCM token

// iOS: a tap on a notification (its data). Android: an FCM data message as it arrives (RemoteMessage.data);
// the SDK shows the notification, whose tap opens the conversation.
if (!await Clomni.handlePush(data)) {
  // the app's own push
}

// iOS, a push while the app is open: not shown while the messenger is open.
final show = await Clomni.shouldShowForeground(data);
```

`Clomni.isClomniPush(data)` tells Clomni's pushes from the app's own. Android only:
`Clomni.setNotificationIcon('drawable_name')`.

## API

| Call | |
|---|---|
| `initialize(appId, apiKey, {region = 'eu'})` | once, at the app's start |
| `loginUser(user, {userHash})`, `loginUnidentifiedUser()`, `updateUser({name, language, customAttributes})`, `logout()` | the user |
| `present({source})`, `presentNewConversation({source})`, `presentConversation(id)`, `dismiss()` | opening and closing |
| `startFlow(event, {data, openMessenger = false, source})` | the flow bound to an app event |
| `setLauncherVisible(visible)`, `setBottomPadding(padding)` | the optional floating button |
| `setDeviceToken(token)`, `isClomniPush(data)`, `handlePush(data)`, `shouldShowForeground(data)` (iOS), `setNotificationIcon(name)` (Android) | push |
| `setTheme({primaryColor, typeface, mode})` | the app's look over the panel's (below) |
| `setLogLevel(ClomniLogLevel)`, `setTypeface(familyName)` | log and font (below) |
| `setSoundsEnabled(enabled)`, `setLanguage(language)` | message sounds (on unless the panel turns them off); the messenger's language, `'az'`, `'en'`, `'ru'` or null for the phone's |
| `onLink(listener)` | a news item's button: the link goes to the app, which opens it; null leaves it to the system |
| `unreadCountStream`, `onMessengerOpened`, `onMessengerClosed`, `onConversationStarted`, `onFlowCompleted` | events, as streams |

The plugin owns the SDK's native event callbacks; native code of the app should not set them as well.

### Font

`setTypeface` takes a font family as each platform knows it; the fonts in Flutter's `pubspec.yaml` do not reach the
native screens by themselves.

- iOS: the family name of a font in the app bundle, listed under `UIAppFonts` in `ios/Runner/Info.plist`
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: a font resource, `android/app/src/main/res/font/montserrat.xml` (a family with its weights) or
  `montserrat.ttf` → `'montserrat'`; otherwise a family the system has.

```dart
await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');
```

### Look

The colours, logo, header, Home cards and texts come from the panel and change without an app update. `setTheme`
puts the app's own colour (`'#RRGGBB'`; the other brand colours are derived from it), font (as `setTypeface`) and
mode over the panel's. Each call replaces the last; what is left out stays the panel's.

```dart
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

### Links

A news item's button carries a web address or the app's own deep link. With a listener the app opens it its own way;
without one the system does.

```dart
await Clomni.onLink((url) => launchUrl(Uri.parse(url)));
```

## Development

Until `ai.clomni:messenger` is on Maven Central, the example (and any app) takes the Android SDK from the local Maven
repository, published from this repository's `android/` as in Install; with the SDK
published, `mavenLocal()` and that step go.

```sh
flutter test                      # the Dart layer, with mocked channels
flutter analyze
cd example && flutter build apk --debug    # the Android plugin, with the SDK published locally (above)
scripts/typecheck-ios-plugin.sh   # without Xcode: the iOS plugin against the iOS SDK's API and a Flutter stub
```
