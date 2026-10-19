# Versiyalar

## 1.0.6

| Paket | Versiya |
|---|---|
| Android `ai.clomni:messenger` | 1.0.6 |
| React Native `@clomni/react-native` | 1.0.6 |
| Flutter `clomni_flutter` | 1.0.6 |
| Unity | `unity-1.0.6` teqi |
| iOS `ClomniMessenger` | 1.0.4, dəyişməyib |

Yalnız Android dəyişib. Tətbiq bağlı olanda gələn push onu ekransız işə salır. SDK bunu tətbiqin açıq olması sayıb
serverlə əlaqə açırdı, server də istifadəçini onlayn görürdü: panel "cavab push ilə çatdırılacaq" yazmırdı və
birincidən sonrakı cavablar üçün push getmirdi. İndi əlaqə tətbiqin ekranlarından biri açılanda qurulur. SDK-nı gec
işə salan tətbiqlərdə (React Native, Flutter, Unity) də tətbiqdən çıxanda əlaqə bağlanır, push-lar arxa planda gəlir.
Kodda heç nə dəyişmir.

Yeniləmək üçün: Android `ai.clomni:messenger:1.0.6`, React Native `@clomni/react-native@1.0.6`, Flutter
`clomni_flutter: ^1.0.6`, Unity `#unity-1.0.6` (sonra EDM4U ilə resolve). iOS 1.0.4-də qalır.

## 1.0.5

| Paket | Versiya |
|---|---|
| Android `ai.clomni:messenger` | 1.0.5 |
| React Native `@clomni/react-native` | 1.0.5 |
| Flutter `clomni_flutter` | 1.0.5 |
| Unity | `unity-1.0.5` teqi |
| iOS `ClomniMessenger` | 1.0.4, dəyişməyib |

Yalnız Android dəyişib. SDK-nın kamerası indi öz FileProvider sinfini işlədir. Əvvəl tətbiq və ya başqa kitabxana
(məsələn, Unity oyunundakı unity-webview) da androidx FileProvider-i işlədəndə Android build manifest birləşməsində
dayana bilirdi: `provider#androidx.core.content.FileProvider@authorities … collides with another value`. 1.0.5 onlarla
yanaşı qurulur. Bu xətaya görə `tools:replace` əlavə etmisinizsə, silin. Başqa heç nə dəyişmir.

Yeniləmək üçün: Android `ai.clomni:messenger:1.0.5`, React Native `@clomni/react-native@1.0.5`, Flutter
`clomni_flutter: ^1.0.5`, Unity `#unity-1.0.5` (sonra EDM4U ilə resolve). iOS 1.0.4-də qalır.

## 1.0.4

Bütün paketlər 1.0.4-dür: Android, iOS, React Native, Flutter və Unity (`unity-1.0.4` teqi).

- Düymə addımında "Müştəri yaza bilməsin" söndürülübsə, yazı qutusu düymələrin altında qalır. Müştəri düymə seçə və ya
  cavabı yaza bilər.
- "Yazmanı bağla" addımından sonra müştəri bu söhbətə yaza bilmir. Kilid flow bitəndən sonra da qalır: söhbət
  bağlıdırsa, müştəriyə yalnız "Yeni söhbət başlat" qalır. Sual addımında, operatora ötürəndə və ya operator yazanda
  yazı qutusu qayıdır.
- Bu ayarları işlətməyən flow-lar əvvəlki kimi işləyir. Köhnə SDK versiyaları bu ayarları görmür və əvvəlki kimi
  davranır.

Yeniləmək üçün versiyanı 1.0.4 edin: Android `ai.clomni:messenger:1.0.4`, React Native `@clomni/react-native@1.0.4`,
Flutter `clomni_flutter: ^1.0.4`, Unity `#unity-1.0.4`, iOS `from: "1.0.4"` və ya `:tag => '1.0.4'`.

## 1.0.3

Bütün paketlər 1.0.3-dür: Android, iOS, React Native, Flutter və Unity (`unity-1.0.3` teqi).

- Mikrofon düyməsi toxunan kimi cavab verir: dairə, taymer və titrəmə dərhal gəlir.
- Bir saniyəlik basış da yazılır, "basıb saxlayın" ipucu artıq çıxmır.

Yeniləmək üçün versiyanı 1.0.3 edin: Android `ai.clomni:messenger:1.0.3`, React Native `@clomni/react-native@1.0.3`,
Flutter `clomni_flutter: ^1.0.3`, Unity `#unity-1.0.3`, iOS `from: "1.0.3"` və ya `:tag => '1.0.3'`.

## 1.0.2

| Paket | Versiya |
|---|---|
| Android `ai.clomni:messenger` | 1.0.2 |
| React Native `@clomni/react-native` | 1.0.2 |
| Flutter `clomni_flutter` | 1.0.2 |
| Unity | `unity-1.0.2` teqi |
| iOS `ClomniMessenger` | 1.0.2 |

### Nə dəyişib

- Səsli mesaj: mikrofon düyməsini basıb saxlayın. Sola sürüşdürmək ləğv edir, yuxarı sürüşdürmək kilidləyir.
  Göndərməzdən əvvəl dinləmək olar, sürət 1×, 1.5× və 2×.
