# Sürümler

## 1.0.3

Tüm paketler 1.0.3: Android, iOS, React Native, Flutter ve Unity (`unity-1.0.3` etiketi).

- Mikrofon düğmesi dokunulduğu anda yanıt verir: daire, sayaç ve titreşim hemen gelir.
- Bir saniyelik basış da kaydedilir, "basılı tutun" ipucu artık çıkmaz.

Güncellemek için sürümü 1.0.3 yapın: Android `ai.clomni:messenger:1.0.3`, React Native `@clomni/react-native@1.0.3`,
Flutter `clomni_flutter: ^1.0.3`, Unity `#unity-1.0.3`, iOS `from: "1.0.3"` veya `:tag => '1.0.3'`.

## 1.0.2

| Paket | Sürüm |
|---|---|
| Android `ai.clomni:messenger` | 1.0.2 |
| React Native `@clomni/react-native` | 1.0.2 |
| Flutter `clomni_flutter` | 1.0.2 |
| Unity | `unity-1.0.2` etiketi |
| iOS `ClomniMessenger` | 1.0.2 |

### Ne değişti

- Sesli mesaj: mikrofon düğmesini basılı tutun. Sola kaydırmak iptal eder, yukarı kaydırmak kilitler. Göndermeden önce
  dinleyebilirsiniz, hız 1×, 1.5× ve 2×.
- Kamerayla fotoğraf ve video.
- İnternet yokken yazılan mesajlar sırada bekler ve bağlantı gelince gider.
- `clomni.ai` gibi `https://` içermeyen adresler de bağlantı olur.
- Yüzen düğme `initialize` geç çağrıldığında da görünür (React Native, Flutter, Unity).
- Android: `MainActivity` `singleTask` olan uygulamada Messenger kaybolmaz.
- Uygulama yeniden açıldığında kullanıcının adı kaybolmaz.
- "Konuşmaya katıldı" satırı doğru yerde görünür.
- "Siz" yazısının yanında şirketin logosu var.
- Akış, devamı olmayan bir seçenekte biter ve yazma alanı açılır.
- iPhone'da yazma alanı klavyeye yapışık kalır.
- `debug` düzeyinde SDK'nın adımları loga yazılır.
- Messenger'ın dili internet varken ve yokken aynıdır.
- Emoji düğmesi kaldırıldı; yazma alanının sağında mikrofon düğmesi var.

### İzinler

- Android: sesli mesaj için uygulamanın manifestinde `RECORD_AUDIO` bildirilmelidir, yoksa mikrofon düğmesi görünmez.
  Kamera için izin gerekmez. Bkz. [Android → Gereksinimler](03-android.md#gereksinimler).
- iOS: `NSCameraUsageDescription` ve `NSMicrophoneUsageDescription`. Bkz. [iOS → Info.plist](04-ios.md#infoplist).

### Nasıl güncellenir

- **Android:** `implementation("ai.clomni:messenger:1.0.2")`.
- **React Native:** `npm install @clomni/react-native@1.0.2`, ardından uygulamayı yeniden build edin (iOS'ta `pod
  install`).
- **Flutter:** `clomni_flutter: ^1.0.2`, ardından `flutter pub get`.
- **Unity:** paket adresi `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.2`, ardından **Force
  Resolve**.
- **iOS:** Swift Package Manager'da `from: "1.0.2"`, CocoaPods'ta `:tag => '1.0.2'`. Bu kez iOS kodu da değişti.

## 1.0.1

| Paket | Sürüm |
|---|---|
| Android `ai.clomni:messenger` | 1.0.1 |
| React Native `@clomni/react-native` | 1.0.1 |
| Flutter `clomni_flutter` | 1.0.1 |
| Unity | `unity-1.0.1` etiketi |
| iOS `ClomniMessenger` | 1.0.0, değişmedi |

### Ne değişti

Android SDK bağlanırken uygulamanın paket adını gönderir. Clomni bunu gelen kutusunun "Android package name" değeriyle
karşılaştırır ve eşleşmezse anahtarı reddeder. iOS'ta Bundle ID ile aynı kontrol baştan beri vardı. React Native,
Flutter ve Unity 1.0.1 Android'de bu yeni SDK'yı kullanır. iOS tarafı değişmedi.

### Kimi etkiler

Android uygulaması olanları. Gelen kutusundaki Android paket adı uygulamanın `applicationId` değeriyle aynıysa hiçbir
şey değişmez. Farklıysa, 1.0.1'den sonra Android uygulaması bağlanamaz. Gelen kutusunda Android paket adı yoksa kontrol
de yoktur.

`applicationIdSuffix` da paket adına dahildir. `.debug` son ekli bir debug build'in paket adı
`com.example.app.debug` olur ve `com.example.app` yazılı gelen kutusunda kabul edilmez. Test için son eksiz bir build
kullanın ya da debug uygulaması için ayrı bir gelen kutusu oluşturun.

### Güncellemeden önce

Gelen kutusunun Android paket adı `app/build.gradle(.kts)` içindeki `applicationId` ile aynı olmalıdır. Paket adı
gelen kutusu oluşturulurken sihirbazda girilir; panelde sonradan değiştirilecek bir yer yoktur. Yanlışsa uygulamanın
doğru paket adını Clomni AI'ye yazın, Clomni ekibi düzeltir.

### Nasıl güncellenir

- **Android:** `implementation("ai.clomni:messenger:1.0.1")`, ardından Gradle sync.
- **React Native:** `npm install @clomni/react-native@1.0.1`, ardından uygulamayı yeniden build edin.
- **Flutter:** `pubspec.yaml` içinde `clomni_flutter: ^1.0.1`, ardından `flutter pub get`.
- **Unity:** Package Manager'da paketin adresini
  `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1` yapın (veya `Packages/manifest.json`
  içinde `#unity-1.0.1`), ardından **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
- **iOS:** bir şey yapmanız gerekmez.

### Eşleşmediğinde

Messenger açılmaz; sunucu anahtarı 401 `invalid_api_key` ile reddeder. Logcat'te, `Clomni` etiketiyle (SDK bu
mesajı Azerbaycanca yazar):

```text
api_key səhvdir və ya bu platforma üçün deyil. Tətbiqin paket adı: com.example.app.debug; paneldəki Android paket adı ilə eyni olmalıdır (applicationIdSuffix da sayılır)
```

Logdaki paket adını paneldekiyle karşılaştırın.

## 1.0.0

İlk sürüm: Android, iOS, React Native, Flutter ve Unity.
