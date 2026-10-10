# React Native

`@clomni/react-native` paketi yerel Android ve iOS SDK'larını sarar. Ekranlar yerel ekranlardır.

## Gereksinimler

- React Native 0.75 veya daha yenisi (New Architecture için 0.76 veya daha yenisi). Development build'de Expo SDK 52
  veya daha yenisi.
- iOS 15, Android 6.0 (API 23).
- Gelen kutusunun ayarlar sütununda **Installation** bölümünden App ID ve her iki API anahtarı (`android_…`, `ios_…`).

## Kurulum

```sh
npm install @clomni/react-native
cd ios && pod install
```

Gerisini autolinking halleder. Android'de modül `ai.clomni:messenger` paketini Maven Central'dan getirir. iOS'ta
`pod install`, iOS SDK'yı Pods projesine bir Swift paketi olarak ekler (React Native'in `spm_dependency`'si) ve Xcode
onu ilk build'de indirir.

iOS linkleme adımı `ClomniMessenger` sembollerinde hata verirse (React Native, statik pod'lardaki bir Swift paketinin
"might cause linker errors" uyarısını verir) ya da push'u aşağıdaki gibi yerel kodda bağlıyorsanız, iOS SDK'yı
uygulamanın target'ına pod olarak ekleyin. Paket bu durumda o pod'u kullanır ve Swift paketi eklemez:

```ruby
# ios/Podfile, uygulamanın target'ı içinde
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.2'
```

### Expo

Expo Go yerel modülleri yükleyemez. Bir development build kullanın (`npx expo prebuild`, `npx expo run:ios` /
`run:android` veya bir EAS build). Paketin config plugin'i yerel projelerin ihtiyaç duyduğu her şeyi yazar:

```ts
// app.config.ts
export default {
  // ...
  plugins: [
    ['@clomni/react-native', {
      photoLibraryPermission: 'Destek ekibine fotoğraf göndermek için',        // iOS
      cameraPermission: 'Fotoğraf çekip destek ekibine göndermek için',         // iOS
      push: true,                                                               // varsayılan
      notificationIcon: './assets/notification-icon.png',                       // Android, beyaz siluet PNG
    }],
  ],
};
```

`push: true` ile plugin iOS'ta `aps-environment` entitlement'ını ve `remote-notification` arka plan modunu,
Android'de ise `POST_NOTIFICATIONS` iznini ekler. Simge `clomni_notification_icon` drawable'ı olarak kopyalanır.

Expo kullanmayan (bare) bir React Native uygulamasında iki iOS metnini `Info.plist`'e kendiniz ekleyin
([iOS bölümüne](04-ios.md#infoplist) bakın).

iOS'ta uygulamanın `Info.plist` dosyasına fotoğraf, kamera ve mikrofon için izin metinlerini ekleyin: [iOS →
Info.plist](04-ios.md#infoplist). Android'de sesli mesaj (SDK 1.0.2'den itibaren) için uygulamanın manifestinde
`RECORD_AUDIO` bildirilmelidir: [Android → Gereksinimler](03-android.md#gereksinimler).

## Başlatma

Bir kez, uygulamanın açılışında, herhangi bir bileşenin dışında. `index.js` iyi bir yerdir, çünkü bir push
uygulamayı ekran olmadan başlatabilir.

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

`initialize`'ın üçüncü parametresi `region`'dır, varsayılanı `'eu'`. Şu an yalnızca `'eu'` var, yazmanıza gerek yok:
başka bir değer verilirse SDK bunu loga yazar ve `'eu'` kullanır.

## Kullanıcı

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, hashFromYourServer);
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });

// Uygulamanın kendi oturum kapatma işlemiyle birlikte:
Clomni.logout();
```

Hash için bkz. [Kullanıcıların tanınması](02-identity.md).

Kullanıcı oturum açmışsa, uygulama her açıldığında `loginUser`'ı yeni giriş yapmış gibi yeniden çağırın. Aynı kullanıcı
için SDK kayıtlı oturumunu kullanır.

Oturum açmamış bir kullanıcı için bir şey çağırmanız gerekmez: Messenger açıldığında anonim ziyaretçiyi kendisi
oluşturur. `Clomni.loginUnidentifiedUser()` bunu önceden yapar. Ziyaretçi `logout`'a kadar bu cihazda aynı kalır;
`loginUser` çağrıldığında konuşmaları kullanıcıya geçer.

## Messenger'ı açma

```tsx
import { useEffect, useState } from 'react';
import { Pressable, Text } from 'react-native';
import Clomni from '@clomni/react-native';