- Kamera ilə şəkil və video.
- İnternet olmayanda yazılan mesajlar növbədə gözləyir və internet qayıdanda gedir.
- `clomni.ai` kimi `https://`-siz ünvanlar da link olur.
- Üzən düymə `initialize` gec çağırılanda da görünür (React Native, Flutter, Unity).
- Android: `MainActivity` `singleTask` olan tətbiqdə Messenger itmir.
- Tətbiq yenidən açılanda istifadəçinin adı itmir.
- "Söhbətə qoşuldu" sətri öz yerində görünür.
- "Siz" yazısının yanında şirkətin loqosu var.
- Flow davamı olmayan seçimdə bitir və yazı yeri açılır.
- iPhone-da yazı yeri klaviaturaya yapışıq qalır.
- `debug` səviyyəsində SDK-nın addımları loga yazılır.
- Messenger-in dili internet olanda və olmayanda eynidir.
- Emoji düyməsi çıxıb, yazı yerinin sağında mikrofon düyməsi var.

### İcazələr

- Android: səsli mesaj üçün tətbiqin manifestində `RECORD_AUDIO` elan olunmalıdır, yoxsa mikrofon düyməsi görünmür.
  Kamera üçün icazə lazım deyil. Bax: [Android → Tələblər](03-android.md#tələblər).
- iOS: `NSCameraUsageDescription` və `NSMicrophoneUsageDescription`. Bax: [iOS → Info.plist](04-ios.md#infoplist).

### Necə yeniləmək olar

- **Android:** `implementation("ai.clomni:messenger:1.0.2")`.
- **React Native:** `npm install @clomni/react-native@1.0.2`, sonra tətbiqi yenidən build edin (iOS-da `pod install`).
- **Flutter:** `clomni_flutter: ^1.0.2`, sonra `flutter pub get`.
- **Unity:** paketin ünvanı `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.2`, sonra **Force
  Resolve**.
- **iOS:** Swift Package Manager-də `from: "1.0.2"`, CocoaPods-da `:tag => '1.0.2'`. Bu dəfə iOS kodu da dəyişib.

## 1.0.1

| Paket | Versiya |
|---|---|
| Android `ai.clomni:messenger` | 1.0.1 |
| React Native `@clomni/react-native` | 1.0.1 |
| Flutter `clomni_flutter` | 1.0.1 |
| Unity | `unity-1.0.1` teqi |
| iOS `ClomniMessenger` | 1.0.0, dəyişməyib |

### Nə dəyişib

Android SDK qoşulanda tətbiqin paket adını göndərir. Clomni onu kanalın "Android paket adı" ilə müqayisə edir və
uyğun gəlməsə açarı rədd edir. iOS-da Bundle ID ilə eyni yoxlama əvvəldən var idi. React Native, Flutter və Unity
1.0.1 Android-də bu yeni SDK-nı işlədir. iOS tərəfi dəyişməyib.

### Kimə təsir edir

Android tətbiqi olanlara. Kanaldakı Android paket adı tətbiqin `applicationId`-si ilə eynidirsə, heç nə dəyişmir.
Fərqlidirsə, 1.0.1-dən sonra Android tətbiqi qoşulmur. Kanalda Android paket adı yazılmayıbsa, yoxlama yoxdur.

`applicationIdSuffix` da paket adına daxildir. Debug build-in `.debug` suffiksi varsa, onun paket adı
`com.example.app.debug` olur və `com.example.app` yazılmış kanalda qəbul olunmur. Sınaq üçün suffiksi olmayan
build işlədin, ya da debug tətbiqi üçün ayrıca kanal yaradın.

### Yeniləməzdən əvvəl

Kanalın Android paket adı `app/build.gradle(.kts)`-dəki `applicationId` ilə eyni olmalıdır. Paket adı kanal
yaradılanda sehrbazda yazılır, sonra paneldə onu dəyişmək yeri yoxdur. Səhv yazılıbsa, Clomni AI-yə tətbiqin düzgün
paket adını yazın, Clomni komandası düzəldir.

### Necə yeniləmək olar

- **Android:** `implementation("ai.clomni:messenger:1.0.1")`, sonra Gradle sync.
- **React Native:** `npm install @clomni/react-native@1.0.1`, sonra tətbiqi yenidən build edin.
- **Flutter:** `pubspec.yaml`-da `clomni_flutter: ^1.0.1`, sonra `flutter pub get`.
- **Unity:** Package Manager-də paketin ünvanını
  `https://github.com/clomni/clomni-mobile-sdk.git?path=unity#unity-1.0.1` edin (və ya `Packages/manifest.json`-da
  `#unity-1.0.1`), sonra **Assets → External Dependency Manager → Android Resolver → Force Resolve**.
- **iOS:** heç nə etmək lazım deyil.

### Uyğun gəlməyəndə

Messenger açılmır, server açarı 401 `invalid_api_key` ilə rədd edir. Logcat-da, `Clomni` tag-ı ilə:

```text
api_key səhvdir və ya bu platforma üçün deyil. Tətbiqin paket adı: com.example.app.debug; paneldəki Android paket adı ilə eyni olmalıdır (applicationIdSuffix da sayılır)
```

Logdakı paket adını paneldəki ilə müqayisə edin.

## 1.0.0

İlk buraxılış: Android, iOS, React Native, Flutter və Unity.
