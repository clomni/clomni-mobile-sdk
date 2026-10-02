# clomni_flutter

The Clomni Messenger in a Flutter app. The Dart API only calls the native iOS and Android SDKs, which draw the
messenger natively, through a method channel and an event channel. It does not use a WebView.

Flutter 3.16 or later; iOS 15, Android API 24.

## Install

```sh
flutter pub add clomni_flutter
```

The iOS side brings the iOS SDK (`ClomniMessenger`, CocoaPods or Swift Package Manager), the Android side the Android
SDK (`ai.clomni:messenger`, Maven Central).

**Android: the app's `MainActivity` extends `FlutterFragmentActivity`**, not `FlutterActivity`: the messenger's
optional launcher draws on the app's activity and needs an AndroidX activity under it.

```kotlin
class MainActivity : FlutterFragmentActivity()
```

Until the native SDKs are published, point both to a checkout of this repository:

- iOS, in `ios/Podfile`: `pod 'ClomniMessenger', :path => '../path/to/clomni-mobile-sdk'`
- Android: publish the SDK to the local Maven repository, then add `mavenLocal()` to the app's repositories (the
  example does). An included build does not work here: Flutter 3.47's apps use AGP 9, the SDK AGP 8, and one Gradle
  build cannot hold both.

  ```sh
  cd path/to/clomni-mobile-sdk/android
  ./gradlew --init-script ../flutter/scripts/publish-sdk-locally.gradle :messenger:publishReleasePublicationToMavenLocal
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
| `setLogLevel(ClomniLogLevel)`, `setTypeface(familyName)` | log and font (a family the platform knows: iOS `UIAppFonts`, Android `res/font`) |
| `unreadCountStream`, `onMessengerOpened`, `onMessengerClosed`, `onConversationStarted`, `onFlowCompleted` | events, as streams |

The plugin owns the SDK's native event callbacks; native code of the app should not set them as well.

## Development

```sh
flutter test                      # the Dart layer, with mocked channels
flutter analyze
cd example && flutter build apk --debug    # the Android plugin, with the SDK published locally (above)
scripts/typecheck-ios-plugin.sh   # without Xcode: the iOS plugin against the iOS SDK's API and a Flutter stub
```
