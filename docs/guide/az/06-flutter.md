# Flutter

`clomni_flutter` plugin-i native Android və iOS SDK-larının üstündədir. Ekranlar native ekranlardır.

## Tələblər

- Flutter 3.16 və ya daha yeni.
- iOS 15, Android API 24.
- Paneldə kanalın ayarlar sütununun **Quraşdırma** bölməsindən App ID və hər iki API açarı (`android_…`, `ios_…`).

## Quraşdırma

```sh
flutter pub add clomni_flutter
```

**iOS.** iOS SDK Swift package-dir:

- Swift Package Manager ilə (indiki Flutter-də standart olaraq açıqdır; 3.24-dən
  `flutter config --enable-swift-package-manager` ilə) plugin SDK-nı özü götürür.
- CocoaPods ilə bu sətri `ios/Podfile`-a, `target 'Runner'` içinə əlavə edin, sonra `pod install` işlədin. Sətir
  olmasa `pod install` dayanır və həmin sətri çap edir.

  ```ruby
  pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.0'
  ```

Şəkil mətnlərini `ios/Runner/Info.plist`-ə əlavə edin ([iOS bölməsinə](04-ios.md#infoplist) baxın).

**Android.** Tətbiqin `MainActivity`-si `FlutterActivity` yox, `FlutterFragmentActivity`-dən törəməlidir:

```kotlin
// android/app/src/main/kotlin/com/example/app/MainActivity.kt
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

iOS-da tətbiqin `Info.plist`-inə şəkil, kamera və mikrofon üçün icazə mətnlərini əlavə edin: [iOS →
Info.plist](04-ios.md#infoplist).

## Başlatma

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

## İstifadəçi

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: hashFromYourServer,
);
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});

// Tətbiqin öz çıxışı ilə birlikdə:
await Clomni.logout();
```

Hash üçün bax: [İstifadəçinin tanıdılması](02-identity.md).

Tətbiq hər açılanda, istifadəçi daxil olubsa, `loginUser`-i yenidən çağırın, istifadəçi təzə daxil olmuş kimi. Eyni
istifadəçi üçün SDK saxlanmış sessiyanı işlədir.

## Messenger-i açmaq

```dart
class SupportTile extends StatelessWidget {
  const SupportTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Clomni.unreadCountStream, // cari say dərhal, sonra hər dəyişiklik
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return ListTile(
          title: const Text('Dəstək'),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => Clomni.present(source: 'profile_support'),
        );
      },
    );
  }
}
```

| Çağırış | Nə edir |
|---|---|
| `Clomni.present(source: …)` | Ana səhifəni açır |
| `Clomni.presentNewConversation(source: …)` | Birbaşa yeni söhbət açır |
| `Clomni.presentConversation(id)` | Məlum söhbəti açır; ID `onConversationStarted`-dən gəlir |
| `Clomni.dismiss()` | Messenger-i koddan bağlayır |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | İstəyə bağlı üzən düymə |

## Flow-lar və hadisələr

```dart
await Clomni.startFlow('ride_problem',
    data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');

Clomni.onMessengerOpened.listen((source) => debugPrint('opened from $source'));
Clomni.onMessengerClosed.listen((_) => debugPrint('closed'));
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

Flow üçün paneldə eyni adla "Tətbiq hadisəsi" trigger-i lazımdır və flow dərc olunmalıdır. Data JSON olmalıdır.
Native SDK-nın hadisə callback-lərini plugin özü tutur. Onları tətbiqin native kodunda ayrıca təyin etməyin.

**Hadisənin adı flow-un adı deyil.** `startFlow`-a paneldəki Flow-lar bölməsində flow-un altındakı "Hadisə: …"
sətrindəki adı verin. Flow "Tətbiq hadisəsi" trigger-i ilə qurulmalıdır: "Söhbət başlayanda" trigger-li flow `startFlow`
ilə başlamır.

## Linklər, dil, səslər və görünüş

```dart
import 'package:url_launcher/url_launcher.dart';

await Clomni.onLink((url) => launchUrl(Uri.parse(url)));   // null: linkləri sistem açır
await Clomni.setLanguage('en');                            // 'az', 'en', 'ru'; null telefonun dilinə uyğunlaşır
await Clomni.setSoundsEnabled(false);
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

`pubspec.yaml`-dakı şriftlər native ekranlara çatmır. Hər platformanın öz adını verin:

- iOS: tətbiqin bundle-ındakı və `ios/Runner/Info.plist`-də `UIAppFonts` altında yazılmış şriftin ailə adı
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: şrift resursu, `android/app/src/main/res/font/montserrat.ttf` → `'montserrat'`.

```dart
await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');
```

## Push bildirişləri

Əvvəlcə açarları panelə yükləyin ([Push açarları](08-push-keys.md)). Nümunələr Android üçün `firebase_messaging`
işlədir. Tokeni və mesajın datasını verən istənilən push kitabxanası olar.

### Android

Firebase-i [FlutterFire sənədlərində](https://firebase.flutter.dev) yazıldığı kimi qurun (`flutterfire configure`)
və icazəni `android/app/src/main/AndroidManifest.xml`-də elan edin:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```dart
import 'dart:io' show Platform;

import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// Tətbiq arxa planda və ya bağlı olanda gələn Clomni data mesajları: bildirişi SDK göstərir.
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
  await messaging.requestPermission(); // Android 13+: sistemin icazə pəncərəsi
  final token = await messaging.getToken();
  if (token != null) await Clomni.setDeviceToken(token);
  messaging.onTokenRefresh.listen(Clomni.setDeviceToken);
  // Tətbiq açıq olanda gələn mesajlar.
  FirebaseMessaging.onMessage.listen((message) async {
    if (!await Clomni.handlePush(message.data)) {
      // tətbiqin öz push-u
    }
  });
  await Clomni.setNotificationIcon('ic_notification'); // android/app/src/main/res/drawable/ic_notification.png
}
```

`setUpAndroidPush()`-u Android-də istifadəçilərinizə uyğun anda çağırın, məsələn login-dən sonra.

### iOS

Clomni iOS push-larını Firebase-dən keçirmədən birbaşa APNs-ə göndərir. `firebase_messaging` yalnız FCM-dən gələn
mesajları bildirir, ona görə Clomni bildirişinə toxunuşu görmür. Toxunuşu Runner-in native kodunda bağlayın:

1. Xcode-da (`ios/Runner.xcworkspace`): Runner hədəfi → **Signing & Capabilities** → **+ Capability** →
   **Push Notifications**.
2. Runner-in öz kodu `ClomniMessenger`-i import edir. CocoaPods ilə yuxarıdakı Podfile sətri kifayətdir. Swift
   Package Manager ilə paketi Runner hədəfinə də əlavə edin: **File → Add Package Dependencies**,
   `https://github.com/clomni/clomni-mobile-sdk.git`, məhsul `ClomniMessenger`, hədəf Runner.
3. Bu faylı Runner hədəfinə əlavə edin:

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

4. `AppDelegate.swift`-də onu bildiriş delegate-i edin, **`super.application(...)`-dan əvvəl**:

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

`firebase_messaging` `super.application(...)` zamanı delegate-i öz üzərinə götürür və özünə aid olmayan hər push-u
bu delegate-ə ötürür. Ona görə öz push-larınız üçün FCM işləməyə davam edir.

5. APNs tokenini Dart-dan verin:

```dart
if (Platform.isIOS) {
  await FirebaseMessaging.instance.requestPermission();
  final apnsToken = await FirebaseMessaging.instance.getAPNSToken(); // hex
  if (apnsToken != null) await Clomni.setDeviceToken(apnsToken);
}
```

iOS-da Firebase yoxdursa, tokeni native kodda verin: `AppDelegate`-də
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` metodunu override edin,
`Clomni.setDeviceToken(deviceToken)`, sonra `super` çağırın.

## Problemlər

| Əlamət | Nə etməli |
|---|---|
| `pod install` dayanır və `pod 'ClomniMessenger'` sətrini çap edir | Həmin sətri `ios/Podfile`-a, `target 'Runner'` içinə əlavə edin |
| Android: üzən düymə görünmür və ya Messenger açılanda tətbiq çökür | `MainActivity` `FlutterFragmentActivity`-dən törəməlidir |
| Android-də tətbiq bağlı olanda bildirişlər gəlmir | `FirebaseMessaging.onBackgroundMessage`-i `runApp`-dan əvvəl, top-level funksiya ilə qeydə alın |
| iOS: `ClomniNotifications.swift`-də `No such module 'ClomniMessenger'` | Paketi və ya pod-u Runner hədəfinə əlavə edin (2-ci addım) |
| iOS-da Clomni bildirişinə toxunanda yalnız tətbiq açılır | Delegate (3-cü və 4-cü addımlar) yoxdur və ya `super.application(...)`-dan sonra təyin olunur |

Dart tərəfinin xətaları Flutter logunda `[Clomni]` ilə başlayır. Native loglar logcat-da (`Clomni` tag-i) və Xcode
konsolundadır. Daha çoxu: [Problemlərin həlli](09-troubleshooting.md).
