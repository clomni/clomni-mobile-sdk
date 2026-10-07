# Clomni Messenger mobil SDK: inteqrasiya

Bu sənəd Clomni Messenger-i iOS, Android, React Native və ya Flutter tətbiqinə qoşmaq üçündür. Hər addımda dörd
nümunə var: Kotlin (Android), Swift (iOS), TypeScript (React Native), Dart (Flutter).

Messenger tətbiqin içində native ekranlarla açılır, WebView işlətmir. Clomni-də hər tətbiq bir "Mobil tətbiq
(App SDK)" kanalıdır: mesajlar operatorlara düşür, flow-lar (dil seçimi, menyu düymələri, operatora ötürmə) burada
native düymələrlə işləyir.

| Platforma | Minimum |
|---|---|
| Android | Android 6.0 (API 23) |
| iOS | iOS 15, Xcode 15 |
| React Native | React Native 0.72 (New Architecture üçün 0.76); Expo SDK 50, development build ilə |
| Flutter | Flutter 3.16; iOS 15, Android API 24 |

## 1. Panel tərəfi

Clomni panelində: **Kanallar → Kanal əlavə et → Mobil tətbiq (App SDK)**. Sehrbazın addımları: Tətbiq məlumatı,
Quraşdırma, Identity verification, Push bildirişləri, Görünüş, Flow-lar.

Kanal bunları verir:

| Açar | Harada saxlanır |
|---|---|
| App ID (`app_…`) | tətbiqdə |
| Android API açarı (`android_…`) | Android tətbiqində |
| iOS API açarı (`ios_…`) | iOS tətbiqində |
| Identity Secret | **yalnız serverinizdə** |

- API açarları tam şəkildə yalnız "Quraşdırma" addımında görünür. Sonra panel yalnız əvvəlini göstərir. Yeni açar
  kanal səhifəsində yaradılır.
- Identity Secret də bir dəfə göstərilir. Onu dərhal serverdə saxlayın (məsələn, `CLOMNI_IDENTITY_SECRET`).
- API açarı platformaya bağlıdır: Android tətbiqində iOS açarı işləmir.

Sonradan hər şey kanal səhifəsinin tablarındadır: Ümumi baxış, Quraşdırma, Təhlükəsizlik, Push, Görünüş, Flow-lar,
Analitika.

## 2. Quraşdırma

> Paketlər hələ dərc olunmayıb. Aşağıdakı adlar və `1.0.0` versiyası dərc olunandan sonra işləyəcək.

**Android** (Maven Central):

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("ai.clomni:messenger:1.0.0")
}
```

SDK özü heç bir icazə istəmir və tətbiqin ekranlarına heç nə əlavə etmir.

**iOS**, Swift Package Manager: File → Add Package Dependencies →
`https://github.com/rzayevkenann/clomni-mobile-sdk.git`, versiya `1.0.0`, məhsul `ClomniMessenger`.

**iOS**, CocoaPods:

```ruby
pod 'ClomniMessenger', '~> 1.0'
```

**React Native**:

```sh
npm install @clomni/react-native
cd ios && pod install
```

Expo-da development build lazımdır (`npx expo prebuild` və ya EAS build). Expo Go native modulları yükləyə bilmir.
Paketin config plugin-i native layihələrə lazım olanı yazır:

```ts
// app.config.ts
plugins: [
  ['@clomni/react-native', {
    photoLibraryPermission: 'Dəstəyə şəkil göndərmək üçün',      // iOS
    cameraPermission: 'Dəstəyə şəkil çəkib göndərmək üçün',        // iOS
    push: true,                                                   // default
    notificationIcon: './assets/notification-icon.png',           // Android, ağ siluet PNG
  }],
],
```

**Flutter**:

```sh
flutter pub add clomni_flutter
```

Android-də tətbiqin `MainActivity`-si `FlutterFragmentActivity`-dən törəməlidir, `FlutterActivity`-dən yox:

```kotlin
class MainActivity : FlutterFragmentActivity()
```

## 3. Başlatma: `initialize`

Tətbiq açılanda bir dəfə çağırın. İkinci çağırış nəzərə alınmır.

```kotlin
// Android: Application.onCreate-də (manifestdə android:name ilə). Bildiriş tətbiqi başladanda SDK hazır olmalıdır.
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Clomni.initialize(this, appId = "app_…", apiKey = "android_…")
    }
}
```

```swift
// iOS: AppDelegate
import ClomniMessenger

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Clomni.initialize(appId: "app_…", apiKey: "ios_…")
    return true
}
```

```ts
// React Native
import { Platform } from 'react-native';
import Clomni from '@clomni/react-native';

Clomni.initialize('app_…', Platform.OS === 'ios' ? 'ios_…' : 'android_…');
```

```dart
// Flutter
import 'dart:io' show Platform;
import 'package:clomni_flutter/clomni_flutter.dart';

await Clomni.initialize('app_…', Platform.isIOS ? 'ios_…' : 'android_…');
```

`Clomni`-nin bütün metodlarını istənilən thread-dən çağırmaq olar. Callback-lər main thread-də gəlir.

## 4. İstifadəçi: `loginUser` və `user_hash`

Giriş olmayanda messenger anonim ziyarətçi üçün açılır. Ziyarətçi `logout`-a qədər bu cihazda saxlanır. İstifadəçi
tətbiqinizə girəndə onu Clomni-yə ötürün. Ziyarətçinin söhbətləri istifadəçiyə keçir.

1. İstifadəçi tətbiqinizə girir.
2. Serveriniz Identity Secret ilə `user_hash` hesablayır və öz API cavabında tətbiqə qaytarır.
3. Tətbiq `loginUser` çağırır.

```kotlin
val user = ClomniUser(userId = "12345", email = "aysel@example.com", name = "Aysel Məmmədova")
Clomni.loginUser(user, userHash = userHashFromYourServer)
```

```swift
let user = ClomniUser(userId: "12345", email: "aysel@example.com", name: "Aysel Məmmədova")
Clomni.loginUser(user, userHash: userHashFromYourServer)
```

```ts
Clomni.loginUser({ userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova' }, userHashFromYourServer);
```

```dart
await Clomni.loginUser(
  const ClomniUser(userId: '12345', email: 'aysel@example.com', name: 'Aysel Məmmədova'),
  userHash: userHashFromYourServer,
);
```

Ad, dil (`az`, `en`, `ru`) və əlavə atributları sonra dəyişmək üçün `updateUser`. Yalnız verilən sahələr dəyişir,
`customAttributes` mövcud atributlarla birləşir:

```kotlin
Clomni.updateUser(language = "az", customAttributes = mapOf("plan" to "premium"))
```

```swift
Clomni.updateUser(language: "az", customAttributes: ["plan": "premium"])
```

```ts
Clomni.updateUser({ language: 'az', customAttributes: { plan: 'premium' } });
```

```dart
await Clomni.updateUser(language: 'az', customAttributes: {'plan': 'premium'});
```

### `user_hash` serverdə necə hesablanır

```
user_hash = hex(HMAC-SHA256(identity_secret, user_id))
```

- Nəticə kiçik hərfli hex-dir, 64 simvol.
- `user_id` sətir kimi, `loginUser`-ə verdiyiniz ilə eyni olmalıdır.
- `userId` yoxdursa, hash email üzərindən hesablanır: kiçik hərflə, boşluqsuz (trim).

> **Diqqət.** Identity Secret heç vaxt tətbiqə qoyulmur: nə koda, nə `BuildConfig`-ə, nə `Info.plist`-ə, nə də
> tətbiqlə gedən `.env`-ə. Tətbiqi açıb secret-i çıxarmaq olar. Secret-i tapan hər kəs başqa istifadəçinin
> söhbətlərini aça bilər. Hash yalnız serverinizdə hesablanır.

