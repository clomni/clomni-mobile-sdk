# Problemlərin həlli

## Əvvəlcə haraya baxmalı

1. **Panelin Ümumi baxış bölməsi.** Orada hər platformanın qoşulub-qoşulmadığı, push-un aktiv olub-olmadığı və "səhv
   hash səbəbindən rədd olunan girişlər", "push qurulmayıb" kimi xəbərdarlıqlar görünür, hər birinin yanında
   **Düzəlt** düyməsi var.
2. **SDK-nın logu.** Standart səviyyə `warning`-dir: xəbərdarlıqlar və xətalar həmişə yazılır, inteqrasiya səhvləri
   (açar, hash, push) `error` kimi yazılır. Tərtibat zamanı `debug` səviyyəsini yandırın: o, bundan əlavə SDK-nın
   addımlarını da yazır.

| Platforma | Yandırmaq | Log harada |
|---|---|---|
| Android | `Clomni.setLogLevel(ClomniLogLevel.DEBUG)` | logcat, `Clomni` tag-i |
| iOS | `Clomni.setLogLevel(.debug)` | Xcode konsolu və Console.app: subsystem `ai.clomni.messenger`, category `Clomni` |
| React Native | `Clomni.setLogLevel('debug')` | yuxarıdakı native loglar |
| Flutter | `await Clomni.setLogLevel(ClomniLogLevel.debug)` | yuxarıdakı native loglar; Dart tərəfinin xətaları `[Clomni]` ilə başlayır |
| Unity | `Clomni.SetLogLevel(ClomniLogLevel.Debug)` | yuxarıdakı native loglar |

SDK-nın öz mesajları ingiliscədir, serverdən gələn bəzi mesajlar isə Azərbaycan dilindədir. Cədvəldə hər ikisi
logda göründüyü kimi yazılıb.

## Quraşdırma

| Log və ya əlamət | Səbəb | Nə etməli |
|---|---|---|
| `call Clomni.initialize first` | Metod `initialize`-dən əvvəl çağırılıb | `initialize`-i açılışda çağırın; Android-də `Application.onCreate`-də |
| `initialize was called before; the first call stays` | `initialize` iki dəfə çağırılıb | Bir dəfə çağırın. Açarı dəyişmək üçün tətbiqi yenidən başladın |
| `api_key səhvdir və ya bu platforma üçün deyil` | API açarı səhvdir, ləğv olunub, yeni açar yaradılandan 7 gün keçib, ya da o biri platformanındır | Android-də `android_…`, iOS-da `ios_…` açarı. Açarı **Quraşdırma** bölməsində yoxlayın |
| Android 1.0.1+: `api_key səhvdir ... Tətbiqin paket adı: …` | Tətbiqin paket adı (`applicationIdSuffix` daxil) kanalın Android paket adı ilə eyni deyil | Logdakı paket adını paneldəki ilə müqayisə edin, bax [Versiyalar](10-versions.md) |
| `this App SDK inbox is switched off in Clomni` | Kanal paneldə söndürülüb | Onu yandırın. O vaxta qədər `present()` heç nə etmir |
| Heç nə açılmır, logda heç nə yoxdur | Log səviyyəsi aşağıdır, ya da çağırış Unity Editor-dadır | Debug səviyyəsini yandırın; cihazda sınayın |
| `setTheme: primaryColor "…" is not #RRGGBB` | Rəngin formatı | `#` ilə altı hex rəqəm, məsələn `#0A66C2` |
| iOS: `no window to present the messenger from yet` | `present` ekran yaranmamış çağırılıb | Onu düymədən və ya ekran göstəriləndən sonra çağırın |
| iOS: `font family "…" is not in the app; the system font stays` | Şrift bundle-da yoxdur | Onu hədəfə və `UIAppFonts`-a əlavə edin |
| Tətbiq şirkət şəbəkəsində serverə çata bilmir | Proxy və ya icazə siyahısı hostu bloklayır | `app.clomni.ai`-a icazə verin (HTTPS və WebSocket) |

## İstifadəçilər

| Log və ya əlamət | Səbəb | Nə etməli |
|---|---|---|
| `user_hash səhvdir. identity_secret və user_id-ni yoxlayın` | Hash uyğun gəlmir | `loginUser`-dəki ilə eyni `user_id` sətri, kiçik hərfli hex, cari secret. `userId` yoxdursa, kənar boşluqları silinmiş kiçik hərfli e-poçt. Təhlükəsizlik → Hash-i yoxla ilə yoxlayın |
| `403 identity_verification_failed` | Məcburi rejimdə hash yoxdur və ya səhvdir | Hash göndərin, ya da bütün tətbiq versiyaları göndərənə qədər Tövsiyə olunan rejimə qayıdın |
| Telefonun növbəti istifadəçisi əvvəlkinin söhbətlərini görür | `logout` çağırılmır | `Clomni.logout()`-u tətbiqin öz çıxışı ilə çağırın |
| Operatorlar istifadəçinin adını və ya e-poçtunu görmür | `loginUser` onlarsız, ya da login bitməmiş çağırılıb | Sahələri verin; sonrakı dəyişikliklər üçün `updateUser` işlədin |

## Flow-lar, görünüş və mətnlər

