# @clomni/react-native

The Clomni Messenger in a React Native app. The JS API only calls the native iOS and Android SDKs, which draw the
messenger natively. It does not use a WebView.

React Native 0.72 or later; the New Architecture (TurboModule) needs 0.76 or later, older versions use the old
architecture's bridge. Expo SDK 50 or later in a development build (`npx expo prebuild`); Expo Go cannot load native
modules.

## Install

```sh
npm install @clomni/react-native
cd ios && pod install
```

The iOS pod (`ClomniReactNative`) brings the iOS SDK (`ClomniMessenger`, CocoaPods); the Android module brings the
Android SDK (`ai.clomni:messenger`, Maven Central). Autolinking does the rest.

Until the native SDKs are published, point both to a checkout of this repository:

- iOS, in the app's `Podfile`: `pod 'ClomniMessenger', :path => '../path/to/clomni-mobile-sdk'`
- Android, in the app's `android/settings.gradle`:

  ```groovy
  includeBuild("../path/to/clomni-mobile-sdk/android") {
      dependencySubstitution {
          substitute(module("ai.clomni:messenger")).using(project(":messenger"))
      }
  }
  ```

## Use

```ts
import { Platform } from 'react-native';
import Clomni from '@clomni/react-native';

// Once, at the app's start: the App ID and the API key of this platform from Clomni (Channels → Mobile app).
Clomni.initialize('app_…', Platform.OS === 'ios' ? 'ios_…' : 'android_…');

// When the app's user logs in. userHash = hex(HMAC-SHA256(identity_secret, userId)), made on the app's server.
Clomni.loginUser({ userId: '5', email: 'aysel@example.com', name: 'Aysel' }, userHash);
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });

// The app's own buttons open the messenger; nothing of Clomni shows until then.
Clomni.present('profile_support');
Clomni.startFlow('ride_problem', { ride_id: 'R-1042' }, { openMessenger: true, source: 'ride_detail' });

// The unread count for the app's own badge: at once, then on every change.
const subscription = Clomni.addEventListener('unreadCountChanged', (count) => setBadge(count));
subscription.remove();

// When the user logs out, or the next user of the phone sees this one's conversations.
Clomni.logout();
```

### Push

Pass the token and the notifications from the app's push library:

```ts
Clomni.setDeviceToken(token); // iOS: the APNs device token as hex; Android: the FCM token

// A tap on a notification (data: APNs userInfo or FCM data)
if (!Clomni.handlePush(data)) {
  // the app's own push
}

// iOS, a push while the app is open: not shown while the messenger is open
const show = Clomni.shouldShowForeground(data);
```

`isClomniPush(data)` tells Clomni's pushes from the app's own. Android only: `setNotificationIcon(drawableName)`.

## API

| Call | |
|---|---|
| `initialize(appId, apiKey, region = 'eu')` | once, at the app's start |
| `loginUser(user, userHash?)`, `loginUnidentifiedUser()`, `updateUser({ name?, language?, customAttributes? })`, `logout()` | the user |
| `present(source?)`, `presentNewConversation(source?)`, `presentConversation(id)`, `dismiss()` | opening and closing |
| `startFlow(event, data?, { openMessenger?, source? })` | the flow bound to an app event |
| `setLauncherVisible(visible)`, `setBottomPadding(padding)` | the optional floating button |
| `setDeviceToken(token)`, `isClomniPush(data)`, `handlePush(data)`, `shouldShowForeground(data)` (iOS), `setNotificationIcon(name)` (Android) | push |
| `setLogLevel('none' \| 'error' \| 'warning' \| 'info' \| 'debug')`, `setTypeface(familyName \| null)` | log and font |
| `addEventListener(name, listener)` → `{ remove() }` | `unreadCountChanged`, `messengerOpened`, `messengerClosed`, `conversationStarted`, `flowCompleted` |

The module owns the SDK's native event callbacks; native code of the app should not set them as well.

## Development

```sh
npm ci
npx tsc --noEmit                 # against React Native's own types
npx jest                         # the JS layer, with react-native replaced by a recording fake (test/react-native.ts)
node scripts/codegen.js          # React Native's codegen on src/NativeClomni.ts; specs in node_modules/.clomni-codegen
```

The Android module compiles on its own against Maven Central's `react-android`, with the Android SDK from `../android`
(`android/settings.gradle`):

```sh
cd android
../../android/gradlew -PclomniReactNativeVersion=0.86.0 :compileDebugKotlin        # old architecture
../../android/gradlew -PclomniReactNativeVersion=0.86.0 \
  -PclomniCodegenDir=../node_modules/.clomni-codegen/android/java :compileDebugKotlin   # New Architecture
```

Without Xcode, `scripts/typecheck-ios-bridge.sh` type-checks `ios/ClomniBridge.swift` against the iOS SDK's API;
`ios/RCTClomni.mm` is compiled by an app's build only.