```ruby
# Ruby
require 'openssl'
user_hash = OpenSSL::HMAC.hexdigest('SHA256', ENV.fetch('CLOMNI_IDENTITY_SECRET'), user.id.to_s)
```

```js
// Node.js
const crypto = require('crypto');
const userHash = crypto.createHmac('sha256', process.env.CLOMNI_IDENTITY_SECRET).update(String(user.id)).digest('hex');
```

```go
// Go
import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"os"
)

func clomniUserHash(userID string) string {
	mac := hmac.New(sha256.New, []byte(os.Getenv("CLOMNI_IDENTITY_SECRET")))
	mac.Write([]byte(userID))
	return hex.EncodeToString(mac.Sum(nil))
}
```

```php
// PHP
$userHash = hash_hmac('sha256', (string) $user->id, getenv('CLOMNI_IDENTITY_SECRET'));
```

```python
# Python
import hashlib, hmac, os
user_hash = hmac.new(os.environ["CLOMNI_IDENTITY_SECRET"].encode(), str(user.id).encode(), hashlib.sha256).hexdigest()
```

Yoxlama üçün: secret `test_secret` və `user_id` `12345` olanda hash
`b01354f5d4c60c56ca76a26c064b9629b0d2a73e169b63b6514b974a9714cf24` olmalıdır. Öz hash-inizi panelin
**Təhlükəsizlik** tabında "Hash-i yoxla" ilə yoxlaya bilərsiniz.

### Rejimlər

Rejim **Təhlükəsizlik** tabında seçilir:

| Rejim | Nə edir |
|---|---|
| Söndürülüb (`off`) | Hash yoxlanmır, istifadəçi təsdiqlənmir. Yalnız sınaq üçün. |
| Tövsiyə olunan (`recommended`, default) | Göndərilən hash düzgün olmalıdır, səhvdirsə giriş rədd olunur. Hash yoxdursa istifadəçi qəbul olunur, amma təsdiqlənmir. Bir dəfə təsdiqlənmiş giriş edən istifadəçi üçün sonra hash məcburidir. |
| Məcburi (`enforced`) | Düzgün hash olmadan giriş olmur (`403 identity_verification_failed`). Tətbiqdə ilk təsdiqlənmiş girişdən sonra seçilə bilər. Hash göndərməyən köhnə tətbiq versiyaları qoşula bilməyəcək. |

Secret-i dəyişmək: Təhlükəsizlik → "Yeni secret yarat". Köhnə secret 7 gün də işləyir; bu müddətdə serverinizi
yenisinə keçirin.

## 5. Messenger-i açmaq

Tətbiq istəməyincə Clomni-dən heç nə görünmür. Messenger-i öz düymənizlə açın. `source` tətbiqin harasından
açıldığını bildirir və burada başlayan söhbətlə birlikdə saxlanır.

```kotlin
supportButton.setOnClickListener { Clomni.present(source = "profile_support") }
```

```swift
Button("Dəstək") { Clomni.present(source: "profile_support") }
```

```ts
<Button title="Dəstək" onPress={() => Clomni.present('profile_support')} />
```

```dart
ListTile(title: const Text('Dəstək'), onTap: () => Clomni.present(source: 'profile_support'))
```

Digər çağırışlar: `presentNewConversation(source)` birbaşa yeni söhbət açır, `presentConversation(id)` məlum söhbəti
açır (id `onConversationStarted`-dən gəlir), `dismiss()` messenger-i koddan bağlayır.

Düymənin yanında oxunmamış mesajların sayı:

```kotlin
private val unread = UnreadCountListener { count -> supportBadge.text = count.toString() }

override fun onStart() { super.onStart(); Clomni.addUnreadCountListener(unread) }
override fun onStop() { Clomni.removeUnreadCountListener(unread); super.onStop() }
```

```swift
let token = Clomni.addUnreadCountListener { count in badgeCount = count }
// lazım olmayanda:
Clomni.removeUnreadCountListener(token)
```

