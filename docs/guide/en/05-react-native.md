# React Native

The package `@clomni/react-native` wraps the native Android and iOS SDKs. The screens are the native ones.

## Requirements

- React Native 0.75 or newer (0.76 or newer for the New Architecture). Expo SDK 52 or newer in a development build.
- iOS 15, Android 6.0 (API 23).
- The App ID and both API keys (`android_…`, `ios_…`) from **Installation** in the inbox's settings column.

## Install

```sh
npm install @clomni/react-native
cd ios && pod install
```

Autolinking does the rest. On Android the module brings `ai.clomni:messenger` from Maven Central. On iOS `pod install`
adds the iOS SDK to the Pods project as a Swift package (React Native's `spm_dependency`), and Xcode fetches it on the
first build.

If the iOS link fails on `ClomniMessenger` symbols (React Native warns that a Swift package in static pods "might cause
linker errors"), or if you wire push in native code as shown below, add the iOS SDK as a pod to the app's target. The
package then uses that pod and adds no Swift package:

```ruby
# ios/Podfile, in the app's target
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Expo

Expo Go cannot load native modules. Use a development build (`npx expo prebuild`, `npx expo run:ios` /
`run:android`, or an EAS build). The package's config plugin writes what the native projects need:

```ts
// app.config.ts
export default {
  // ...
  plugins: [
    ['@clomni/react-native', {
      photoLibraryPermission: 'To send photos to support',      // iOS
      cameraPermission: 'To take and send photos to support',   // iOS
      push: true,                                               // the default
      notificationIcon: './assets/notification-icon.png',       // Android, a white silhouette PNG
    }],
  ],
};
```

With `push: true` the plugin adds the `aps-environment` entitlement and the `remote-notification` background mode on
iOS, and the `POST_NOTIFICATIONS` permission on Android. The icon is copied as the drawable
`clomni_notification_icon`.

In a bare React Native app, add the two iOS texts to `Info.plist` yourself (see the [iOS chapter](04-ios.md#infoplist)).

On iOS, add the permission texts for photos, the camera and the microphone to the app's `Info.plist`: [iOS →
Info.plist](04-ios.md#infoplist).

## Initialize

Once, at the app's start, outside any component. `index.js` is a good place, because a push can start the app
without a screen.

```js
// index.js
import { AppRegistry, Platform } from 'react-native';
import Clomni from '@clomni/react-native';
import App from './App';
import { name as appName } from './app.json';

Clomni.initialize('app_…', Platform.OS === 'ios' ? 'ios_…' : 'android_…');
if (__DEV__) Clomni.setLogLevel('debug');

AppRegistry.registerComponent(appName, () => App);
```

The third parameter of `initialize` is `region`, `'eu'` by default. `'eu'` is the only region today, so there is no need
to pass it: the SDK logs any other value and uses `'eu'`.

## The user

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, hashFromYourServer);
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });

// With your app's own logout:
Clomni.logout();
```

See [Identifying users](02-identity.md) for the hash.

Call `loginUser` on every app start while the user is signed in, as if they had just signed in. For the same user the
SDK reuses its stored session.

A user who has not signed in needs no call: the Messenger makes an anonymous visitor itself when it opens.
`Clomni.loginUnidentifiedUser()` does it in advance. The visitor stays the same on this device until `logout`; when
`loginUser` is called, their conversations move to the user.

## Open the Messenger

```tsx
import { useEffect, useState } from 'react';
import { Pressable, Text } from 'react-native';
import Clomni from '@clomni/react-native';

export function SupportRow() {
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    // Hears the current count at once, then every change.
    const subscription = Clomni.addEventListener('unreadCountChanged', setUnread);
    return () => subscription.remove();
  }, []);

  return (
    <Pressable onPress={() => Clomni.present('profile_support')}>
      <Text>Support{unread > 0 ? ` (${unread})` : ''}</Text>
    </Pressable>
  );
}
```

| Call | What it does |
|---|---|
| `Clomni.present(source?)` | Opens Home |
| `Clomni.presentNewConversation(source?)` | Opens a new conversation straight away |
| `Clomni.presentConversation(id)` | Opens a known conversation; the ID comes from `conversationStarted` |
| `Clomni.dismiss()` | Closes the Messenger from code |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | The optional floating button |

## Flows and events

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });

const subscriptions = [
  Clomni.addEventListener('messengerOpened', (source) => console.log('opened from', source)),
  Clomni.addEventListener('messengerClosed', () => console.log('closed')),
  Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id)),
  Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId)),
];
// later: subscriptions.forEach((s) => s.remove());
```

The flow needs the "App event" trigger with the same name in the panel, and must be published. The data must be JSON.

The module owns the native SDK's event callbacks. Do not set them in the app's native code as well.

**The event name is not the flow's name.** Pass `startFlow` the name on the flow's "Event: …" line in the panel's Flows
section. The flow must use the "App event" trigger: a flow with the "When a conversation starts" trigger does not start
with `startFlow`.

## Links, language, sounds and look

```ts
import { Linking } from 'react-native';

Clomni.onLink((url) => Linking.openURL(url));   // or your own router; null: the system opens links
Clomni.setLanguage('en');                       // 'az', 'en', 'ru'; null follows the phone
Clomni.setSoundsEnabled(false);
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

