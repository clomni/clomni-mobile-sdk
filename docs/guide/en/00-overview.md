# Clomni Mobile SDK: integration guide

The Clomni Mobile SDK opens the Clomni Messenger inside your iOS or Android app. Your users write to your support
team without leaving the app, and the conversations reach your agents in Clomni next to WhatsApp, Instagram and the
website chat.

![The Messenger inside an app: Home, a language choice, a flow step and an agent's reply](../images/sdk-screens.png)

*The screenshots in this guide come from the Android SDK. The iOS SDK draws the same screens.*

## What the SDK does

- Opens the Messenger with native screens. There is no WebView.
- Runs your Clomni flows with native buttons: language choice, menus, forms, handover to an agent.
- Shows replies as push notifications while the app is closed.
- Takes its colours, logo, texts and news from the Clomni panel. A change in the panel reaches the app without a new
  release.

The SDK adds nothing to your screens by itself. You open the Messenger from your own button, for example a "Support"
row on the profile screen. A floating button is available, but it is off unless you turn it on.

## Packages

| Platform | Package | Minimum |
|---|---|---|
| Android | `ai.clomni:messenger:1.0.3` (Maven Central) | Android 6.0 (API 23), Kotlin 1.8 |
| iOS | Swift Package `https://github.com/clomni/clomni-mobile-sdk.git`, version 1.0.3, product `ClomniMessenger` | iOS 15, Xcode 15 |
| React Native | `@clomni/react-native` | React Native 0.75 |
| Flutter | `clomni_flutter` | Flutter 3.16, iOS 15, Android API 24 |
| Unity | `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.3` | Unity 2021.3, iOS 15, Android API 23 |

React Native, Flutter and Unity use the native Android and iOS SDKs underneath, so everything in this guide works the
same way on every platform.

The SDK talks to `https://app.clomni.ai/v1` over HTTPS and a WebSocket on the same host. If your company network or
an MDM profile only allows listed hosts, add this one.

## The steps

1. **In the Clomni panel**, create a "Mobile app (App SDK)" inbox. You get an App ID, an API key for each platform
   and an Identity Secret. See [The Clomni panel](01-panel.md).
2. **On your server**, compute a `user_hash` for each logged-in user with the Identity Secret. See
   [Identifying users](02-identity.md).
3. **In the app**, add the package, call `initialize` at start, log the user in and open the Messenger from your
   button. See the chapter for your platform:
   [Android](03-android.md), [iOS](04-ios.md), [React Native](05-react-native.md), [Flutter](06-flutter.md),
   [Unity](07-unity.md).
4. **Push notifications**: upload the Firebase and APNs keys to the panel ([Push keys](08-push-keys.md)) and hand
   the device token to the SDK (the push section of your platform's chapter).
5. **Check** with "Test push" and **Overview** in the panel. If something does not work, see
   [Troubleshooting](09-troubleshooting.md).

## The keys

| Key | Looks like | Where it goes |
|---|---|---|
| App ID | `app_…` | In the app |
| Android API key | `android_…` | In the Android app |
| iOS API key | `ios_…` | In the iOS app |
| Identity Secret | a long random string | **Only on your server.** Never in the app |

An API key belongs to one platform: the iOS key does not work in the Android app. React Native, Flutter and Unity
apps pass the key of the platform they run on.

## Words used in this guide

- **Inbox (channel)**: one app in Clomni. Its messages, keys and settings live together.
- **Source**: a short name you pass when opening the Messenger, such as `profile_support`. It is stored with a
  conversation started there and shown in the panel's statistics.
- **Flow**: an automated conversation built in Clomni's flow builder: buttons, questions, handover to an agent.
- **App event**: a name such as `ride_problem` that your app sends with `startFlow`. A published flow bound to that
  event starts a conversation about it.