```ts
const subscription = Clomni.addEventListener('unreadCountChanged', (count) => setBadge(count));
// lazım olmayanda:
subscription.remove();
```

```dart
StreamBuilder<int>(
  stream: Clomni.unreadCountStream,
  builder: (context, snapshot) => Text('${snapshot.data ?? 0}'),
)
```

### Launcher (istəyə bağlı)

Üzən düymə default olaraq sönülüdür. Paneldən də yandırmaq olar, tətbiqin seçimi üstündür. `setBottomPadding` onu alt
naviqasiyanın üstünə qaldırır (Android-də dp).

```kotlin
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

```swift
Clomni.setLauncherVisible(true)
Clomni.setBottomPadding(72)
```

```ts
Clomni.setLauncherVisible(true);
Clomni.setBottomPadding(72);
```

```dart
await Clomni.setLauncherVisible(true);
await Clomni.setBottomPadding(72);
```

## 6. Hadisələr və flow trigger

Tətbiqin bir ekranındakı düymə müəyyən mövzuda söhbət başlada bilər, məsələn gedişlə bağlı problem.

**Paneldə:** Flow qurucuda trigger olaraq "Tətbiq hadisəsi" seçin, hadisənin adını yazın (`ride_problem`) və flow-u
dərc edin. Kanalın **Flow-lar** tabında flow "Hadisə: ride_problem" kimi görünür.

**Tətbiqdə:** `startFlow` hadisəni məlumatla birlikdə göndərir. Flow mətnlərində məlumat `{{data.ride_id}}` kimi
işlənir. Məlumat JSON olmalıdır: sətir, rəqəm, boolean, siyahı, map.

```kotlin
Clomni.startFlow("ride_problem", mapOf("ride_id" to "R-1923"), openMessenger = true, source = "ride_screen")
```

```swift
Clomni.startFlow("ride_problem", data: ["ride_id": "R-1923"], openMessenger: true, source: "ride_screen")
```

```ts
Clomni.startFlow('ride_problem', { ride_id: 'R-1923' }, { openMessenger: true, source: 'ride_screen' });
```

```dart
await Clomni.startFlow('ride_problem', data: {'ride_id': 'R-1923'}, openMessenger: true, source: 'ride_screen');
```

- Hadisəyə bağlı dərc olunmuş flow yoxdursa, heç nə baş vermir.
- İstifadəçinin özünün basmadığı hadisədə (məsələn, ödəniş alınmadı) `openMessenger`-i `false` saxlayın. İstifadəçi
  söhbətdən push və ya oxunmamış sayı ilə xəbər tutur.

### SDK-nın hadisələri

`onMessengerOpened` (source), `onMessengerClosed`, `onConversationStarted` (söhbətin id-si), `onFlowCompleted`
(flow-un id-si) və oxunmamış sayı.

```kotlin
Clomni.onConversationStarted { id -> Log.d("App", "conversation $id") }
Clomni.onFlowCompleted { flowId -> Log.d("App", "flow $flowId") }
```

```swift
Clomni.onConversationStarted = { id in print("conversation \(id)") }
Clomni.onFlowCompleted = { flowId in print("flow \(flowId)") }
```

```ts
Clomni.addEventListener('conversationStarted', (id) => console.log('conversation', id));
Clomni.addEventListener('flowCompleted', (flowId) => console.log('flow', flowId));
```

```dart
Clomni.onConversationStarted.listen((id) => debugPrint('conversation $id'));
Clomni.onFlowCompleted.listen((flowId) => debugPrint('flow $flowId'));
```

Native SDK-da hər hadisənin bir dinləyicisi var, `null` onu silir. React Native və Flutter paketləri native
callback-ləri özləri tutur: tətbiqin native kodu onları ayrıca təyin etməməlidir.

## 7. Push bildirişləri

**Paneldə**, kanalın **Push** tabında:

- Android: Firebase layihəsinin service account JSON faylı.
- iOS: APNs `.p8` faylı, Key ID, Team ID, Bundle ID.

Yükləyəndən sonra "Test push" ilə yoxlayın.

Tətbiq tokeni və gələn push-ları SDK-ya ötürür. Öz push-larınız sizdə qalır: `isClomniPush` Clomni push-larını
ayırır.

### Android

SDK-nın Firebase asılılığı yoxdur. Tətbiq öz `firebase-messaging`-ini saxlayır:

```kotlin
class AppMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Clomni.setDeviceToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (ClomniPush.handle(this, message.data)) return
        // tətbiqin öz push-u
    }
}
```

```xml
<!-- AndroidManifest.xml -->
<service android:name=".AppMessagingService" android:exported="false">
    <intent-filter>
        <action android:name="com.google.firebase.MESSAGING_EVENT" />
    </intent-filter>
