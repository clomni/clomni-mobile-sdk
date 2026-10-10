# Flutter

`clomni_flutter` eklentisi yerel Android ve iOS SDK'larını sarar. Ekranlar yerel ekranlardır.

## Gereksinimler

- Flutter 3.16 veya daha yenisi.
- iOS 15, Android API 24.
- Gelen kutusunun ayarlar sütununda **Installation** bölümünden App ID ve her iki API anahtarı (`android_…`, `ios_…`).

## Kurulum

```sh
flutter pub add clomni_flutter
```

**iOS.** iOS SDK bir Swift paketidir:

- Swift Package Manager ile (güncel Flutter'da varsayılan olarak açık; 3.24'ten itibaren
  `flutter config --enable-swift-package-manager` ile) eklenti SDK'yı kendisi alır.
- CocoaPods ile bu satırı `ios/Podfile` içinde, `target 'Runner'` bloğuna ekleyin ve `pod install` çalıştırın. Satır
  yoksa `pod install` durur ve satırı ekrana yazar.

  ```ruby
  pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.2'
  ```

Fotoğraf metinlerini `ios/Runner/Info.plist` dosyasına ekleyin ([iOS bölümüne](04-ios.md#infoplist) bakın).

**Android.** Uygulamanın `MainActivity` sınıfı `FlutterActivity`'den değil, `FlutterFragmentActivity`'den
türemelidir:

```kotlin
// android/app/src/main/kotlin/com/example/app/MainActivity.kt
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

iOS'ta uygulamanın `Info.plist` dosyasına fotoğraf, kamera ve mikrofon için izin metinlerini ekleyin: [iOS →
Info.plist](04-ios.md#infoplist). Android'de sesli mesaj (SDK 1.0.2'den itibaren) için uygulamanın manifestinde
`RECORD_AUDIO` bildirilmelidir: [Android → Gereksinimler](03-android.md#gereksinimler).

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

## Kullanıcı

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: hashFromYourServer,
);
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});

// Uygulamanın kendi oturum kapatma işlemiyle birlikte:
await Clomni.logout();
```

Hash için bkz. [Kullanıcıların tanınması](02-identity.md).

Kullanıcı oturum açmışsa, uygulama her açıldığında `loginUser`'ı yeni giriş yapmış gibi yeniden çağırın. Aynı kullanıcı
için SDK kayıtlı oturumunu kullanır.

## Messenger'ı açma

```dart
class SupportTile extends StatelessWidget {
  const SupportTile({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Clomni.unreadCountStream, // güncel sayı hemen, sonra her değişiklik
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return ListTile(
          title: const Text('Destek'),
          trailing: unread > 0 ? Badge(label: Text('$unread')) : null,
          onTap: () => Clomni.present(source: 'profile_support'),
        );
      },
    );
  }
}
```

| Çağrı | Ne yapar |
|---|---|
| `Clomni.present(source: …)` | Ana sayfayı açar |
| `Clomni.presentNewConversation(source: …)` | Doğrudan yeni bir konuşma açar |
| `Clomni.presentConversation(id)` | Bilinen bir konuşmayı açar; ID `onConversationStarted`'dan gelir |
| `Clomni.dismiss()` | Messenger'ı koddan kapatır |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | İsteğe bağlı yüzen düğme |

## Akışlar ve olaylar

```dart
await Clomni.startFlow('ride_problem',
    data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');

Clomni.onMessengerOpened.listen((source) => debugPrint('opened from $source'));
Clomni.onMessengerClosed.listen((_) => debugPrint('closed'));
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

Akışın panelde aynı adla "App event" tetikleyicisine sahip olması ve yayınlanmış olması gerekir. Veri JSON
olmalıdır. Yerel SDK'nın olay callback'leri eklentiye aittir; bunları ayrıca uygulamanın yerel kodunda atamayın.

**Olay adı akışın adı değildir.** `startFlow`'a paneldeki Flows bölümünde akışın altındaki "Event: …" satırındaki adı
verin. Akış "App event" tetikleyicisiyle kurulmalıdır: "When a conversation starts" tetikleyicili bir akış `startFlow`
ile başlamaz.

## Bağlantılar, dil, sesler ve görünüm

```dart
import 'package:url_launcher/url_launcher.dart';

await Clomni.onLink((url) => launchUrl(Uri.parse(url)));   // null: bağlantıları sistem açar
await Clomni.setLanguage('en');                            // 'az', 'en', 'ru'; null telefona uyar
await Clomni.setSoundsEnabled(false);
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

`pubspec.yaml`'daki yazı tipleri yerel ekranlara ulaşmaz. Her platformun kendi adını verin:

- iOS: uygulama paketindeki ve `ios/Runner/Info.plist`'te `UIAppFonts` altında listelenen bir yazı tipinin aile adı
  (`Montserrat-Regular.ttf` → `'Montserrat'`).
- Android: bir font kaynağı, `android/app/src/main/res/font/montserrat.ttf` → `'montserrat'`.

```dart
await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');
```

## Push bildirimleri

Önce anahtarları panele yükleyin ([Push anahtarları](08-push-keys.md)). Örnekler Android için `firebase_messaging`
kullanır. Token'ı ve mesaj verisini veren her push kütüphanesi işinizi görür.

### Android

Firebase'i [FlutterFire belgelerinde](https://firebase.flutter.dev) anlatıldığı gibi kurun (`flutterfire configure`)
ve izni `android/app/src/main/AndroidManifest.xml` içinde bildirin:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

```dart
import 'dart:io' show Platform;

import 'package:clomni_flutter/clomni_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// Uygulama arka plandayken veya kapalıyken gelen Clomni data mesajları: bildirimi SDK gösterir.
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
  await messaging.requestPermission(); // Android 13+: sistemin izin penceresi
  final token = await messaging.getToken();
  if (token != null) await Clomni.setDeviceToken(token);
  messaging.onTokenRefresh.listen(Clomni.setDeviceToken);
  // Uygulama açıkken gelen mesajlar.
  FirebaseMessaging.onMessage.listen((message) async {
    if (!await Clomni.handlePush(message.data)) {
      // uygulamanın kendi push'u
    }
  });
  await Clomni.setNotificationIcon('ic_notification'); // android/app/src/main/res/drawable/ic_notification.png
}
```

`setUpAndroidPush()`'u Android'de kullanıcılarınıza uygun bir anda çağırın, örneğin oturum açtıktan sonra.

### iOS

Clomni, iOS push'larını Firebase üzerinden değil, doğrudan APNs'e gönderir. `firebase_messaging` yalnızca FCM
üzerinden gönderilen mesajları bildirir; bu yüzden bir Clomni bildirimine dokunulduğunu görmez. Dokunmayı Runner'ın
yerel kodunda bağlayın:

1. Xcode'da (`ios/Runner.xcworkspace`): Runner target'ı → **Signing & Capabilities** → **+ Capability** →
   **Push Notifications**.
2. Runner'ın kendi kodu `ClomniMessenger`'ı import eder. CocoaPods ile yukarıdaki Podfile satırı yeterlidir. Swift
   Package Manager ile paketi Runner target'ına da ekleyin: **File → Add Package Dependencies**,
   `https://github.com/clomni/clomni-mobile-sdk.git`, ürün `ClomniMessenger`, target Runner.
3. Bu dosyayı Runner target'ına ekleyin:

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

4. `AppDelegate.swift` içinde, `super.application(...)`'dan **önce** onu bildirim delegate'i yapın:

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

`firebase_messaging`, `super.application(...)` sırasında delegate'i devralır ve kendisine ait olmayan her push'u bu
delegate'e iletir; böylece FCM kendi push'larınız için çalışmaya devam eder.

5. APNs token'ını Dart'tan iletin:

```dart
if (Platform.isIOS) {
  await FirebaseMessaging.instance.requestPermission();
  final apnsToken = await FirebaseMessaging.instance.getAPNSToken(); // hex
  if (apnsToken != null) await Clomni.setDeviceToken(apnsToken);
}
```

iOS'ta Firebase yoksa token'ı yerel olarak iletin: `AppDelegate` içinde
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` metodunu override edin,
`Clomni.setDeviceToken(deviceToken)` ve ardından `super` çağırın.

## Sorunlar

| Belirti | Ne yapmalı |
|---|---|
| `pod install` durup bir `pod 'ClomniMessenger'` satırı yazıyor | O satırı `ios/Podfile` içinde `target 'Runner'` bloğuna ekleyin |
| Android: yüzen düğme görünmüyor ya da Messenger açılırken uygulama çöküyor | `MainActivity`, `FlutterFragmentActivity`'den türemelidir |
| Uygulama kapalıyken Android bildirimleri görünmüyor | `FirebaseMessaging.onBackgroundMessage`'ı `runApp`'ten önce, üst düzey bir fonksiyonla kaydedin |
| iOS: `ClomniNotifications.swift` içinde `No such module 'ClomniMessenger'` | Paketi veya pod'u Runner target'ına ekleyin (2. adım) |
| iOS'ta bir Clomni bildirimine dokunmak yalnızca uygulamayı açıyor | Delegate (3. ve 4. adımlar) eksik ya da `super.application(...)`'dan sonra atanmış |

Dart tarafındaki hatalar Flutter logunda `[Clomni]` ile başlar; yerel loglar logcat'te (etiket `Clomni`) ve Xcode
konsolundadır. Daha fazlası: [Sorun giderme](09-troubleshooting.md).