export function SupportRow() {
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    // Güncel sayıyı hemen, sonra her değişikliği alır.
    const subscription = Clomni.addEventListener('unreadCountChanged', setUnread);
    return () => subscription.remove();
  }, []);

  return (
    <Pressable onPress={() => Clomni.present('profile_support')}>
      <Text>Destek{unread > 0 ? ` (${unread})` : ''}</Text>
    </Pressable>
  );
}
```

| Çağrı | Ne yapar |
|---|---|
| `Clomni.present(source?)` | Ana sayfayı açar |
| `Clomni.presentNewConversation(source?)` | Doğrudan yeni bir konuşma açar |
| `Clomni.presentConversation(id)` | Bilinen bir konuşmayı açar; ID `conversationStarted`'dan gelir |
| `Clomni.dismiss()` | Messenger'ı koddan kapatır |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | İsteğe bağlı yüzen düğme |

## Akışlar ve olaylar

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });

const subscriptions = [
  Clomni.addEventListener('messengerOpened', (source) => console.log('opened from', source)),
  Clomni.addEventListener('messengerClosed', () => console.log('closed')),
  Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id)),
  Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId)),
];
// daha sonra: subscriptions.forEach((s) => s.remove());
```

Akışın panelde aynı adla "App event" tetikleyicisine sahip olması ve yayınlanmış olması gerekir. Veri JSON
olmalıdır.

Yerel SDK'nın olay callback'leri modüle aittir. Bunları ayrıca uygulamanın yerel kodunda atamayın.

**Olay adı akışın adı değildir.** `startFlow`'a paneldeki Flows bölümünde akışın altındaki "Event: …" satırındaki adı
verin. Akış "App event" tetikleyicisiyle kurulmalıdır: "When a conversation starts" tetikleyicili bir akış `startFlow`
ile başlamaz.

## Bağlantılar, dil, sesler ve görünüm

```ts
import { Linking } from 'react-native';

Clomni.onLink((url) => Linking.openURL(url));   // veya kendi yönlendiriciniz; null: bağlantıları sistem açar
Clomni.setLanguage('en');                       // 'az', 'en', 'ru'; null telefona uyar
Clomni.setSoundsEnabled(false);
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

Yazı tipi, `fontFamily` stillerinde kullandığınız aile adıdır. iOS'ta yazı tipi uygulamada bulunmalı ve
`UIAppFonts` altında listelenmelidir; Android'de React Native onu `android/app/src/main/assets/fonts` veya `res/font`
içinde bulur. Yalnızca yazı tipi için: `Clomni.setTypeface('Montserrat')`.

## Push bildirimleri

Önce anahtarları panele yükleyin ([Push anahtarları](08-push-keys.md)). Örnekler Android için
`@react-native-firebase/messaging` kullanır. Token'ı ve mesaj verisini veren her push kütüphanesi işinizi görür.

### Android

Firebase kurulumu: [React Native Firebase belgelerinde](https://rnfirebase.io) anlatıldığı gibi
`google-services.json` ve Google services Gradle eklentisi. Ardından:

```js
// index.js, initialize'ın yanında
import messaging from '@react-native-firebase/messaging';