</service>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

FCM `onNewToken`-i yalnız token dəyişəndə çağırır. Ona görə cari tokeni başlanğıcda da ötürün:

```kotlin
FirebaseMessaging.getInstance().token.addOnSuccessListener(Clomni::setDeviceToken)
```

Android 13+ bildiriş icazəsini tətbiq özü istəyir (SDK istəmir):

```kotlin
if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
```

Bildirişi SDK göstərir. Ona basanda tətbiq açılır və messenger həmin söhbətdə üstdə açılır. Messenger açıq olanda
Clomni bildirişləri göstərilmir. Kiçik ikon tətbiqin ikonudur; ağ siluet lazımdırsa:

```kotlin
Clomni.setNotificationIcon(R.drawable.ic_notification)
```

### iOS

Tətbiq hədəfinə Push Notifications capability əlavə edin.

```swift
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Clomni.initialize(appId: "app_…", apiKey: "ios_…")
        UNUserNotificationCenter.current().delegate = self
        Task {
            let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted == true { UIApplication.shared.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Clomni.setDeviceToken(deviceToken)
    }

    // Tətbiq açıq olanda gələn push. Messenger açıqdırsa Clomni push-u göstərilmir.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Clomni.shouldShowForeground(notification.request.content.userInfo) ? [.banner, .list, .sound] : []
    }

    // Bildirişə basanda: Clomni push-u öz söhbətini açır. nonisolated yox, @MainActor: sistem bu metodu arxa
    // thread-dən çağıra bilər, Swift isə sistemin completion handler-ini metod harada bitirsə orada çağırır. Main
    // thread-dən kənarda çağırılanda UIKit tətbiqi dayandırır ("Call must be made on main thread").
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if Clomni.handlePush(response.notification.request.content.userInfo) { return }
        // tətbiqin öz push-u
    }
}
```

Operatorun şəkli bildirişdə görünsün deyə istəyə bağlı Notification Service Extension:
`ios/Examples/NotificationService`.

### React Native

```ts
import messaging from '@react-native-firebase/messaging';

const token = Platform.OS === 'ios' ? await messaging().getAPNSToken() : await messaging().getToken();
if (token) Clomni.setDeviceToken(token);   // iOS: APNs tokeni hex kimi; Android: FCM tokeni

if (Platform.OS === 'android') {
  // Clomni data mesajları: bildirişi SDK göstərir.
  messaging().onMessage((message) => { Clomni.handlePush(message.data ?? {}); });
  messaging().setBackgroundMessageHandler(async (message) => { Clomni.handlePush(message.data ?? {}); });
  Clomni.setNotificationIcon('clomni_notification_icon');   // config plugin-in notificationIcon-u
} else {
  // Bildirişə basanda söhbət açılır.
  messaging().onNotificationOpenedApp((message) => { Clomni.handlePush(message.data ?? {}); });
}

// iOS, tətbiq açıq olanda gələn push:
const show = Clomni.shouldShowForeground(data);
```

### Flutter

Token və push məlumatı tətbiqin öz push kitabxanasından gəlir:

