# Flutter

The plugin `clomni_flutter` wraps the native Android and iOS SDKs. The screens are the native ones.

## Requirements

- Flutter 3.16 or newer.
- iOS 15, Android API 24.
- The App ID and both API keys (`android_…`, `ios_…`) from **Installation** in the inbox's settings column.

## Install

```sh
flutter pub add clomni_flutter
```

**iOS.** The iOS SDK is a Swift package:

- With Swift Package Manager (on by default in current Flutter; from 3.24 with
  `flutter config --enable-swift-package-manager`) the plugin takes the SDK by itself.
- With CocoaPods, add this line to `ios/Podfile`, inside `target 'Runner'`, then run `pod install`. Without it
  `pod install` stops and prints the line.

  ```ruby
  pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.3'
  ```

Add the photo texts to `ios/Runner/Info.plist` (see the [iOS chapter](04-ios.md#infoplist)).

**Android.** The app's `MainActivity` must extend `FlutterFragmentActivity`, not `FlutterActivity`:

```kotlin
// android/app/src/main/kotlin/com/example/app/MainActivity.kt
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

On iOS, add the permission texts for photos, the camera and the microphone to the app's `Info.plist`: [iOS →
Info.plist](04-ios.md#infoplist). On Android, voice messages (from SDK 1.0.2) need `RECORD_AUDIO` declared in the app's
manifest: [Android → Requirements](03-android.md#requirements).

## Initialize

```dart
import 'dart:io' show Platform;

import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Clomni.initialize('app_…', Platform.isIOS ? 'ios_…' : 'android_…');
  if (kDebugMode) await Clomni.setLogLevel(ClomniLogLevel.debug);
  runApp(const App());
}
```

## The user

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: hashFromYourServer,
);
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});

// With your app's own logout:
await Clomni.logout();
```

See [Identifying users](02-identity.md) for the hash.

Call `loginUser` on every app start while the user is signed in, as if they had just signed in. For the same user the
SDK reuses its stored session.

## Open the Messenger

```dart
class SupportTile extends StatelessWidget {
  const SupportTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Clomni.unreadCountStream, // the current count at once, then every change
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return ListTile(
          title: const Text('Support'),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => Clomni.present(source: 'profile_support'),
        );
      },
    );
  }
}
```

| Call | What it does |
|---|---|
| `Clomni.present(source: …)` | Opens Home |
| `Clomni.presentNewConversation(source: …)` | Opens a new conversation straight away |
| `Clomni.presentConversation(id)` | Opens a known conversation; the ID comes from `onConversationStarted` |
| `Clomni.dismiss()` | Closes the Messenger from code |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | The optional floating button |

## Flows and events

```dart
await Clomni.startFlow('ride_problem',
    data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');

Clomni.onMessengerOpened.listen((source) => debugPrint('opened from $source'));
Clomni.onMessengerClosed.listen((_) => debugPrint('closed'));
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

The flow needs the "App event" trigger with the same name in the panel, and must be published. The data must be JSON.
The plugin owns the native SDK's event callbacks; do not set them in the app's native code as well.

**The event name is not the flow's name.** Pass `startFlow` the name on the flow's "Event: …" line in the panel's Flows
section. The flow must use the "App event" trigger: a flow with the "When a conversation starts" trigger does not start
with `startFlow`.

## Links, language, sounds and look

```dart
import 'package:url_launcher/url_launcher.dart';

await Clomni.onLink((url) => launchUrl(Uri.parse(url)));   // null: the system opens links
await Clomni.setLanguage('en');                            // 'az', 'en', 'ru'; null follows the phone
await Clomni.setSoundsEnabled(false);
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

Fonts from `pubspec.yaml` do not reach the native screens. Pass each platform's own name:

- iOS: the family name of a font in the app bundle, listed under `UIAppFonts` in `ios/Runner/Info.plist`
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: a font resource, `android/app/src/main/res/font/montserrat.ttf` → `'montserrat'`.

```dart
await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');
```

## Push notifications

Upload the keys to the panel first ([Push keys](08-push-keys.md)). The examples use `firebase_messaging` for Android.
Any push library works if it gives you the token and the message data.

### Android

Set up Firebase as the [FlutterFire docs](https://firebase.flutter.dev) describe (`flutterfire configure`), and
declare the permission in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```dart
import 'dart:io' show Platform;

import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// Clomni's data messages while the app is in the background or closed: the SDK shows the notification.
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await Clomni.handlePush(message.data);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  await Clomni.initialize('app_…', Platform.isIOS ? 'ios_…' : 'android_…');
  runApp(const App());
}

Future<void> setUpAndroidPush() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(); // Android 13+: the system's permission dialog
  final token = await messaging.getToken();
  if (token != null) await Clomni.setDeviceToken(token);
  messaging.onTokenRefresh.listen(Clomni.setDeviceToken);
  // Messages while the app is open.
  FirebaseMessaging.onMessage.listen((message) async {
    if (!await Clomni.handlePush(message.data)) {
      // the app's own push
    }
  });
  await Clomni.setNotificationIcon('ic_notification'); // android/app/src/main/res/drawable/ic_notification.png
}
```

Call `setUpAndroidPush()` on Android at a moment that suits your users, for example after login.

### iOS

Clomni sends iOS pushes straight to APNs, not through Firebase. `firebase_messaging` reports only messages sent
through FCM, so it does not see a tap on a Clomni notification. Wire the tap in the Runner's native code:

1. In Xcode (`ios/Runner.xcworkspace`): Runner target → **Signing & Capabilities** → **+ Capability** →
   **Push Notifications**.
2. The Runner's own code imports `ClomniMessenger`. With CocoaPods, the Podfile line above is enough. With Swift
   Package Manager, add the package to the Runner target as well: **File → Add Package Dependencies**,
   `https://github.com/clomni/clomni-mobile-sdk.git`, product `ClomniMessenger`, target Runner.
3. Add this file to the Runner target:

```swift
// ios/Runner/ClomniNotifications.swift
import ClomniMessenger
import UserNotifications

/// Clomni pushes: hidden while the Messenger is open, and a tap opens the conversation.
final class ClomniNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ClomniNotifications()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let show = Clomni.shouldShowForeground(notification.request.content.userInfo)
        completionHandler(show ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        _ = Clomni.handlePush(response.notification.request.content.userInfo)
        completionHandler()
    }
}
```

4. Make it the notification delegate in `AppDelegate.swift`, **before** `super.application(...)`:

```swift
// ios/Runner/AppDelegate.swift
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = ClomniNotifications.shared
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

`firebase_messaging` takes over the delegate during `super.application(...)` and passes every push that is not its
own on to this one, so FCM keeps working for your own pushes.

5. Hand over the APNs token from Dart:

```dart
if (Platform.isIOS) {
  await FirebaseMessaging.instance.requestPermission();
  final apnsToken = await FirebaseMessaging.instance.getAPNSToken(); // hex
  if (apnsToken != null) await Clomni.setDeviceToken(apnsToken);
}
```

Without Firebase on iOS, hand the token over natively: override
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` in `AppDelegate`, call
`Clomni.setDeviceToken(deviceToken)` and then `super`.

## Problems

| Symptom | What to do |
|---|---|
| `pod install` stops and prints a `pod 'ClomniMessenger'` line | Add that line to `ios/Podfile` in `target 'Runner'` |
| Android: the floating button does not show, or the app crashes opening the Messenger | `MainActivity` must extend `FlutterFragmentActivity` |
| Android notifications do not appear while the app is closed | Register `FirebaseMessaging.onBackgroundMessage` before `runApp`, with a top-level function |
| iOS: `No such module 'ClomniMessenger'` in `ClomniNotifications.swift` | Add the package or the pod to the Runner target (step 2) |
| A tap on a Clomni notification on iOS only opens the app | The delegate (steps 3 and 4) is missing or set after `super.application(...)` |

Errors of the Dart side start with `[Clomni]` in the Flutter log; the native logs are in logcat (tag `Clomni`) and
the Xcode console. More in [Troubleshooting](09-troubleshooting.md).
