# React Native

`@clomni/react-native` paketi native Android və iOS SDK-larının üstündədir. Ekranlar native ekranlardır.

## Tələblər

- React Native 0.75 və ya daha yeni (New Architecture üçün 0.76 və ya daha yeni). Expo SDK 52 və ya daha yeni,
  development build ilə.
- iOS 15, Android 6.0 (API 23).
- Paneldə kanalın ayarlar sütununun **Quraşdırma** bölməsindən App ID və hər iki API açarı (`android_…`, `ios_…`).

## Quraşdırma

```sh
npm install @clomni/react-native
cd ios && pod install
```

Qalanını autolinking edir. Android-də modul `ai.clomni:messenger`-i Maven Central-dan gətirir. iOS-da `pod install`
iOS SDK-nı Pods layihəsinə Swift package kimi əlavə edir (React Native-in `spm_dependency`-si), Xcode isə onu ilk
build-də yükləyir.

iOS-da link `ClomniMessenger` simvollarında xəta verirsə (React Native statik pod-lardakı Swift package üçün "might
cause linker errors" xəbərdarlığı verir), ya da push-u aşağıdakı kimi native kodda bağlayırsınızsa, iOS SDK-nı
tətbiqin target-inə pod kimi əlavə edin. Onda paket həmin pod-u işlədir və Swift package əlavə etmir:

```ruby
# ios/Podfile, tətbiqin target-ində
pod 'ClomniMessenger', :git => 'https://github.com/clomni/clomni-mobile-sdk.git', :tag => '1.0.3'
```

### Expo

Expo Go native modulları yükləyə bilmir. Development build işlədin (`npx expo prebuild`, `npx expo run:ios` /
`run:android` və ya EAS build). Paketin config plugin-i native layihələrə lazım olanları yazır:

```ts
// app.config.ts
export default {
  // ...
  plugins: [
    ['@clomni/react-native', {
      photoLibraryPermission: 'Dəstəyə şəkil göndərmək üçün',        // iOS
      cameraPermission: 'Şəkil çəkib dəstəyə göndərmək üçün',        // iOS
      push: true,                                                   // standart dəyər
      notificationIcon: './assets/notification-icon.png',           // Android, ağ siluet PNG
    }],
  ],
};
```

`push: true` ilə plugin iOS-da `aps-environment` entitlement-ini və `remote-notification` background mode-u,
Android-də isə `POST_NOTIFICATIONS` icazəsini əlavə edir. İkon `clomni_notification_icon` adlı drawable kimi
köçürülür.

Adi (bare) React Native tətbiqində iOS-un iki mətnini `Info.plist`-ə özünüz əlavə edin
([iOS bölməsinə](04-ios.md#infoplist) baxın).

iOS-da tətbiqin `Info.plist`-inə şəkil, kamera və mikrofon üçün icazə mətnlərini əlavə edin: [iOS →
Info.plist](04-ios.md#infoplist). Android-də səsli mesaj üçün (SDK 1.0.2-dən) tətbiqin manifestində `RECORD_AUDIO` elan
olunmalıdır: [Android → Tələblər](03-android.md#tələblər).

## Başlatma

Bir dəfə, tətbiq açılanda, heç bir komponentin içində olmadan. `index.js` yaxşı yerdir, çünki push tətbiqi ekransız
başlada bilər.

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

`initialize`-in üçüncü parametri `region`-dur, standart dəyəri `'eu'`-dur. Hazırda yalnız `'eu'` var, onu yazmaq lazım
deyil: başqa dəyər verilsə, SDK bunu loga yazır və `'eu'` işlədir.

## İstifadəçi

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, hashFromYourServer);
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });

// Tətbiqin öz çıxışı ilə birlikdə:
Clomni.logout();
```

Hash üçün bax: [İstifadəçinin tanıdılması](02-identity.md).

Tətbiq hər açılanda, istifadəçi daxil olubsa, `loginUser`-i yenidən çağırın, istifadəçi təzə daxil olmuş kimi. Eyni
istifadəçi üçün SDK saxlanmış sessiyanı işlədir.

Daxil olmamış istifadəçi üçün heç nə çağırmaq lazım deyil: Messenger açılanda anonim ziyarətçini özü yaradır.
`Clomni.loginUnidentifiedUser()` bunu əvvəlcədən edir. Ziyarətçi `logout`-a qədər bu cihazda eyni qalır, `loginUser`
çağırılanda onun söhbətləri istifadəçiyə keçir.

## Messenger-i açmaq

```tsx
import { useEffect, useState } from 'react';
import { Pressable, Text } from 'react-native';
import Clomni from '@clomni/react-native';

export function SupportRow() {
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    // Cari sayı dərhal, sonra hər dəyişikliyi eşidir.
    const subscription = Clomni.addEventListener('unreadCountChanged', setUnread);
    return () => subscription.remove();
  }, []);

  return (
    <Pressable onPress={() => Clomni.present('profile_support')}>
      <Text>Dəstək{unread > 0 ? ` (${unread})` : ''}</Text>
    </Pressable>
  );
}
```

| Çağırış | Nə edir |
|---|---|
| `Clomni.present(source?)` | Ana səhifəni açır |
| `Clomni.presentNewConversation(source?)` | Birbaşa yeni söhbət açır |
| `Clomni.presentConversation(id)` | Məlum söhbəti açır; ID `conversationStarted`-dən gəlir |
| `Clomni.dismiss()` | Messenger-i koddan bağlayır |
| `Clomni.setLauncherVisible(true)`, `Clomni.setBottomPadding(72)` | İstəyə bağlı üzən düymə |

## Flow-lar və hadisələr

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });

const subscriptions = [
  Clomni.addEventListener('messengerOpened', (source) => console.log('opened from', source)),
  Clomni.addEventListener('messengerClosed', () => console.log('closed')),
  Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id)),
  Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId)),
];
// sonra: subscriptions.forEach((s) => s.remove());
```