| Əlamət | Səbəb | Nə etməli |
|---|---|---|
| `startFlow` heç nə etmir | Hadisəyə bağlı dərc olunmuş flow yoxdur | Flow qurucusunda: "Tətbiq hadisəsi" trigger-i, eyni ad, dərc olunub. **Flow-lar** bölməsində hadisənin adı görünür |
| Flow mətnində `{{data.…}}` boş qalır | `startFlow` datasındakı açarın adı başqadır | Tətbiqdə və flow-da eyni açarı işlədin |
| Paneldəki dəyişiklik tətbiqdə görünmür | Görünüş qaralaması dərc olunmayıb | Görünüş → **Dərc et** |
| Messenger gözlənilən dildə danışmır | `setLanguage` sönülü dili seçib, ya da heç dil seçilməyib | Dili Görünüş → Dillər bölməsində yandırın və ya `setLanguage` çağırın |
| Üzən düymə görünmür | Həm paneldə, həm kodda sönülüdür | `setLauncherVisible(true)` və ya Görünüş → Tema bölməsində yandırın |
| React Native: üzən düymə tətbiqin soyuq açılışında görünmür | SDK 1.0.1-in xətası | SDK 1.0.2-də düzəlir. O vaxta qədər Messenger-i öz düymənizdən açın |
| React Native, Android: tətbiq ikonla yenidən açılanda açıq Messenger itir | `MainActivity` `singleTask`-dır | SDK 1.0.2-də düzəlir |
| Flutter, Android: üzən düymə görünmür | `MainActivity` `FlutterActivity`-dən törəyir | `FlutterFragmentActivity`-dən törədin |

## Push bildirişləri

Ayarlar sütununda **Push** → **Test bildirişi** bölməsindən başlayın. Oradakı cavab FCM və ya APNs-in öz cavabıdır,
hər cavab [Push açarları](08-push-keys.md#test-bildirişi) bölməsindəki cədvəldə izah olunub.

| Əlamət | Səbəb | Nə etməli |
|---|---|---|
| Cihaz Test bildirişi siyahısında yoxdur | Clomni-yə token çatmayıb | Telefonda bildirişlərə icazə verin; `setDeviceToken` çağırışını yoxlayın; Messenger-i bir dəfə açın |
| Android: bildiriş yoxdur, `notification not shown (POST_NOTIFICATIONS?)` | Android 13+-da icazə yoxdur | `POST_NOTIFICATIONS` istəyin |
| Android: `push token not registered: …` | Token serverə çatmayıb | Şəbəkəni və `setDeviceToken` çağırışını yoxlayın |
| Android: bildirişlər yalnız tətbiq açıq olanda gəlir | Data mesajı yalnız UI-da emal olunur | Mesajı `FirebaseMessagingService`-də `ClomniPush.handle`-a verin (React Native: `setBackgroundMessageHandler`, Flutter: `onBackgroundMessage`) |
| Android: ikon yerinə boz kvadrat | Tətbiqin ikonu siluet deyil | Ağ ikonla `setNotificationIcon` |
| Android: `SENDER_ID_MISMATCH` | Service account və `google-services.json` fərqli Firebase layihələrindəndir | Tətbiqin layihəsinin service account-unu yükləyin |
| iOS: `BadEnvironmentKeyInToken` | APNs açarı bir mühitlə məhdudlaşıb | Sandbox & Production açarı yaradın |
| iOS: `InvalidProviderToken` | Key ID və ya Team ID səhvdir, ya da açar ləğv olunub | Hər iki ID-ni yoxlayın, açarı yenidən yükləyin |
| iOS: `DeviceTokenNotForTopic` | **Push** bölməsindəki Bundle ID tətbiqinki deyil | Tətbiqin Bundle ID-sini yazın |
| iOS: Xcode-dan işləyir, TestFlight-dan yox (və ya əksinə) | Açar yalnız bir mühiti əhatə edir | Sandbox & Production açarı |
| iOS: Clomni bildirişinə toxunanda yalnız tətbiq açılır | Toxunuş `handlePush`-a çatmır | Native iOS: AppDelegate-dəki delegate. React Native və Flutter: öz bölmələrindəki native delegate; Firebase kitabxanaları iOS-da Clomni push-larını görmür |
| iOS: toxunuşda tətbiq "Call must be made on main thread" ilə çökür | Async delegate metodu `nonisolated`-dir | Onu `@MainActor` edin |
| Messenger açıq olanda Clomni bildirişi görünür | `shouldShowForeground` işlədilmir | O false olanda heç bir göstərmə seçimi qaytarmayın |

## Açarlar dəyişəndən sonra

- Yeni API açarı: köhnəsi daha 7 gün işləyir. Ondan sonra köhnə açarlı tətbiq versiyaları qoşula bilmir.
- Ləğv olunan API açarı dərhal dayanır.
- Yeni Identity Secret: köhnəsi daha 7 gün işləyir. Hash-i yoxla hash-in hansı secret ilə hazırlandığını deyir.
- Yeni push açarı: onu **Push** bölməsində yükləyin, növbəti push onu işlədir.

## Kömək istəmək

Clomni dəstəyinə yazın və bunları əlavə edin:

- platforma və SDK versiyası (Kotlin və Swift-də `Clomni.version`);
- App ID (heç vaxt Identity Secret və ya tam API açarı yox);
- **Ümumi baxış** bölməsinin dedikləri və problem anında debug səviyyəsində SDK logu;
- push üçün: Test bildirişinin cavabı.
