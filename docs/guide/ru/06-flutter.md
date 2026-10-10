# Flutter

Плагин `clomni_flutter` — обёртка над нативными SDK для Android и iOS. Экраны остаются нативными.

## Требования

- Flutter 3.16 или новее.
- iOS 15, Android API 24.
- App ID и оба API-ключа (`android_…`, `ios_…`) из раздела **Installation** в колонке настроек канала.

## Установка

```sh
flutter pub add clomni_flutter
```

**iOS.** iOS SDK — это Swift-пакет:

- Со Swift Package Manager (в актуальном Flutter включён по умолчанию; начиная с 3.24 — через
  `flutter config --enable-swift-package-manager`) плагин подключает SDK сам.
- С CocoaPods добавьте эту строку в `ios/Podfile`, внутри `target 'Runner'`, и выполните `pod install`. Без неё
  `pod install` остановится и выведет эту строку.

  ```ruby
  pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
  ```

Добавьте тексты для доступа к фото в `ios/Runner/Info.plist` (см. [главу об iOS](04-ios.md#infoplist)).

**Android.** `MainActivity` приложения должен наследовать `FlutterFragmentActivity`, а не `FlutterActivity`:

```kotlin
// android/app/src/main/kotlin/com/example/app/MainActivity.kt
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

На iOS добавьте в `Info.plist` приложения тексты разрешений для фото, камеры и микрофона: [iOS →
Info.plist](04-ios.md#infoplist). На Android голосовым сообщениям (с SDK 1.0.2) нужно `RECORD_AUDIO`, объявленное в
манифесте приложения: [Android → Требования](03-android.md#требования).

## Инициализация

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

## Пользователь

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: hashFromYourServer,
);
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});

// Вместе с выходом из вашего приложения:
await Clomni.logout();
```

О хеше — в главе [Идентификация пользователей](02-identity.md).

Пока пользователь вошёл в приложение, вызывайте `loginUser` при каждом запуске, как будто он только что вошёл. Для того
же пользователя SDK использует сохранённую сессию.

## Открытие Messenger

```dart
class SupportTile extends StatelessWidget {
  const SupportTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Clomni.unreadCountStream, // сразу текущее значение, затем каждое изменение
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return ListTile(
          title: const Text('Поддержка'),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => Clomni.present(source: 'profile_support'),
        );
      },
    );
  }
}
```

| Вызов | Что делает |
|---|---|
| `Clomni.present(source: …)` | Открывает главный экран |
| `Clomni.presentNewConversation(source: …)` | Сразу открывает новый диалог |
| `Clomni.presentConversation(id)` | Открывает известный диалог; ID приходит из `onConversationStarted` |
| `Clomni.dismiss()` | Закрывает Messenger из кода |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | Необязательная плавающая кнопка |

## Сценарии и события

```dart
await Clomni.startFlow('ride_problem',
    data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');

Clomni.onMessengerOpened.listen((source) => debugPrint('opened from $source'));
Clomni.onMessengerClosed.listen((_) => debugPrint('closed'));
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

В панели у сценария должен быть триггер «App event» с тем же именем, и сценарий должен быть опубликован. Данные
должны быть JSON. Колбэки событий нативного SDK принадлежат плагину; не задавайте их дополнительно в нативном коде
приложения.

**Имя события и название сценария не одно и то же.** Передайте в `startFlow` имя из строки "Event: …" под сценарием в
разделе Flows панели. Сценарий должен использовать триггер "App event": сценарий с триггером "When a conversation
starts" через `startFlow` не запускается.

## Ссылки, язык, звуки и оформление

```dart
import 'package:url_launcher/url_launcher.dart';

await Clomni.onLink((url) => launchUrl(Uri.parse(url)));   // null: ссылки открывает система
await Clomni.setLanguage('en');                            // 'az', 'en', 'ru'; null — как на телефоне
await Clomni.setSoundsEnabled(false);
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

Шрифты из `pubspec.yaml` не доходят до нативных экранов. Передайте имя, принятое на каждой платформе:

- iOS: имя семейства шрифта из бандла приложения, указанного в `UIAppFonts` в `ios/Runner/Info.plist`
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: ресурс шрифта, `android/app/src/main/res/font/montserrat.ttf` → `'montserrat'`.

```dart
await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');
```

## Push-уведомления

Сначала загрузите ключи в панель ([Ключи для push](08-push-keys.md)). В примерах для Android используется
`firebase_messaging`. Подойдёт любая push-библиотека, которая отдаёт токен и данные сообщения.

### Android

Настройте Firebase, как описано в [документации FlutterFire](https://firebase.flutter.dev) (`flutterfire configure`),
и объявите разрешение в `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```dart
import 'dart:io' show Platform;

import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// Data-сообщения Clomni, пока приложение в фоне или закрыто: уведомление показывает SDK.
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
  await messaging.requestPermission(); // Android 13+: системный запрос разрешения
  final token = await messaging.getToken();
  if (token != null) await Clomni.setDeviceToken(token);
  messaging.onTokenRefresh.listen(Clomni.setDeviceToken);
  // Сообщения, пока приложение открыто.
  FirebaseMessaging.onMessage.listen((message) async {
    if (!await Clomni.handlePush(message.data)) {
      // собственный push приложения
    }
  });
  await Clomni.setNotificationIcon('ic_notification'); // android/app/src/main/res/drawable/ic_notification.png
}
```

Вызывайте `setUpAndroidPush()` на Android в подходящий для пользователей момент, например после входа.

### iOS

Clomni отправляет push для iOS напрямую в APNs, а не через Firebase. `firebase_messaging` сообщает только о
сообщениях, отправленных через FCM, поэтому не видит нажатия на уведомление Clomni. Подключите обработку нажатия в
нативном коде Runner:

1. В Xcode (`ios/Runner.xcworkspace`): таргет Runner → **Signing & Capabilities** → **+ Capability** →
   **Push Notifications**.
2. Собственный код Runner импортирует `ClomniMessenger`. С CocoaPods достаточно строки в Podfile, указанной выше. Со
   Swift Package Manager добавьте пакет и в таргет Runner: **File → Add Package Dependencies**,
   `https://github.com/clomni/clomni-mobile-sdk.git`, продукт `ClomniMessenger`, таргет Runner.
3. Добавьте этот файл в таргет Runner:

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

4. Назначьте его делегатом уведомлений в `AppDelegate.swift`, **до** `super.application(...)`:

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

`firebase_messaging` перехватывает делегат во время `super.application(...)` и передаёт этому делегату каждый push,
который не его собственный, так что FCM продолжает работать для ваших push-уведомлений.

5. Передайте APNs-токен из Dart:

```dart
if (Platform.isIOS) {
  await FirebaseMessaging.instance.requestPermission();
  final apnsToken = await FirebaseMessaging.instance.getAPNSToken(); // hex
  if (apnsToken != null) await Clomni.setDeviceToken(apnsToken);
}
```

Если на iOS нет Firebase, передавайте токен нативно: переопределите
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` в `AppDelegate`, вызовите
`Clomni.setDeviceToken(deviceToken)`, а затем `super`.

## Проблемы

| Симптом | Что делать |
|---|---|
| `pod install` останавливается и выводит строку `pod 'ClomniMessenger'` | Добавьте эту строку в `ios/Podfile` внутри `target 'Runner'` |
| Android: плавающая кнопка не появляется или приложение падает при открытии Messenger | `MainActivity` должен наследовать `FlutterFragmentActivity` |
| На Android уведомления не появляются, когда приложение закрыто | Регистрируйте `FirebaseMessaging.onBackgroundMessage` до `runApp`, с функцией верхнего уровня |
| iOS: `No such module 'ClomniMessenger'` в `ClomniNotifications.swift` | Добавьте пакет или pod в таргет Runner (шаг 2) |
| На iOS нажатие на уведомление Clomni только открывает приложение | Нет делегата (шаги 3 и 4) или он назначен после `super.application(...)` |

Ошибки на стороне Dart начинаются с `[Clomni]` в логе Flutter; нативные логи — в logcat (тег `Clomni`) и в консоли
Xcode. Подробнее — в главе [Решение проблем](09-troubleshooting.md).