// Uygulama arka plandayken veya kapalıyken gelen Clomni data mesajları: bildirimi SDK gösterir.
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
  // Uygulama açıkken gelen mesajlar.
  const unsubscribeMessage = messaging().onMessage(async (message) => {
    if (!Clomni.handlePush(message.data ?? {})) {
      // uygulamanın kendi push'u
    }
  });
  Clomni.setNotificationIcon('clomni_notification_icon');   // config plugin'in notificationIcon'u
  return () => { unsubscribeToken(); unsubscribeMessage(); };
}, []);
```

Bare bir uygulamada `AndroidManifest.xml` içinde
`<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />` bildirin,
`android/app/src/main/res/drawable/` klasörüne beyaz bir simge koyun ve adını `setNotificationIcon`'a verin.

### iOS

Clomni, iOS push'larını Firebase üzerinden değil, doğrudan APNs'e gönderir. Firebase kütüphanesi yalnızca FCM
üzerinden gönderilen mesajları bildirir; bu yüzden bir Clomni bildirimine dokunulduğunu görmez. Dokunmayı yerel
kodda bağlayın:

1. Xcode'da Push Notifications capability'sini ekleyin ([iOS bölümüne](04-ios.md#1-capability) bakın).
2. `ios/Podfile` dosyasına `pod 'ClomniMessenger'` satırını ekleyin (yukarıdaki Kurulum'a bakın); böylece
   uygulamanın kendi kodu `import ClomniMessenger` yapabilir. `pod install` çalıştırın.
3. Bu dosyayı uygulama target'ına ekleyin:

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

4. `application(_:didFinishLaunchingWithOptions:)` içinde, metot dönmeden önce onu bildirim delegate'i yapın:

```swift
// AppDelegate.swift
UNUserNotificationCenter.current().delegate = ClomniNotifications.shared
```

```objc
// AppDelegate.mm, uygulamanın delegate'i Objective-C ise
#import "YourApp-Swift.h"
#import <UserNotifications/UserNotifications.h>

[UNUserNotificationCenter currentNotificationCenter].delegate = ClomniNotifications.shared;
```

React Native Firebase açılıştan sonra delegate'i devralır ve kendisine ait olmayan her push'u bu delegate'e iletir;
böylece FCM kendi push'larınız için çalışmaya devam eder.

5. APNs token'ını JavaScript'ten iletin:

```ts
if (Platform.OS === 'ios') {
  await messaging().requestPermission();
  const apnsToken = await messaging().getAPNSToken();   // hex
  if (apnsToken) Clomni.setDeviceToken(apnsToken);
}
```

iOS'ta Firebase yoksa token'ı bunun yerine yerel olarak iletin:
`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` içinde `Clomni.setDeviceToken(deviceToken)`,
[iOS bölümündeki](04-ios.md#2-appdelegate) gibi.

Bir Expo uygulamasında `ios` klasörünü `npx expo prebuild` üretir. 3. ve 4. adımları kendi küçük config plugin'inizde
tutun (`expo/config-plugins`'ten `withAppDelegate` ve `withXcodeProject`) ya da üretilen `ios` klasörünü commit edin.

`Clomni.isClomniPush(data)`, bir Clomni push'unu sizin push'larınızdan ayırt eder.

## Sorunlar

| Belirti | Ne yapmalı |
|---|---|
| "The package doesn't seem to be linked" ya da yerel modül bulunamıyor | Kurulumdan sonra uygulamayı yeniden build edin. Expo'da Expo Go değil, development build kullanın |
| iOS'ta `ClomniMessenger` sembollerinde linkleme hataları | Podfile'a `pod 'ClomniMessenger'` satırını ekleyin ve `pod install` çalıştırın |
| Uygulama kapalıyken Android bildirimleri görünmüyor | `setBackgroundMessageHandler`, bileşenlerin dışında, `index.js` içinde kaydedilmelidir |
| iOS'ta bir Clomni bildirimine dokunmak yalnızca uygulamayı açıyor | Yerel delegate (3. ve 4. adımlar) eksik ya da açılıştan sonra atanmış |
| Yüzen düğme uygulamanın soğuk açılışında görünmüyor | SDK 1.0.2'de düzeliyor. O zamana kadar Messenger'ı kendi düğmenizden açın |
| Android: uygulama simgesinden yeniden açılınca açık Messenger kayboluyor (`MainActivity` `singleTask`) | SDK 1.0.2'de düzeliyor |

Loglar yerel taraftadır: Android'de logcat etiketi `Clomni`, iOS'ta Xcode konsolu. Varsayılan düzey `warning`'dir,
entegrasyon hataları `error` olarak yazılır; `setLogLevel('debug')` ayrıca SDK'nın adımlarını gösterir. Daha fazlası:
[Sorun giderme](09-troubleshooting.md).