```dart
await Clomni.setDeviceToken(token); // iOS: APNs tokeni hex kimi; Android: FCM tokeni

// iOS: bildirişə basanda (onun data-sı). Android: FCM data mesajı gələndə (RemoteMessage.data);
// bildirişi SDK göstərir, ona basanda söhbət açılır.
if (!await Clomni.handlePush(data)) {
  // tətbiqin öz push-u
}

// iOS, tətbiq açıq olanda gələn push:
final show = await Clomni.shouldShowForeground(data);
```

Android-də ikon: `await Clomni.setNotificationIcon('drawable_name');`

## 8. Görünüş

Rənglər, loqo, başlıq, Ana səhifənin kartları və mətnlər paneldən, kanalın **Görünüş** tabından gəlir. Dəyişiklik
tətbiqi yeniləmədən çatır: dərc olunan dəyişiklik açıq ekranda yumşaq keçidlə görünür.

Tətbiqin öz rəngini, şriftini və rejimini panelin görünüşü üzərinə qoymaq üçün `setTheme`. Rəng `#RRGGBB`
formatındadır, digər brend rəngləri ondan panelin qaydaları ilə alınır. Hər çağırış əvvəlkini əvəz edir. Verilməyən
dəyər panelinki qalır.

```kotlin
Clomni.setTheme(
    primaryColor = "#0A66C2",
    typeface = ResourcesCompat.getFont(context, R.font.montserrat),
    mode = ClomniThemeMode.DARK,
)
```

```swift
Clomni.setTheme(primaryColor: "#0A66C2", typeface: "Montserrat", mode: .dark)
```

```ts
Clomni.setTheme({ primaryColor: '#0A66C2', typeface: 'Montserrat', mode: 'dark' });
```

```dart
await Clomni.setTheme(primaryColor: '#0A66C2', mode: ClomniThemeMode.dark);
```

Rejim: light, dark və ya system. Yalnız şrift lazımdırsa `setTypeface`. Şrift istifadəçinin şrift ölçüsünə uyğun
qalır.

- iOS: tətbiq paketindəki şriftin family adı, `Info.plist`-də `UIAppFonts` altında (`Montserrat-Regular.ttf` →
  `'Montserrat'`).
- Android: şrift resursu (`res/font/montserrat.xml` və ya `montserrat.ttf`).
- Flutter: `pubspec.yaml`-dakı şriftlər native ekranlara özbaşına çatmır. Hər platformaya öz adı ilə verin:
  `await Clomni.setTypeface(Platform.isIOS ? 'Montserrat' : 'montserrat');`

## 9. Dil, səs, linklər

**Dil.** Messenger paneldə (Görünüş tabı) yandırılmış dillərdə danışır. `setLanguage` onlardan birini seçir (`az`,
`en`, `ru`). `null` və ya paneldə sönülü dil telefonun dilinə baxır, o da yoxdursa panelin əsas dili işlənir.
Paneldə bir dil yanılıdırsa, həmişə o işlənir.

**Səs.** Söhbət açıq olanda gələn və göndərilən mesaj üçün qısa səs. Telefonun səssiz rejiminə tabedir. Panel onu
söndürə bilər; `setSoundsEnabled(false)` paneldən asılı olmayaraq söndürür.

**Linklər.** Xəbər kartının düyməsi veb ünvan və ya tətbiqin öz deep link-i ola bilər. `onLink` olanda link
tətbiqə gəlir.

```kotlin
Clomni.setLanguage("en")
Clomni.setSoundsEnabled(false)
// true: link tətbiqdə açıldı; false və ya dinləyici yoxdursa sistem açır.
Clomni.onLink { url ->
    val ownLink = url.startsWith("myapp://")
    if (ownLink) startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    ownLink
}
```

```swift
Clomni.setLanguage("en")
Clomni.setSoundsEnabled(false)
// Dinləyici varsa linki tətbiq açır, yoxdursa sistem.
Clomni.onLink = { url in UIApplication.shared.open(url) }
```

