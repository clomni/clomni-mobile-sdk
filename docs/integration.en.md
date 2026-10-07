# Clomni Messenger mobile SDK: integration

This guide adds the Clomni Messenger to an iOS, Android, React Native or Flutter app. Each step has four examples:
Kotlin (Android), Swift (iOS), TypeScript (React Native), Dart (Flutter).

The messenger opens inside the app with native screens; it does not use a WebView. In Clomni each app is a "Mobile
app (App SDK)" channel: messages reach the operators, and flows (language choice, menu buttons, handover to an
operator) run here with native buttons.

| Platform | Minimum |
|---|---|
| Android | Android 6.0 (API 23) |
| iOS | iOS 15, Xcode 15 |
| React Native | React Native 0.72 (0.76 for the New Architecture); Expo SDK 50 in a development build |
| Flutter | Flutter 3.16; iOS 15, Android API 24 |

## 1. In the Clomni panel

In the Clomni panel: **Channels → Add channel → Mobile app (App SDK)**. The wizard's steps: App details,
Installation, Identity verification, Push notifications, Appearance, Flows.

The channel gives you:

| Key | Where it lives |
|---|---|
| App ID (`app_…`) | in the app |
| Android API key (`android_…`) | in the Android app |
| iOS API key (`ios_…`) | in the iOS app |
| Identity Secret | **only on your server** |

- The API keys are shown in full only in the "Installation" step. After that the panel shows only their start. A new
  key is created on the channel page.
- The Identity Secret is also shown once. Store it on your server right away (for example `CLOMNI_IDENTITY_SECRET`).
- An API key belongs to one platform: the iOS key does not work in the Android app.

Later, everything is on the channel page's tabs: Overview, Installation, Security, Push, Appearance, Flows, Analytics.

## 2. Install

> The packages are not published yet. The names below and version `1.0.0` will work once they are.

**Android** (Maven Central):

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.clomni:messenger:1.0.0")
}
```

The SDK asks for no permission itself and adds nothing to the app's screens.

**iOS**, Swift Package Manager: File → Add Package Dependencies →
`https://github.com/rzayevkenann/clomni-mobile-sdk.git`, version `1.0.0`, product `ClomniMessenger`.

**iOS**, CocoaPods:

```ruby
pod 'ClomniMessenger', '~> 1.0'
```

**React Native**:

```sh
npm install @clomni/react-native
cd ios && pod install
```

Expo needs a development build (`npx expo prebuild` or an EAS build). Expo Go cannot load native modules. The
package's config plugin writes what the native projects need:

```ts
// app.config.ts
plugins: [
  ['@clomni/react-native', {
    photoLibraryPermission: 'To send photos to support',          // iOS
    cameraPermission: 'To take and send photos to support',       // iOS
    push: true,                                                   // default
    notificationIcon: './assets/notification-icon.png',           // Android, a white silhouette PNG
  }],
],
```

**Flutter**:

```sh
flutter pub add clomni_flutter
```

On Android the app's `MainActivity` extends `FlutterFragmentActivity`, not `FlutterActivity`:

```kotlin
class MainActivity : FlutterFragmentActivity()
```

## 3. Initialize: `initialize`

Call it once, when the app starts. A second call is ignored.

```kotlin
// Android: in Application.onCreate (named in the manifest with android:name). A notification can start the app,
// and the SDK must be ready then.
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Clomni.initialize(this, appId = "app_…", apiKey = "android_…")
    }
}
```

```swift
// iOS: AppDelegate
import ClomniMessenger

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Clomni.initialize(appId: "app_…", apiKey: "ios_…")
    return true
}
```

```ts
// React Native
import { Platform } from 'react-native';
import Clomni from '@clomni/react-native';

Clomni.initialize('app_…', Platform.OS === 'ios' ? 'ios_…' : 'android_…');
```

```dart
// Flutter
import 'dart:io' show Platform;
import 'package:clomni_flutter/clomni_flutter.dart';

await Clomni.initialize('app_…', Platform.isIOS ? 'ios_…' : 'android_…');
```

Every method of `Clomni` may be called from any thread. Callbacks arrive on the main thread.

## 4. The user: `loginUser` and `user_hash`

Without a login the messenger opens for an anonymous visitor, kept on this device until `logout`. When the user logs
in to your app, hand them to Clomni. The visitor's conversations move to the user.

1. The user logs in to your app.
2. Your server computes `user_hash` with the Identity Secret and returns it to the app in your own API response.
3. The app calls `loginUser`.

