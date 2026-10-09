# Sürümler

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
