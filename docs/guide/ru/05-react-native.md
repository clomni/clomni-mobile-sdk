# React Native

Пакет `@clomni/react-native` — обёртка над нативными SDK для Android и iOS. Экраны остаются нативными.

## Требования

- React Native 0.75 или новее (0.76 или новее для New Architecture). Expo SDK 52 или новее в development build.
- iOS 15, Android 6.0 (API 23).
- App ID и оба API-ключа (`android_…`, `ios_…`) из раздела **Installation** в колонке настроек канала.

## Установка

```sh
npm install @clomni/react-native
cd ios && pod install
```

Остальное сделает autolinking. На Android модуль подтягивает `ai.clomni:messenger` из Maven Central. На iOS
`pod install` добавляет iOS SDK в проект Pods как Swift-пакет (`spm_dependency` из React Native), и Xcode скачивает
его при первой сборке.

Если линковка на iOS падает на символах `ClomniMessenger` (React Native предупреждает, что Swift-пакет в статических
подах «might cause linker errors») или если вы подключаете push в нативном коде, как показано ниже, добавьте iOS SDK
как pod в таргет приложения. Тогда пакет использует этот pod и не добавляет Swift-пакет:

```ruby
# ios/Podfile, в таргете приложения
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
```

### Expo

Expo Go не загружает нативные модули. Используйте development build (`npx expo prebuild`, `npx expo run:ios` /
`run:android` или сборку EAS). Config plugin пакета сам прописывает всё, что нужно нативным проектам:

```ts
// app.config.ts
export default {
  // ...
  plugins: [
    ['@clomni/react-native', {
      photoLibraryPermission: 'Чтобы отправлять фото в поддержку',            // iOS
      cameraPermission: 'Чтобы снимать и отправлять фото в поддержку',         // iOS
      push: true,                                                              // по умолчанию
      notificationIcon: './assets/notification-icon.png',                      // Android, белый PNG-силуэт
    }],
  ],
};
```

С `push: true` плагин добавляет на iOS entitlement `aps-environment` и фоновый режим `remote-notification`, а на
Android — разрешение `POST_NOTIFICATIONS`. Иконка копируется как drawable `clomni_notification_icon`.

В «голом» React Native-приложении (без Expo) добавьте два текста для iOS в `Info.plist` сами (см.
[главу об iOS](04-ios.md#infoplist)).

На iOS добавьте в `Info.plist` приложения тексты разрешений для фото, камеры и микрофона: [iOS →
Info.plist](04-ios.md#infoplist).

## Инициализация

Один раз, при запуске приложения, вне компонентов. Хорошее место — `index.js`: push может запустить приложение без
экрана.

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

Третий параметр `initialize` называется `region`, по умолчанию `'eu'`. Сейчас есть только `'eu'`, передавать его не
нужно: любое другое значение SDK пишет в лог и использует `'eu'`.

## Пользователь

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, hashFromYourServer);
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });

// Вместе с выходом из вашего приложения:
Clomni.logout();
```

О хеше — в главе [Идентификация пользователей](02-identity.md).

Пока пользователь вошёл в приложение, вызывайте `loginUser` при каждом запуске, как будто он только что вошёл. Для того
же пользователя SDK использует сохранённую сессию.

Для пользователя, который не вошёл, ничего вызывать не нужно: Messenger сам создаёт анонимного посетителя при открытии.
`Clomni.loginUnidentifiedUser()` делает это заранее. Посетитель остаётся тем же на этом устройстве до `logout`, а при
вызове `loginUser` его диалоги переходят к пользователю.

## Открытие Messenger

```tsx
import { useEffect, useState } from 'react';
import { Pressable, Text } from 'react-native';
import Clomni from '@clomni/react-native';

export function SupportRow() {
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    // Сразу получает текущее значение, затем каждое изменение.
    const subscription = Clomni.addEventListener('unreadCountChanged', setUnread);
    return () => subscription.remove();
  }, []);

  return (
    <Pressable onPress={() => Clomni.present('profile_support')}>
      <Text>Поддержка{unread > 0 ? ` (${unread})` : ''}</Text>
    </Pressable>
  );
}
```

| Вызов | Что делает |
|---|---|
| `Clomni.present(source?)` | Открывает главный экран |
| `Clomni.presentNewConversation(source?)` | Сразу открывает новый диалог |
| `Clomni.presentConversation(id)` | Открывает известный диалог; ID приходит из `conversationStarted` |
| `Clomni.dismiss()` | Закрывает Messenger из кода |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | Необязательная плавающая кнопка |

## Сценарии и события

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });

const subscriptions = [
  Clomni.addEventListener('messengerOpened', (source) => console.log('opened from', source)),
  Clomni.addEventListener('messengerClosed', () => console.log('closed')),
  Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id)),
  Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId)),
];
// позже: subscriptions.forEach((s) => s.remove());
```

В панели у сценария должен быть триггер «App event» с тем же именем, и сценарий должен быть опубликован. Данные
должны быть JSON.

Колбэки событий нативного SDK принадлежат модулю. Не задавайте их дополнительно в нативном коде приложения.

**Имя события и название сценария не одно и то же.** Передайте в `startFlow` имя из строки "Event: …" под сценарием в
разделе Flows панели. Сценарий должен использовать триггер "App event": сценарий с триггером "When a conversation
starts" через `startFlow` не запускается.