Flow üçün paneldə eyni adla "Tətbiq hadisəsi" trigger-i lazımdır və flow dərc olunmalıdır. Data JSON olmalıdır.

Native SDK-nın hadisə callback-lərini modul özü tutur. Onları tətbiqin native kodunda ayrıca təyin etməyin.

**Hadisənin adı flow-un adı deyil.** `startFlow`-a paneldəki Flow-lar bölməsində flow-un altındakı "Hadisə: …"
sətrindəki adı verin. Flow "Tətbiq hadisəsi" trigger-i ilə qurulmalıdır: "Söhbət başlayanda" trigger-li flow `startFlow`
ilə başlamır.

## Linklər, dil, səslər və görünüş

```ts
import { Linking } from 'react-native';

Clomni.onLink((url) => Linking.openURL(url));   // və ya öz router-iniz; null: linkləri sistem açır
Clomni.setLanguage('en');                       // 'az', 'en', 'ru'; null telefonun dilinə uyğunlaşır
Clomni.setSoundsEnabled(false);
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

Şrift `fontFamily` stillərində işlətdiyiniz ailə adıdır. iOS-da şrift tətbiqdə olmalı və `UIAppFonts` altında
yazılmalıdır. Android-də React Native onu `android/app/src/main/assets/fonts` və ya `res/font` qovluğunda tapır.
Yalnız şrift üçün: `Clomni.setTypeface('Montserrat')`.

## Push bildirişləri

Əvvəlcə açarları panelə yükləyin ([Push açarları](08-push-keys.md)). Nümunələr Android üçün
`@react-native-firebase/messaging` işlədir. Tokeni və mesajın datasını verən istənilən push kitabxanası olar.

### Android

Firebase-in qurulması: `google-services.json` və Google services Gradle plugin-i,
[React Native Firebase sənədlərində](https://rnfirebase.io) yazıldığı kimi. Sonra:

```js
// index.js, initialize-in yanında
import messaging from '@react-native-firebase/messaging';