```kotlin
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = userHashFromYourServer)
```

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: userHashFromYourServer)
```

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, userHashFromYourServer);
```

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: userHashFromYourServer,
);
```

To change the name, the language (`az`, `en`, `ru`) or custom attributes later, use `updateUser`. Only the given
fields change; `customAttributes` are merged with the existing ones:

```kotlin
Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))
```

```swift
Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])
```

```ts
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });
```

```dart
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});
```

### Computing `user_hash` on the server

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- The result is lower-case hex, 64 characters.
- `user_id` is a string, exactly the one you pass to `loginUser`.
- Without a `userId` the hash is taken over the email, lower-cased and trimmed.

> **Warning.** The Identity Secret never goes into the app: not in code, not in `BuildConfig`, not in `Info.plist`,
> not in an `.env` shipped with the app. An app can be unpacked and the secret read out. Anyone with the secret can
> open another user's conversations. The hash is computed only on your server.

```ruby
# Ruby
require 'openssl'
user_hash = OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('CLOMNI_IDENTITY_SECRET'), user.id.to_s)
```

```js
// Node.js
const crypto = require('crypto');
const userHash = crypto.createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET).update(String(user.id)).digest('hex');
```

```go
// Go
import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"os"
)

func clomniUserHash(userID string) string {
	mac := hmac.New(sha256.New, []byte(os.Getenv("CLOMNI_IDENTITY_SECRET")))
	mac.Write([]byte(userID))
	return hex.EncodeToString(mac.Sum(nil))
}
```

```php
// PHP
$userHash = hash_hmac('sha256', (string) $user->id, getenv('CLOMNI_IDENTITY_SECRET'));
```

```python
# Python
import hashlib, hmac, os
user_hash = hmac.new(os.environ["CLOMNI_IDENTITY_SECRET"].encode(), str(user.id).encode(), hashlib.sha256).hexdigest()
```

To check: with the secret `test_secret` and `user_id` `12345` the hash is
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24`. You can check your own hash with "Test a hash" on
the panel's **Security** tab.

### Modes

The mode is chosen on the **Security** tab:

| Mode | What it does |
|---|---|
| Off (`off`) | The hash is not checked; the user is not verified. For testing only. |
| Recommended (`recommended`, default) | A hash that is sent must be right; a wrong one refuses the login. Without a hash the user is accepted, not verified. Once a user has logged in verified, a hash is required for them from then on. |
| Enforced (`enforced`) | No login without a right hash (`403 identity_verification_failed`). Available after the first verified login from the app. Old app versions that send no hash can no longer connect. |

Replacing the secret: Security → "Make a new secret". The old secret keeps working for 7 days; move your server to the new
one in that time.

## 5. Opening the messenger

Nothing of Clomni shows until the app asks. Open the messenger from your own button. `source` says where in the app
it was opened and is stored with a conversation started there.

```kotlin
supportButton.setOnClickListener { Clomni.present(source = "profile_support") }
```

```swift
Button("Support") { Clomni.present(source: "profile_support") }
```

```ts
<Button title="Support" onPress={() => Clomni.present('profile_support')} />
```

```dart
ListTile(title: const Text('Support'), onTap: () => Clomni.present(source: 'profile_support'))
```

Other calls: `presentNewConversation(source)` goes straight into a new conversation, `presentConversation(id)` opens a
known one (the id comes from `onConversationStarted`), `dismiss()` closes the messenger from code.

The unread count next to the button:

```kotlin
private val unread = UnreadCountListener { count -> supportBadge.text = count.toString() }

override fun onStart() { super.onStart(); Clomni.addUnreadCountListener(unread) }
override fun onStop() { Clomni.removeUnreadCountListener(unread); super.onStop() }
```

```swift
let token = Clomni.addUnreadCountListener { count in badgeCount = count }
// when no longer needed:
Clomni.removeUnreadCountListener(token)
```

```ts
const subscription = Clomni.addEventListener('unreadCountChanged', (count) => setBadge(count));
// when no longer needed:
subscription.remove();
```

```dart
StreamBuilder<int>(
  stream: Clomni.unreadCountStream,
  builder: (context, snapshot) => Text('${snapshot.data ?? 0}'),
)
```

### Launcher (optional)

The floating button is off by default. The panel can turn it on too; the app's choice wins. `setBottomPadding` lifts it
above a bottom navigation (dp on Android).

```kotlin
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

```ts
Clomni.setLauncherVisible(true);
Clomni.setBottomPadding(72);
```

```dart
await Clomni.setLauncherVisible(true);
await Clomni.setBottomPadding(72);
```

## 6. Events and flow triggers

A button on a screen of the app can start a conversation about something, for example a problem with a ride.

**In the panel:** in the flow builder pick "App event" as the trigger, enter the event's name (`ride_problem`) and
publish the flow. On the channel's **Flows** tab it shows as "Event: ride_problem".

**In the app:** `startFlow` sends the event with its data. The flow's texts use the data as `{{data.ride_id}}`. The data
must be JSON: strings, numbers, booleans, lists, maps.

```kotlin
Clomni.startFlow("ride_problem", mapOf("ride_id" to "R-1923"), openMessenger = true, source = "ride_screen")
```

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });
```