The font is the family name you use in `fontFamily` styles. On iOS the font must be in the app and listed under
`UIAppFonts`; on Android React Native finds it in `android/app/src/main/assets/fonts` or `res/font`. For the font
alone: `Clomni.setTypeface('Montserrat')`.

## Push notifications

Upload the keys to the panel first ([Push keys](08-push-keys.md)). The examples use
`@react-native-firebase/messaging` for Android. Any push library works if it gives you the token and the message
data.

### Android

Firebase setup: `google-services.json` and the Google services Gradle plugin, as the
[React Native Firebase docs](https://rnfirebase.io) describe. Then:

```js
// index.js, next to initialize
import messaging from '@react-native-firebase/messaging';

// Clomni's data messages while the app is in the background or closed: the SDK shows the notification.
messaging().setBackgroundMessageHandler(async (message) => {
  Clomni.handlePush(message.data ?? {});
});
```

```ts
// App.tsx
import { useEffect } from 'react';
import { PermissionsAndroid, Platform } from 'react-native';
import messaging from '@react-native-firebase/messaging';
import Clomni from '@clomni/react-native';

useEffect(() => {
  if (Platform.OS !== 'android') return;
  PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);   // Android 13+
  messaging().getToken().then((token) => Clomni.setDeviceToken(token));
  const unsubscribeToken = messaging().onTokenRefresh((token) => Clomni.setDeviceToken(token));
  // Messages while the app is open.
  const unsubscribeMessage = messaging().onMessage(async (message) => {
    if (!Clomni.handlePush(message.data ?? {})) {
      // the app's own push
    }
  });
  Clomni.setNotificationIcon('clomni_notification_icon');   // the config plugin's notificationIcon
  return () => { unsubscribeToken(); unsubscribeMessage(); };
}, []);
```

In a bare app, declare `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` in
`AndroidManifest.xml`, put a white icon into `android/app/src/main/res/drawable/` and pass its name to
`setNotificationIcon`.

### iOS

Clomni sends iOS pushes straight to APNs, not through Firebase. Firebase's library reports only messages sent through
FCM, so it does not see a tap on a Clomni notification. Wire the tap in native code:

1. Add the Push Notifications capability in Xcode (see the [iOS chapter](04-ios.md#1-capability)).
2. Add the `pod 'ClomniMessenger'` line to `ios/Podfile` (see Install above), so the app's own code can
   `import ClomniMessenger`. Run `pod install`.
3. Add this file to the app target:

```swift
// ios/<YourApp>/ClomniNotifications.swift
import ClomniMessenger
import UserNotifications

/// Clomni pushes: hidden while the Messenger is open, and a tap opens the conversation.
@objc(ClomniNotifications)
final class ClomniNotifications: NSObject, UNUserNotificationCenterDelegate {
    @objc static let shared = ClomniNotifications()

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

4. Make it the notification delegate in `application(_:didFinishLaunchingWithOptions:)`, before it returns:

```swift
// AppDelegate.swift
UNUserNotificationCenter.current().delegate = ClomniNotifications.shared
```

```objc
// AppDelegate.mm, if the app's delegate is Objective-C
#import "YourApp-Swift.h"
#import <UserNotifications/UserNotifications.h>

[UNUserNotificationCenter currentNotificationCenter].delegate = ClomniNotifications.shared;
```

React Native Firebase takes over the delegate after launch and passes every push that is not its own on to this one,
so FCM keeps working for your own pushes.

5. Hand over the APNs token from JavaScript:

```ts
if (Platform.OS === 'ios') {
  await messaging().requestPermission();
  const apnsToken = await messaging().getAPNSToken();   // hex
  if (apnsToken) Clomni.setDeviceToken(apnsToken);
}
```

Without Firebase on iOS, hand the token over natively instead:
`Clomni.setDeviceToken(deviceToken)` in `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, as in the
[iOS chapter](04-ios.md#2-appdelegate).

In an Expo app the `ios` folder is generated by `npx expo prebuild`. Keep steps 3 and 4 in a small config plugin of
your own (`withAppDelegate` and `withXcodeProject` from `expo/config-plugins`), or commit the generated `ios` folder.

`Clomni.isClomniPush(data)` tells a Clomni push from your own.

## Problems

| Symptom | What to do |
|---|---|
| "The package doesn't seem to be linked" or the native module is not found | Rebuild the app after installing. In Expo, use a development build, not Expo Go |
| iOS link errors on `ClomniMessenger` symbols | Add the `pod 'ClomniMessenger'` line to the Podfile and run `pod install` |
| Android notifications do not appear while the app is closed | `setBackgroundMessageHandler` must be registered in `index.js`, outside components |
| A tap on a Clomni notification on iOS only opens the app | The native delegate (steps 3 and 4) is missing or set after launch |
| The floating button does not show on a cold start of the app | Fixed in SDK 1.0.2. Until then, open the Messenger from your own button |
| Android: the open Messenger disappears when the app is opened again from its icon (`MainActivity` is `singleTask`) | Fixed in SDK 1.0.2 |

The logs are on the native side: logcat tag `Clomni` on Android, the Xcode console on iOS. The default level is
`warning`, and integration mistakes are written as `error`; `setLogLevel('debug')` also shows the SDK's steps. More in
[Troubleshooting](09-troubleshooting.md).