// Tətbiq arxa planda və ya bağlı olanda gələn Clomni data mesajları: bildirişi SDK göstərir.
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
  // Tətbiq açıq olanda gələn mesajlar.
  const unsubscribeMessage = messaging().onMessage(async (message) => {
    if (!Clomni.handlePush(message.data ?? {})) {
      // tətbiqin öz push-u
    }
  });
  Clomni.setNotificationIcon('clomni_notification_icon');   // config plugin-in notificationIcon-u
  return () => { unsubscribeToken(); unsubscribeMessage(); };
}, []);
```

Adi tətbiqdə `AndroidManifest.xml`-də `<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />`
elan edin, ağ ikonu `android/app/src/main/res/drawable/` qovluğuna qoyun və adını `setNotificationIcon`-a verin.

### iOS

Clomni iOS push-larını Firebase-dən keçirmədən birbaşa APNs-ə göndərir. Firebase kitabxanası yalnız FCM-dən gələn
mesajları bildirir, ona görə Clomni bildirişinə toxunuşu görmür. Toxunuşu native kodda bağlayın:

1. Xcode-da Push Notifications capability-sini əlavə edin ([iOS bölməsinə](04-ios.md#1-capability) baxın).
2. `ios/Podfile`-a `pod 'ClomniMessenger'` sətrini əlavə edin (yuxarıdakı Quraşdırma hissəsinə baxın), ki tətbiqin
   öz kodu `import ClomniMessenger` edə bilsin. `pod install` işlədin.
3. Bu faylı tətbiq hədəfinə əlavə edin:

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

4. Onu `application(_:didFinishLaunchingWithOptions:)` içində, metod qayıtmazdan əvvəl bildiriş delegate-i edin:

```swift
// AppDelegate.swift
UNUserNotificationCenter.current().delegate = ClomniNotifications.shared
```

```objc
// AppDelegate.mm, tətbiqin delegate-i Objective-C-dədirsə
#import "YourApp-Swift.h"
#import <UserNotifications/UserNotifications.h>

[UNUserNotificationCenter currentNotificationCenter].delegate = ClomniNotifications.shared;
```

React Native Firebase açılışdan sonra delegate-i öz üzərinə götürür və özünə aid olmayan hər push-u bu delegate-ə
ötürür. Ona görə öz push-larınız üçün FCM işləməyə davam edir.

5. APNs tokenini JavaScript-dən verin:

```ts
if (Platform.OS === 'ios') {
  await messaging().requestPermission();
  const apnsToken = await messaging().getAPNSToken();   // hex
  if (apnsToken) Clomni.setDeviceToken(apnsToken);
}
```

iOS-da Firebase yoxdursa, tokeni native kodda verin: `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
içində `Clomni.setDeviceToken(deviceToken)`, [iOS bölməsindəki](04-ios.md#2-appdelegate) kimi.

Expo tətbiqində `ios` qovluğunu `npx expo prebuild` yaradır. 3-cü və 4-cü addımları öz kiçik config plugin-inizdə
saxlayın (`expo/config-plugins`-dən `withAppDelegate` və `withXcodeProject`), ya da yaradılmış `ios` qovluğunu
repozitoriyada saxlayın.

`Clomni.isClomniPush(data)` Clomni push-unu sizin push-larınızdan ayırır.

## Problemlər

| Əlamət | Nə etməli |
|---|---|
| "The package doesn't seem to be linked" və ya native modul tapılmır | Quraşdırmadan sonra tətbiqi yenidən build edin. Expo-da Expo Go yox, development build işlədin |
| iOS-da `ClomniMessenger` simvolları üzrə link xətaları | Podfile-a `pod 'ClomniMessenger'` sətrini əlavə edin və `pod install` işlədin |
| Android-də tətbiq bağlı olanda bildirişlər gəlmir | `setBackgroundMessageHandler` `index.js`-də, komponentlərdən kənarda qeydə alınmalıdır |
| iOS-da Clomni bildirişinə toxunanda yalnız tətbiq açılır | Native delegate (3-cü və 4-cü addımlar) yoxdur və ya açılışdan sonra təyin olunur |
| Üzən düymə tətbiqin soyuq açılışında görünmür | SDK 1.0.2-də düzəlir. O vaxta qədər Messenger-i öz düymənizdən açın |
| Android: tətbiq ikonla yenidən açılanda açıq Messenger itir (`MainActivity` `singleTask`-dır) | SDK 1.0.2-də düzəlir |

Loglar native tərəfdədir: Android-də logcat, `Clomni` tag-i; iOS-da Xcode konsolu. Standart səviyyə `warning`-dir,
inteqrasiya səhvləri `error` kimi yazılır; `setLogLevel('debug')` bundan əlavə SDK-nın addımlarını göstərir. Daha çoxu:
[Problemlərin həlli](09-troubleshooting.md).