```dart
await Clomni.startFlow('ride_problem', data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');
```

- Without a published flow bound to the event, nothing happens.
- For an event the user did not tap (a failed payment, say), keep `openMessenger` `false`. The user learns of the
  conversation from a push or the unread count.

### The SDK's events

`onMessengerOpened` (source), `onMessengerClosed`, `onConversationStarted` (the conversation's id), `onFlowCompleted`
(the flow's id) and the unread count.

```kotlin
Clomni.onConversationStarted { id -> Log.d("App", "conversation $id") }
Clomni.onFlowCompleted { flowId -> Log.d("App", "flow $flowId") }
```

```swift
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId)") }
```

```ts
Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id));
Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId));
```

```dart
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

In the native SDKs each event has one listener; `null` removes it. The React Native and Flutter packages own the
native callbacks: the app's native code should not set them as well.

## 7. Push notifications

**In the panel**, on the channel's **Push** tab:

- Android: the Firebase project's service account JSON file.
- iOS: the APNs `.p8` file, Key ID, Team ID, Bundle ID.

After uploading, check with "Test push".

The app hands the SDK its token and the pushes it receives. Your own pushes stay yours: `isClomniPush` tells Clomni's
apart.

### Android

The SDK has no Firebase dependency. The app keeps its own `firebase-messaging`:

```kotlin
class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // the app's own push
    }
}
```

```xml
<!-- AndroidManifest.xml -->
<service android:name=".AppMessagingService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

FCM calls `onNewToken` only when the token changes, so hand over the current one at start as well:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

On Android 13+ the app asks for the notification permission (the SDK never does):

```kotlin
if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
```

The SDK shows the notification. A tap opens the app with the messenger on that conversation over it. While the
messenger is open, Clomni's notifications are not shown. The small icon is the app's; for a white silhouette:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

### iOS

Add the Push Notifications capability to the app target.

```swift
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        UNUserNotificationCenter.current().delegate = self
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // A push while the app is open. Clomni's are not shown while the messenger is open.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // A tap on a notification: a Clomni push opens its conversation. @MainActor, not nonisolated: the system may
    // call this from a background queue, and Swift calls the system's completion handler where this method ends.
    // Ended off the main thread, UIKit stops the app ("Call must be made on main thread").
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // the app's own push
    }
}
```

For the operator's photo on the notification, an optional Notification Service Extension:
`ios/Examples/NotificationService`.

### React Native

```ts
import messaging from '@react-native-firebase/messaging';

const token = Platform.OS === 'ios' ? await messaging().getAPNSToken() : await messaging().getToken();
if (token) Clomni.setDeviceToken(token);   // iOS: the APNs token as hex; Android: the FCM token

if (Platform.OS === 'android') {
  // Clomni's data messages: the SDK shows the notification.
  messaging().onMessage((message) => { Clomni.handlePush(message.data ?? {}); });
  messaging().setBackgroundMessageHandler(async (message) => { Clomni.handlePush(message.data ?? {}); });
  Clomni.setNotificationIcon('clomni_notification_icon');   // from the config plugin's notificationIcon
} else {
  // A tap on a notification opens its conversation.
  messaging().onNotificationOpenedApp((message) => { Clomni.handlePush(message.data ?? {}); });
}

// iOS, a push while the app is open:
const show = Clomni.shouldShowForeground(data);
```

### Flutter

The token and the push data come from the app's own push library:

```dart
await Clomni.setDeviceToken(token); // iOS: the APNs token as hex; Android: the FCM token

// iOS: a tap on a notification (its data). Android: an FCM data message as it arrives (RemoteMessage.data);
// the SDK shows the notification, whose tap opens the conversation.
if (!await Clomni.handlePush(data)) {
  // the app's own push
}

// iOS, a push while the app is open:
final show = await Clomni.shouldShowForeground(data);
```

The icon on Android: `await Clomni.setNotificationIcon('drawable_name');`

## 8. Appearance

Colours, logo, header, Home cards and texts come from the panel, the channel's **Appearance** tab. A change reaches
the app without an update: a published change fades in on the open screen.

To put the app's own colour, font and mode over the panel's look, use `setTheme`. The colour is `#RRGGBB`; the other
brand colours are derived from it by the panel's rules. Each call replaces the last. A value left out stays the
panel's.

```kotlin
Clomni.setTheme(
    primaryColor = "#0A66C2",
    typeface = ResourcesCompat.getFont(context, R.font.montserrat),
    mode = ClomniThemeMode.DARK,
)
```