## Ссылки, язык, звуки и оформление

```ts
import { Linking } from 'react-native';

Clomni.onLink((url) => Linking.openURL(url));   // или ваш собственный роутер; null: ссылки открывает система
Clomni.setLanguage('en');                       // 'az', 'en', 'ru'; null — как на телефоне
Clomni.setSoundsEnabled(false);
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

Шрифт — это имя семейства, которое вы используете в стилях `fontFamily`. На iOS шрифт должен быть в приложении и в
списке `UIAppFonts`; на Android React Native находит его в `android/app/src/main/assets/fonts` или `res/font`. Только
для шрифта: `Clomni.setTypeface('Montserrat')`.

## Push-уведомления

Сначала загрузите ключи в панель ([Ключи для push](08-push-keys.md)). В примерах для Android используется
`@react-native-firebase/messaging`. Подойдёт любая push-библиотека, которая отдаёт токен и данные сообщения.

### Android

Настройка Firebase: `google-services.json` и Gradle-плагин Google services, как описано в
[документации React Native Firebase](https://rnfirebase.io). Затем:

```js
// index.js, рядом с initialize
import messaging from '@react-native-firebase/messaging';

// Data-сообщения Clomni, пока приложение в фоне или закрыто: уведомление показывает SDK.
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
  // Сообщения, пока приложение открыто.
  const unsubscribeMessage = messaging().onMessage(async (message) => {
    if (!Clomni.handlePush(message.data ?? {})) {
      // собственный push приложения
    }
  });
  Clomni.setNotificationIcon('clomni_notification_icon');   // notificationIcon из config plugin
  return () => { unsubscribeToken(); unsubscribeMessage(); };
}, []);
```

В «голом» приложении объявите `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` в
`AndroidManifest.xml`, положите белую иконку в `android/app/src/main/res/drawable/` и передайте её имя в
`setNotificationIcon`.

### iOS

Clomni отправляет push для iOS напрямую в APNs, а не через Firebase. Библиотека Firebase сообщает только о
сообщениях, отправленных через FCM, поэтому не видит нажатия на уведомление Clomni. Подключите обработку нажатия в
нативном коде:

1. Добавьте в Xcode capability Push Notifications (см. [главу об iOS](04-ios.md#1-capability)).
2. Добавьте строку `pod 'ClomniMessenger'` в `ios/Podfile` (см. «Установка» выше), чтобы код приложения мог делать
   `import ClomniMessenger`. Выполните `pod install`.
3. Добавьте этот файл в таргет приложения:

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

4. Назначьте его делегатом уведомлений в `application(_:didFinishLaunchingWithOptions:)`, до возврата из метода:

```swift
// AppDelegate.swift
UNUserNotificationCenter.current().delegate = ClomniNotifications.shared
```

```objc
// AppDelegate.mm, если делегат приложения на Objective-C
#import "YourApp-Swift.h"
#import <UserNotifications/UserNotifications.h>

[UNUserNotificationCenter currentNotificationCenter].delegate = ClomniNotifications.shared;
```

React Native Firebase после запуска перехватывает делегат и передаёт этому делегату каждый push, который не его
собственный, так что FCM продолжает работать для ваших push-уведомлений.

5. Передайте APNs-токен из JavaScript:

```ts
if (Platform.OS === 'ios') {
  await messaging().requestPermission();
  const apnsToken = await messaging().getAPNSToken();   // hex
  if (apnsToken) Clomni.setDeviceToken(apnsToken);
}
```

Если на iOS нет Firebase, передавайте токен нативно:
`Clomni.setDeviceToken(deviceToken)` в `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, как в
[главе об iOS](04-ios.md#2-appdelegate).

В Expo-приложении папку `ios` генерирует `npx expo prebuild`. Шаги 3 и 4 держите в небольшом собственном config
plugin (`withAppDelegate` и `withXcodeProject` из `expo/config-plugins`) или закоммитьте сгенерированную папку `ios`.

`Clomni.isClomniPush(data)` отличает push от Clomni от ваших собственных.

## Проблемы

| Симптом | Что делать |
|---|---|
| «The package doesn't seem to be linked» или нативный модуль не найден | Пересоберите приложение после установки. В Expo используйте development build, а не Expo Go |
| Ошибки линковки на iOS по символам `ClomniMessenger` | Добавьте строку `pod 'ClomniMessenger'` в Podfile и выполните `pod install` |
| На Android уведомления не появляются, когда приложение закрыто | `setBackgroundMessageHandler` нужно регистрировать в `index.js`, вне компонентов |
| На iOS нажатие на уведомление Clomni только открывает приложение | Нет нативного делегата (шаги 3 и 4) или он назначен после запуска |
| Плавающая кнопка не появляется при холодном запуске приложения | Исправлено в SDK 1.0.2. До этого открывайте Messenger своей кнопкой |
| Android: открытый Messenger пропадает, когда приложение снова открывают по иконке (`MainActivity` с `singleTask`) | Исправлено в SDK 1.0.2 |

Логи пишутся на нативной стороне: на Android logcat с тегом `Clomni`, на iOS консоль Xcode. По умолчанию уровень
`warning`, ошибки интеграции пишутся как `error`; `setLogLevel('debug')` дополнительно показывает шаги SDK. Подробнее в
[Решение проблем](09-troubleshooting.md).