```ts
import { Linking } from 'react-native';

Clomni.setLanguage('en');
Clomni.setSoundsEnabled(false);
Clomni.onLink((url) => Linking.openURL(url)); // null: linki sistem açır
```

```dart
// launchUrl: url_launcher paketindən
await Clomni.setLanguage('en');
await Clomni.setSoundsEnabled(false);
await Clomni.onLink((url) => launchUrl(Uri.parse(url))); // null: linki sistem açır
```

## 10. Logout

Tətbiqin öz logout-u ilə birlikdə çağırın. Sessiyanı bitirir və messenger-in bu cihazdakı məlumatını silir. Çağırılmasa,
telefonun növbəti istifadəçisi əvvəlkinin söhbətlərini görər.

```kotlin
Clomni.logout()
```

```swift
Clomni.logout()
```

```ts
Clomni.logout();
```

```dart
await Clomni.logout();
```

## 11. Problemlərin həlli

İnkişaf zamanı logları açın. Default səviyyə `warning`-dir; inteqrasiya xətaları `error` kimi yazılır.

```kotlin
if (BuildConfig.DEBUG) Clomni.setLogLevel(ClomniLogLevel.DEBUG)
```

```swift
#if DEBUG
Clomni.setLogLevel(.debug)
#endif
```

```ts
if (__DEV__) Clomni.setLogLevel('debug');
```

```dart
if (kDebugMode) await Clomni.setLogLevel(ClomniLogLevel.debug);
```

Loglar harada:

- Android: logcat, tag `Clomni`.
- iOS: Xcode konsolu və Console.app, subsystem `ai.clomni.messenger`, category `Clomni`.
- React Native və Flutter: yuxarıdakı native loglar. Flutter-də Dart tərəfinin xətaları `[Clomni]` ilə başlayır.

Tez-tez rast gəlinən xətalar:

| Log və ya əlamət | Səbəb | Nə etməli |
|---|---|---|
| `api_key səhvdir və ya bu platforma üçün deyil` | Açar səhvdir, ləğv olunub və ya başqa platformanındır | Android-də `android_…`, iOS-da `ios_…` açarı |
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | Hash uyğun gəlmir | Eyni `user_id` sətri, kiçik hərfli hex, cari secret; `userId` yoxdursa kiçik hərfli email. Təhlükəsizlik → "Hash-i yoxla" |
| `call Clomni.initialize first` | Metod `initialize`-dan əvvəl çağırılıb | `initialize` başlanğıcda (Android-də `Application.onCreate`) |
| `initialize was called before; the first call stays` | `initialize` iki dəfə çağırılıb | Bir dəfə çağırın |
| `this App SDK inbox is switched off in Clomni` | Kanal paneldə söndürülüb | Kanalı yandırın; o vaxta qədər `present()` heç nə etmir |
| `setTheme: primaryColor "…" is not #RRGGBB` | Rəng formatı | `#RRGGBB` |
| `startFlow` heç nə etmir | Hadisəyə bağlı dərc olunmuş flow yoxdur | Flow qurucuda "Tətbiq hadisəsi", eyni ad, dərc edin |
| Android: bildiriş yoxdur, `notification not shown (POST_NOTIFICATIONS?)` | İcazə verilməyib | Android 13+ `POST_NOTIFICATIONS` istəyin |
| Android: `push token not registered: …` | Token serverə çatmayıb | `setDeviceToken` çağırışı, paneldə Firebase JSON |
| iOS: push gəlmir | Capability, `.p8` və ya Bundle ID | Push tabında açarlar, "Test push" |
| iOS: `no window to present the messenger from` | `present` pəncərə yaranmamış çağırılıb | Ekran göründükdən sonra çağırın |
| iOS: `font family "…" is not in the app; the system font stays` | Şrift paketdə deyil | `UIAppFonts`-a əlavə edin |
| React Native: native modul tapılmır | Expo Go | Development build (`npx expo prebuild`) |
| Flutter, Android: launcher görünmür | `MainActivity` | `FlutterFragmentActivity` |
