# Troubleshooting

## Where to look first

1. **The panel's Overview section.** It shows whether each platform has connected, whether push is active, and warnings
   such as "logins refused for a wrong hash" or "push is not set up", each with a **Fix** button.
2. **The SDK's log.** Turn on the debug level while developing. The default level is `warning`, and integration
   mistakes are logged as `error`.

| Platform | Turn on | Where the log is |
|---|---|---|
| Android | `Clomni.setLogLevel(ClomniLogLevel.DEBUG)` | logcat, tag `Clomni` |
| iOS | `Clomni.setLogLevel(.debug)` | Xcode console and Console.app: subsystem `ai.clomni.messenger`, category `Clomni` |
| React Native | `Clomni.setLogLevel('debug')` | the native logs above |
| Flutter | `await Clomni.setLogLevel(ClomniLogLevel.debug)` | the native logs above; Dart-side errors start with `[Clomni]` |
| Unity | `Clomni.SetLogLevel(ClomniLogLevel.Debug)` | the native logs above |

Some server messages are in Azerbaijani, exactly as the table below shows them.

## Setup

| Log or symptom | Cause | What to do |
|---|---|---|
| `call Clomni.initialize first` | A method was called before `initialize` | Call `initialize` at start; on Android in `Application.onCreate` |
| `initialize was called before; the first call stays` | `initialize` was called twice | Call it once. To switch keys, restart the app |
| `api_key səhvdir və ya bu platforma üçün deyil` | The API key is wrong, revoked, older than 7 days after a new one was made, or of the other platform | The `android_…` key on Android, the `ios_…` key on iOS. Check the key under **Installation** |
| `this App SDK inbox is switched off in Clomni` | The inbox is switched off in the panel | Switch it on. Until then `present()` does nothing |
| Nothing opens, nothing in the log | The log level is too low, or the call happens in the Unity Editor | Turn on the debug level; test on a device |
| `setTheme: primaryColor "…" is not #RRGGBB` | Colour format | Six hex digits with `#`, for example `#0A66C2` |
| iOS: `no window to present the messenger from yet` | `present` was called before a screen exists | Call it from a button or once a screen is shown |
| iOS: `font family "…" is not in the app; the system font stays` | The font is not in the bundle | Add it to the target and to `UIAppFonts` |
| The app cannot reach the server in a company network | A proxy or allow-list blocks the host | Allow `app.clomni.ai` (HTTPS and WebSocket) |

## Users

| Log or symptom | Cause | What to do |
|---|---|---|
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | The hash does not match | Same `user_id` string as in `loginUser`, lower-case hex, the current secret. Without `userId`, the trimmed lower-case e-mail. Check with Security → Test a hash |
| `403 identity_verification_failed` | Enforced mode and no hash, or a wrong one | Send the hash, or switch back to Recommended until every app version sends it |
| The next user of the phone sees the previous user's conversations | `logout` is not called | Call `Clomni.logout()` with your app's own logout |
| The user's name or e-mail is missing for agents | `loginUser` is called without them, or before your login finished | Pass the fields; use `updateUser` for later changes |

## Flows, look and texts

| Symptom | Cause | What to do |
|---|---|---|
| `startFlow` does nothing | No published flow is bound to the event | In the flow builder: trigger "App event", the same name, published. **Flows** shows the event name |
| `{{data.…}}` stays empty in the flow's text | The key in `startFlow`'s data has another name | Use the same key in the app and in the flow |
| A panel change does not show in the app | The Appearance draft is not published | Appearance → **Publish** |
| The Messenger speaks another language than expected | `setLanguage` picked a language that is off, or none was picked | Turn the language on in Appearance → Languages, or call `setLanguage` |
| The floating button does not show | It is off in the panel and in code | `setLauncherVisible(true)`, or turn it on in Appearance → Theme |
| Flutter, Android: the floating button does not show | `MainActivity` extends `FlutterActivity` | Extend `FlutterFragmentActivity` |

## Push notifications

Start with **Push** in the side menu → **Test push**. The answer there is what FCM or APNs replied, and the table in
[Push keys](08-push-keys.md#test-push) explains each answer.

| Symptom | Cause | What to do |
|---|---|---|
| The device is not in the Test push list | No token reached Clomni | Allow notifications on the phone; check the `setDeviceToken` call; open the Messenger once |
| Android: no notification, `notification not shown (POST_NOTIFICATIONS?)` | No permission on Android 13+ | Ask for `POST_NOTIFICATIONS` |
| Android: `push token not registered: …` | The token did not reach the server | Check the network and the `setDeviceToken` call |
| Android: notifications only while the app is open | The data message is handled only in the UI | Hand the message to `ClomniPush.handle` in `FirebaseMessagingService` (React Native: `setBackgroundMessageHandler`, Flutter: `onBackgroundMessage`) |
| Android: a grey square instead of the icon | The app icon is not a silhouette | `setNotificationIcon` with a white icon |
| Android: `SENDER_ID_MISMATCH` | The service account and `google-services.json` are of different Firebase projects | Upload the service account of the app's project |
| iOS: `BadEnvironmentKeyInToken` | The APNs key is limited to one environment | Make a key for Sandbox & Production |
| iOS: `InvalidProviderToken` | Wrong Key ID or Team ID, or the key was revoked | Check both IDs; upload the key again |
| iOS: `DeviceTokenNotForTopic` | The Bundle ID under **Push** is not the app's | Enter the app's Bundle ID |
| iOS: works from Xcode, not from TestFlight (or the other way round) | The key covers one environment only | A Sandbox & Production key |
| iOS: a tap on a Clomni notification only opens the app | The tap does not reach `handlePush` | Native iOS: the delegate in AppDelegate. React Native and Flutter: the native delegate in their chapters; Firebase's libraries do not see Clomni pushes on iOS |
| iOS: the app crashes on a tap with "Call must be made on main thread" | The async delegate method is `nonisolated` | Mark it `@MainActor` |
| A Clomni notification appears while the Messenger is open | `shouldShowForeground` is not used | Return no presentation options when it is false |

## Keys after a change

- A new API key: the old one works for 7 more days. App versions with the old key stop connecting after that.
- A revoked API key stops at once.
- A new Identity Secret: the old one works for 7 more days. Test a hash says which secret a hash was made with.
- A new push key: upload it under **Push**; the next push uses it.

## Asking for help

Write to Clomni support with:

- the platform and the SDK version (`Clomni.version` in Kotlin and Swift);
- the App ID (never the Identity Secret or a full API key);
- what **Overview** says, and the SDK's log at debug level around the problem;
- for push: the answer of Test push.