```swift
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

```ts
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

```dart
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

The mode is light, dark or system. For the font alone, `setTypeface`. The font still follows the user's text size.

- iOS: the family name of a font in the app bundle, listed under `UIAppFonts` in `Info.plist`
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: a font resource (`res/font/montserrat.xml` or `montserrat.ttf`).
- Flutter: fonts in `pubspec.yaml` do not reach the native screens by themselves. Pass each platform's name:
  `await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');`

## 9. Language, sounds, links

**Language.** The messenger speaks the languages turned on in the panel (Appearance tab). `setLanguage` picks one of
them (`az`, `en`, `ru`). `null`, or a language that is off, follows the phone's language, then the panel's main
language. With one language on, that one is always used.

**Sounds.** A short sound for a message received or sent while a conversation is open. It follows the phone's silent
mode. The panel can turn sounds off; `setSoundsEnabled(false)` turns them off whatever the panel says.

**Links.** A news item's button carries a web address or the app's own deep link. With `onLink` the link goes to the
app.

```kotlin
Clomni.setLanguage("en")
Clomni.setSoundsEnabled(false)
// true: the app opened the link; false, or no listener, lets the system open it.
Clomni.onLink { url ->
    val ownLink = url.startsWith("myapp://")
    if (ownLink) startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    ownLink
}
```

```swift
Clomni.setLanguage("en")
Clomni.setSoundsEnabled(false)
// With a listener the app opens the link; without one the system does.
Clomni.onLink = { url in UIApplication.shared.open(url) }
```

```ts
import { Linking } from 'react-native';

Clomni.setLanguage('en');
Clomni.setSoundsEnabled(false);
Clomni.onLink((url) => Linking.openURL(url)); // null: the system opens links
```

```dart
// launchUrl: from the url_launcher package
await Clomni.setLanguage('en');
await Clomni.setSoundsEnabled(false);
await Clomni.onLink((url) => launchUrl(Uri.parse(url))); // null: the system opens links
```

## 10. Logout

Call it with the app's own logout. It ends the session and deletes the messenger's data on this device. Without it,
the phone's next user sees the previous one's conversations.

```kotlin
Clomni.logout()
```

```swift
Clomni.logout()
```

```ts
Clomni.logout();
```

```dart
await Clomni.logout();
```

## 11. Troubleshooting

Turn logs on while developing. The default level is `warning`; integration mistakes are logged as `error`.

```kotlin
if (BuildConfig.DEBUG) Clomni.setLogLevel(ClomniLogLevel.DEBUG)
```

```swift
#if DEBUG
Clomni.setLogLevel(.debug)
#endif
```

```ts
if (__DEV__) Clomni.setLogLevel('debug');
```

```dart
if (kDebugMode) await Clomni.setLogLevel(ClomniLogLevel.debug);
```

Where the logs are:

- Android: logcat, tag `Clomni`.
- iOS: the Xcode console and Console.app, subsystem `ai.clomni.messenger`, category `Clomni`.
- React Native and Flutter: the native logs above. In Flutter, errors of the Dart side start with `[Clomni]`.

Common errors:

| Log or symptom | Cause | What to do |
|---|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | The key is wrong, revoked or another platform's | `android_…` key on Android, `ios_…` on iOS |
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | The hash does not match | Same `user_id` string, lower-case hex, the current secret; without `userId` the lower-cased email. Security → "Test a hash" |
| `call Clomni.initialize first` | A method was called before `initialize` | `initialize` at start (on Android in `Application.onCreate`) |
| `initialize was called before; the first call stays` | `initialize` was called twice | Call it once |
| `this App SDK inbox is switched off in Clomni` | The channel is switched off in the panel | Switch it on; until then `present()` does nothing |
| `setTheme: primaryColor "…" is not #RRGGBB` | Colour format | `#RRGGBB` |
| `startFlow` does nothing | No published flow is bound to the event | "App event" trigger in the flow builder, the same name, published |
| Android: no notification, `notification not shown (POST_NOTIFICATIONS?)` | Permission not granted | Ask for `POST_NOTIFICATIONS` on Android 13+ |
| Android: `push token not registered: …` | The token did not reach the server | The `setDeviceToken` call; the Firebase JSON in the panel |
| iOS: no push arrives | Capability, `.p8` or Bundle ID | The keys on the Push tab, "Test push" |
| iOS: `no window to present the messenger from` | `present` was called before a window exists | Call it once a screen is shown |
| iOS: `font family "…" is not in the app; the system font stays` | The font is not in the bundle | Add it to `UIAppFonts` |
| React Native: the native module is not found | Expo Go | A development build (`npx expo prebuild`) |
| Flutter, Android: the launcher does not show | `MainActivity` | `FlutterFragmentActivity` |
